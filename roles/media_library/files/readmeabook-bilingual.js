// Compatibility patch for the pinned ReadMeABook 1.2.13 ARM64 image.
// Fail closed if upstream changes the compiled code; never guess a patch.
const fs = require('fs');
const crypto = require('crypto');

// The app otherwise hard-filters author pages to the active region's language,
// even with its language filter off. Keep both English and German editions.
const oldAuthor = 'for(let e of u)e.authors?.some(e=>e.asin===t)&&e.language&&(0,o.W)(e.language,a)&&s.push(q(e));let g=';
// Audible assigns multiple IDs to the same author, and sometimes omits IDs.
// Also accept the complete normalized name, keeping only the chosen author's
// contributors and both supported edition languages.
const helper = 'require("/app/frey-author-language.cjs")';
const newAuthor = 'for(let x of u)x.authors?.some(n=>n.asin===t||(n.name&&' + helper + '.key(n.name)===' + helper + '.key(e)))&&x.language&&((0,o.W)(x.language,a)||/^(english|german|deutsch|en|de)$/i.test(x.language.trim()))&&s.push(q(x));{let f=' + helper + ',p=await f.getPreferredLanguage(e);s.sort((x,y)=>Number(f.code(y.language)===p)-Number(f.code(x.language)===p))}let g=';

// For an exact author-name search, use the same author language preference.
// Other searches keep their upstream order.
const oldSearch = 'h=c.map(q);return z.info(` Found ${h.length} results for';
const newSearch = 'h=c.map(q);{let f=' + helper + ';if(h.some(x=>f.key(x.author)===f.key(e))){let p=await f.getPreferredLanguage(e);h.sort((x,y)=>Number(f.key(y.author)===f.key(e)&&f.code(y.language)===p)-Number(f.key(x.author)===f.key(e)&&f.code(x.language)===p))}}return z.info(` Found ${h.length} results for';

function patch(source, verifyDigest = true) {
  const digest = crypto.createHash('sha256').update(source).digest('hex');
  if (verifyDigest && digest !== 'cc876349ea4eb2b87febe587e873dc7ef1b839c8bec4d504950852c4d6bde8fd') {
    throw new Error('Unexpected ReadMeABook author-search bundle; review the patch before upgrading');
  }
  for (const [before, after] of [[oldAuthor, newAuthor], [oldSearch, newSearch]]) {
    if (source.split(before).length !== 2) throw new Error('Expected search code was not unique');
    source = source.replace(before, after);
  }
  return source;
}

function patchMatcher(source, verifyDigest = true) {
  const digest = crypto.createHash('sha256').update(source).digest('hex');
  if (verifyDigest && digest !== '77cb3a0c6681c85d539319d64fcbf605c1bded134b81fbe7dd73cea63313747d') {
    throw new Error('Unexpected ReadMeABook library-matcher bundle; review the patch before upgrading');
  }
  const before = 'if(0===a.length)return s.matchType="no_asin_match",i.debug("Matcher result",{MATCHER:s}),null;';
  const after = 'if(0===a.length){if(typeof e.language==="string"&&/^(german|deutsch|de)$/i.test(e.language.trim())&&e.author){let c=await t.prisma.plexLibrary.findMany({where:{OR:[{asin:null},{asin:""}],author:{equals:e.author,mode:"insensitive"}},select:{plexGuid:!0,plexRatingKey:!0,title:!0,author:!0,asin:!0,narrator:!0}}),m=require("/app/frey-german-library-match.cjs").findGermanMatch(e,c);if(m)return m}return s.matchType="no_asin_match",i.debug("Matcher result",{MATCHER:s}),null;}';
  if (source.split(before).length !== 2) throw new Error('Expected library-matching code was not unique');
  return source.replace(before, after);
}

function patchWorks(source, verifyDigest = true) {
  const digest = crypto.createHash('sha256').update(source).digest('hex');
  if (verifyDigest && digest !== 'aaff4c997723a4fefee91f6931c8f4c907544827fe33a3bc7dc4ef40b575219a') {
    throw new Error('Unexpected ReadMeABook edition-grouping bundle; review the patch before upgrading');
  }
  const lang = variable => '(' + helper + '.code(' + variable + '.language)||String(' + variable + '.language||"").trim().toLowerCase())';
  const groupBefore = '}(n.narrator)}`,a=t.get(e);';
  const groupAfter = '}(n.narrator)}|||${' + lang('n') + '}`,a=t.get(e);';
  const collapseBefore = 'let e=a.get(t.asin);if(!e){i.push(t);continue}let r=o.get(e);';
  const collapseAfter = 'let e=a.get(t.asin);if(!e){i.push(t);continue}e=e+"|||"+' + lang('t') + ';let r=o.get(e);';
  for (const [before, after] of [[groupBefore, groupAfter], [collapseBefore, collapseAfter]]) {
    if (source.split(before).length !== 2) throw new Error('Expected edition-grouping code was not unique');
    source = source.replace(before, after);
  }
  return source;
}

// Some indexers only find ASCII spellings. Search the original title first,
// then try its accent-free spelling only if no usable title was found.
function patchIndexerSearch(source, verifyDigest = true) {
  const digest = crypto.createHash('sha256').update(source).digest('hex');
  if (verifyDigest && digest !== '125b71ec0abc58da30cf9497a5039335d7900c67fba20e946267189dfe0507e0') {
    throw new Error('Unexpected ReadMeABook indexer-search bundle; review the patch before upgrading');
  }
  const before = 'for(let t of[er(e),r&&(er(r)??r)])t&&!n.some(e=>Y(e,t))&&n.push(t);';
  const after = 'for(let t of[er(e),r&&(er(r)??r),e.normalize("NFD").replace(/\\p{M}/gu,""),e.replace(/^(?:the|an|a)\\s+/i,"")])t&&!Y(e,t)&&!n.some(e=>Y(e,t))&&n.push(t);';
  if (source.split(before).length !== 2) throw new Error('Expected indexer fallback code was not unique');
  return source.replace(before, after);
}

if (require.main === module) {
  const path = process.argv[2] || '/app/.next/server/chunks/src_lib_integrations_audible_service_ts_1mow0o0u4euxe._.js';
  fs.writeFileSync(path, patch(fs.readFileSync(path, 'utf8')));
  if (!process.argv[2]) {
    const matcherPath = '/app/.next/server/chunks/src_lib_utils_audiobook-matcher_ts_1dp58968y1rlf._.js';
    fs.writeFileSync(matcherPath, patchMatcher(fs.readFileSync(matcherPath, 'utf8')));
    const worksPath = '/app/.next/server/chunks/src_lib_services_works_service_ts_1of_a6o17-ecz._.js';
    fs.writeFileSync(worksPath, patchWorks(fs.readFileSync(worksPath, 'utf8')));
    const indexerPath = '/app/.next/server/chunks/_0rdhav026snq-._.js';
    fs.writeFileSync(indexerPath, patchIndexerSearch(fs.readFileSync(indexerPath, 'utf8')));
  }
}
module.exports = { patch, patchMatcher, patchWorks, patchIndexerSearch };

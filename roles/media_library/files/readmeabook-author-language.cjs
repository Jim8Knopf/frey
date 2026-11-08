// Resolve an author's likely working language without inferring it from the
// language of a particular translation. Unknown or non-English/German means
// English, as requested. Wikidata is best-effort; cached answers work offline.
const fs = require('fs');
const cachePath = process.env.FREY_AUTHOR_LANGUAGE_CACHE || '/app/config/frey-author-languages.json';
const key = value => String(value || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
const code = value => /^(german|deutsch|de)$/i.test(String(value || '').trim()) ? 'de' :
  /^(english|englisch|en)$/i.test(String(value || '').trim()) ? 'en' : null;
const ids = claims => (claims || []).filter(c => c.rank !== 'deprecated').map(c => c.mainsnak?.datavalue?.value?.id).filter(Boolean);
const pending = new Map();
let cache;
function readCache() {
  if (cache) return cache;
  try {
    cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    if (!cache || typeof cache !== 'object' || Array.isArray(cache)) cache = {};
  }
  catch { cache = {}; }
  return cache;
}
function overrides() {
  try { return JSON.parse(process.env.FREY_AUTHOR_LANGUAGE_OVERRIDES || '{}'); }
  catch { return {}; }
}
function classify(entity) {
  const claims = entity?.claims || {};
  const native = [...new Set(ids(claims.P103))];
  if (native.length === 1) return native[0] === 'Q188' ? 'de' : 'en';
  if (native.length > 1) return 'en';
  const used = [...new Set(ids(claims.P1412))];
  return used.length === 1 && used[0] === 'Q188' ? 'de' : 'en';
}
async function lookup(name) {
  const headers = { 'User-Agent': 'FreyReadMeABook/1.0 (personal media server)' };
  async function api(params) {
    const url = new URL('https://www.wikidata.org/w/api.php');
    for (const [k, v] of Object.entries({ ...params, format: 'json' })) url.searchParams.set(k, v);
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(4000) });
    if (!response.ok) throw new Error(`Wikidata HTTP ${response.status}`);
    return response.json();
  }
  const found = await api({ action: 'wbsearchentities', search: name, language: 'en', limit: '8' });
  const exact = (found.search || []).filter(item => key(item.label) === key(name) || key(item.match?.text) === key(name));
  if (!exact.length) return null;
  const data = await api({ action: 'wbgetentities', ids: exact.map(x => x.id).join('|'), props: 'claims' });
  const humans = exact.map(x => data.entities?.[x.id]).filter(x => ids(x?.claims?.P31).includes('Q5'));
  if (humans.length !== 1) return null;
  return classify(humans[0]);
}
async function getPreferredLanguage(name) {
  const normalized = key(name);
  if (!normalized) return 'en';
  for (const [author, language] of Object.entries(overrides())) {
    if (key(author) === normalized && ['de', 'en'].includes(language)) return language;
  }
  const entries = readCache();
  const saved = entries[normalized];
  if (saved && ['de', 'en'].includes(saved.language) && Date.now() - saved.checkedAt < 30 * 86400000) return saved.language;
  if (!pending.has(normalized)) pending.set(normalized, (async () => {
    try {
      const language = await lookup(name);
      if (language) {
        entries[normalized] = { language, checkedAt: Date.now() };
        try {
          const tmp = cachePath + '.' + process.pid + '.tmp';
          fs.writeFileSync(tmp, JSON.stringify(entries), { mode: 0o600 });
          fs.renameSync(tmp, cachePath);
        } catch { /* A read-only cache must not break browsing. */ }
        return language;
      }
    } catch { /* Offline or ambiguous: use a known cached value or English. */ }
    return ['de', 'en'].includes(saved?.language) ? saved.language : 'en';
  })().finally(() => pending.delete(normalized)));
  return pending.get(normalized);
}
module.exports = { getPreferredLanguage, classify, key, code };

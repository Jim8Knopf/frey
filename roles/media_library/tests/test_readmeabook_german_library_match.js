const assert = require('assert');
const { findGermanMatch } = require('../files/readmeabook-german-library-match.cjs');
const { patchMatcher } = require('../files/readmeabook-bilingual.js');

const author = 'Marc-Uwe Kling';
const candidates = [
  {title: 'Die Känguru Chroniken', author, asin: null, plexGuid: 'chroniken'},
  {title: 'Das Känguru Manifest', author, asin: null, plexGuid: 'manifest'},
  {title: 'QualityLand 2.0: Kikis Geheimnis [ungekürzt]', author, asin: null, plexGuid: 'quality-2'},
  {title: 'QualityLand (Dunkle Edition) [ungekürzt]', author, asin: null, plexGuid: 'dark'},
  {title: 'QualityLand (Helle Edition) [ungekürzt]', author, asin: null, plexGuid: 'light'},
];
const book = (title, extra = {}) => ({title, author, language: 'german', ...extra});
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken'), candidates).plexGuid, 'chroniken');
assert.strictEqual(findGermanMatch(book('Das Känguru-Manifest'), candidates).plexGuid, 'manifest');
assert.strictEqual(findGermanMatch(book('QualityLand 2.0 - Kikis Geheimnis'), candidates).plexGuid, 'quality-2');
assert.strictEqual(findGermanMatch(book('QualityLand', {subtitle: 'Dunkle Edition'}), candidates).plexGuid, 'dark');
assert.strictEqual(findGermanMatch(book('QualityLand', {subtitle: 'Helle Edition'}), candidates).plexGuid, 'light');
assert.strictEqual(findGermanMatch(book('Die Känguru-Apokryphen'), candidates), null);
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken', {language: 'english'}), candidates), null);
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken', {author: 'Another Author'}), candidates), null);
assert.strictEqual(findGermanMatch(book('QualityLand'), candidates), null);
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken', {narrator: 'Someone'}), [{...candidates[0], narrator: 'Another'}]), null);
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken'), [{...candidates[0], asin: 'different'}]), null);
assert.strictEqual(findGermanMatch(book('Die Känguru-Chroniken'), [{...candidates[0], title: 'Die Känguru Chroniken [gekürzt]'}]), null);

const branch = 'if(0===a.length)return s.matchType="no_asin_match",i.debug("Matcher result",{MATCHER:s}),null;';
assert.throws(() => patchMatcher(branch), /Unexpected ReadMeABook/);
assert.throws(() => patchMatcher(branch + branch, false), /not unique/);
assert(patchMatcher(branch, false).includes('findGermanMatch(e,c)'));
console.log('ReadMeABook German library matching tests passed');

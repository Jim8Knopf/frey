const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'frey-author-language-'));
process.env.FREY_AUTHOR_LANGUAGE_CACHE = path.join(tmp, 'cache.json');
process.env.FREY_AUTHOR_LANGUAGE_OVERRIDES = JSON.stringify({'Known German': 'de', 'J. R. R. Tolkien': 'en'});
const { classify, getPreferredLanguage, key } = require('../files/readmeabook-author-language.cjs');
const claim = id => ({mainsnak: {datavalue: {value: {id}}}});
assert.strictEqual(key('J.R.R. Tolkien'), key('J. R. R. Tolkien'));
assert.strictEqual(classify({claims: {P103: [claim('Q1860')], P1412: [claim('Q188')]}}), 'en');
assert.strictEqual(classify({claims: {P1412: [claim('Q188')]}}), 'de');
assert.strictEqual(classify({claims: {P103: [claim('Q150')]}}), 'en');
assert.strictEqual(classify({claims: {P1412: [claim('Q188'), claim('Q1860')]}}), 'en');

(async () => {
  let calls = 0;
  global.fetch = async url => {
    calls++;
    const action = new URL(url).searchParams.get('action');
    return {ok: true, json: async () => action === 'wbsearchentities'
      ? {search: [{id: 'Q1', label: 'German Writer'}]}
      : {entities: {Q1: {claims: {P31: [claim('Q5')], P1412: [claim('Q188')]}}}}};
  };
  assert.strictEqual(await getPreferredLanguage('Known German'), 'de');
  assert.strictEqual(await getPreferredLanguage('J.R.R. Tolkien'), 'en');
  assert.strictEqual(calls, 0);
  assert.strictEqual(await getPreferredLanguage('German Writer'), 'de');
  assert.strictEqual(calls, 2);
  global.fetch = async () => { throw new Error('offline'); };
  assert.strictEqual(await getPreferredLanguage('German Writer'), 'de');
  assert.strictEqual(await getPreferredLanguage('Unknown Writer'), 'en');
  assert.strictEqual(JSON.parse(fs.readFileSync(process.env.FREY_AUTHOR_LANGUAGE_CACHE)).germanwriter.language, 'de');
  console.log('ReadMeABook author language tests passed');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(tmp, {recursive: true, force: true}));

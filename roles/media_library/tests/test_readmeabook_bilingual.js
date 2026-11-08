const assert = require('assert');
const { patch, patchWorks } = require('../files/readmeabook-bilingual.js');

const authorCode = 'for(let e of u)e.authors?.some(e=>e.asin===t)&&e.language&&(0,o.W)(e.language,a)&&s.push(q(e));let g=';
const searchCode = 'h=c.map(q);return z.info(` Found ${h.length} results for';
const fixture = authorCode + '\n' + searchCode;
assert.throws(() => patch(fixture), /Unexpected ReadMeABook/);
assert.throws(() => patch(fixture + authorCode, false), /not unique/);
const source = patch(fixture, false);
const groupFixture = 'let e=`${s(n.title)}|||${function(e){return e}(n.narrator)}`,a=t.get(e);';
const collapseFixture = 'let e=a.get(t.asin);if(!e){i.push(t);continue}let r=o.get(e);';
assert.throws(() => patchWorks(groupFixture + collapseFixture), /Unexpected ReadMeABook/);
const works = patchWorks(groupFixture + collapseFixture, false);
const groupEnd = works.indexOf(';') + 1;
const groupKey = new Function('n', 's', 't', 'require', works.slice(0, groupEnd) + 'return e;');

const searchStart = source.indexOf('h=c.map(q);{let f=');
const searchEnd = source.indexOf('return z.info(` Found', searchStart);
assert(searchStart >= 0 && searchEnd > searchStart);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const search = new AsyncFunction('e', 'c', 'q', 'require', 'let h;' + source.slice(searchStart, searchEnd) + 'return h;');
const authorStart = source.indexOf('for(let x of u)x.authors?.some(');
const authorEnd = source.indexOf('let g=', authorStart);
assert(authorStart >= 0 && authorEnd > authorStart);
const author = new AsyncFunction('e', 't', 'u', 'q', 'o', 'a', 'require', 'let s=[];' + source.slice(authorStart, authorEnd) + 'return s;');

const books = [
  {title: 'English', language: 'english', author: 'Torsten Weitze', authors: [{asin: 'author'}]},
  {title: 'German', language: 'german', author: 'Torsten Weitze', authors: [{asin: 'author'}]},
  {title: 'Other', language: 'german', author: 'Someone Else', authors: [{asin: 'other'}]},
];
const { key, code } = require('../files/readmeabook-author-language.cjs');
const req = () => ({key, code, getPreferredLanguage: async name => name === 'Torsten Weitze' ? 'de' : 'en'});
(async () => {
  const map = new Map();
  assert.notStrictEqual(groupKey({title: 'Same', narrator: 'Reader', language: 'english'}, x => x, map, req), groupKey({title: 'Same', narrator: 'Reader', language: 'german'}, x => x, map, req));
  assert.strictEqual(groupKey({title: 'Same', narrator: 'Reader', language: 'en'}, x => x, map, req), groupKey({title: 'Same', narrator: 'Reader', language: 'english'}, x => x, map, req));
  assert.deepStrictEqual((await search('Torsten Weitze', books, x => x, req)).map(x => x.title), ['German', 'English', 'Other']);
  assert.deepStrictEqual((await search('Different', books, x => x, req)).map(x => x.title), ['English', 'German', 'Other']);
  assert.deepStrictEqual((await author('Torsten Weitze', 'author', books, x => x, {W: x => x === 'english'}, {}, req)).map(x => x.title), ['German', 'English']);
  assert.deepStrictEqual((await author('Any Author', 'author', books, x => x, {W: x => x === 'english'}, {}, req)).map(x => x.title), ['English', 'German']);
  const noId = {title: 'Missing ID', language: 'german', authors: [{name: 'Torsten Weitze'}]};
  const alternateId = {title: 'Alternate ID', language: 'german', authors: [{name: 'Torsten Weitze', asin: 'other'}]};
  const differentName = {title: 'Different name', language: 'german', authors: [{name: 'Different Person', asin: 'other'}]};
  assert.deepStrictEqual((await author('Torsten Weitze', 'author', [noId, alternateId, differentName], x => x, {W: () => false}, {}, req)).map(x => x.title), ['Missing ID', 'Alternate ID']);
  const french = {title: 'French', language: 'french', authors: [{asin: 'author'}]};
  assert.deepStrictEqual((await author('Any Author', 'author', [...books, french], x => x, {W: x => x === 'english'}, {}, req)).map(x => x.title), ['English', 'German']);
  console.log('ReadMeABook bilingual search tests passed');
})().catch(error => { console.error(error); process.exitCode = 1; });

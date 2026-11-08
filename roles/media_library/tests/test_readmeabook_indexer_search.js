const assert = require('assert');
const { patchIndexerSearch } = require('../files/readmeabook-bilingual');

const original = 'for(let t of[er(e),r&&(er(r)??r)])t&&!n.some(e=>Y(e,t))&&n.push(t);';
const patched = patchIndexerSearch(original, false);
const fallback = new Function('e', `let r=null,n=[],er=()=>null,Y=(a,b)=>a.toLowerCase()===b.toLowerCase();${patched}return n;`);
assert.deepStrictEqual(fallback('The Children of Húrin'), ['The Children of Hurin', 'Children of Húrin']);
assert.deepStrictEqual(fallback('The Fall of Númenor'), ['The Fall of Numenor', 'Fall of Númenor']);
assert.deepStrictEqual(fallback('The Adventures of Tom Bombadil'), ['Adventures of Tom Bombadil']);
assert.deepStrictEqual(fallback('Hobbit'), []);
assert.throws(() => patchIndexerSearch('unexpected', false));
console.log('ReadMeABook indexer fallback tests passed');

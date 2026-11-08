// ReadMeABook's library index can contain books without Audible IDs. Match
// German catalogue entries conservatively without writing to Audiobookshelf.
function normalize(value) {
  return String(value || '').toLowerCase()
    .replace(/\s*[\[(]\s*(?:ungekürzt|unabridged)\s*[\])]/gu, ' ')
    .replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss')
    .normalize('NFKD').replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().replace(/\s+/g, ' ');
}

function findGermanMatch(book, candidates) {
  if (!/^(german|deutsch|de)$/i.test(String(book.language || '').trim())) return null;
  const author = normalize(book.author);
  const title = normalize(book.title);
  if (!author || !title) return null;
  const titles = new Set();
  // Single-word titles are too easy to confuse across languages or editions.
  if (title.split(' ').length >= 2) titles.add(title);
  if (book.subtitle) titles.add(normalize(`${book.title} ${book.subtitle}`));
  if (titles.size === 0) return null;
  return candidates.find(candidate => {
    if (candidate.asin || normalize(candidate.author) !== author) return false;
    if (!titles.has(normalize(candidate.title))) return false;
    if (candidate.narrator && book.narrator && normalize(candidate.narrator) !== normalize(book.narrator)) return false;
    return true;
  }) || null;
}

module.exports = { findGermanMatch, normalize };

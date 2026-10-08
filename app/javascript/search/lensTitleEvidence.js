const aliases = {
  couch: "sofa",
  couches: "sofa",
  settee: "sofa",
  settees: "sofa",
  bookshelf: "bookcase",
  bookshelves: "bookcase",
  shelves: "shelf",
  benches: "bench",
  grey: "gray",
  wooden: "wood",
};

function words(text) {
  return (
    text
      .normalize("NFKD")
      .toLowerCase()
      .replace(/\p{M}/gu, "")
      .match(/[a-z0-9]+/g) || []
  ).map((word) => (Object.hasOwn(aliases, word) ? aliases[word] : word));
}

// Select evidence for an existing server phrase; never build or change the search query.
export function supportingLensTitles({ titles, query, category }) {
  if (!Array.isArray(titles) || typeof query !== "string" || typeof category !== "string")
    return [];
  const phraseWords = words(query);
  const categoryWords = words(category);
  if (!phraseWords.length || !categoryWords.length) return [];
  return [...new Set(titles.slice(0, 8))]
    .filter((title) => {
      if (typeof title !== "string") return false;
      const titleWords = words(title).map((word) =>
        word.endsWith("s") && categoryWords.includes(word.slice(0, -1)) ? word.slice(0, -1) : word,
      );
      const hasCategory = titleWords.some((_, index) =>
        categoryWords.every((word, offset) => titleWords[index + offset] === word),
      );
      return hasCategory && phraseWords.every((word) => titleWords.includes(word));
    })
    .slice(0, 2);
}

import assert from "node:assert/strict";
import test from "node:test";
import { supportingLensTitles } from "../../app/javascript/search/lensTitleEvidence.js";

test("the sofa explanation selects the titles supporting green velvet instead of the first matches", () => {
  const titles = [
    "What Does A Sofa Cost? | Seriously Happy Homes",
    "Sectionals Available at Rufeners Furniture in Rittman, OH",
    "Amazon.com: Modway EEI-3764-GRN Valour Performance Velvet ...",
    "US Pride Furniture Civa 69.6 in. Green Velvet 3-Seater Sofa ...",
    "west elm - Hyde Park",
    "MODWAY Valour 73 in. Green Velvet 3-Seater Tuxedo Sofa with ...",
    "How to Give Your Home Furniture a Makeover - Smithe Blog ...",
    "Five Things to Know About the Co-CEO Model - Steyer Associates",
  ];
  assert.deepEqual(supportingLensTitles({ titles, query: "green velvet sofa", category: "sofa" }), [
    titles[3],
    titles[5],
  ]);
});

test("evidence matches complete words, aliases and adjacent compound furniture types", () => {
  const cases = [
    ["gray wood sofa", "sofa", ["GREY wooden couches", "Grey wood settees"]],
    ["oak shelf", "shelf", ["Oak shelves", "Oak shelf"]],
    ["red dining chair", "dining chair", ["Red dining chairs", "Red dining-chair"]],
  ];
  for (const [query, category, titles] of cases) {
    assert.deepEqual(supportingLensTitles({ titles, query, category }), titles);
  }
  assert.deepEqual(
    supportingLensTitles({
      titles: ["Evergreen velvet sofa", "Green sofa", "Green velvet wallpaper"],
      query: "green velvet sofa",
      category: "sofa",
    }),
    [],
  );
  assert.deepEqual(
    supportingLensTitles({
      titles: ["Coffee served on a wood table"],
      query: "wood coffee table",
      category: "coffee table",
    }),
    [],
  );
});

test("missing evidence is omitted and excerpts stay within the eight titles used by Lens recognition", () => {
  for (const value of [undefined, null, {}, { titles: [], query: null, category: null }]) {
    assert.deepEqual(supportingLensTitles(value || {}), []);
  }
  const first = "Green velvet sofa";
  const second = "Green velvet sofas for sale";
  const third = "Our green velvet sofa";
  assert.deepEqual(
    supportingLensTitles({
      titles: [first, first, second, third],
      query: "green velvet sofa",
      category: "sofa",
    }),
    [first, second],
  );
  assert.deepEqual(
    supportingLensTitles({
      titles: [...Array(8).fill("Sofa guide"), first],
      query: "green velvet sofa",
      category: "sofa",
    }),
    [],
  );
});

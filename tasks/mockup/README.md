# Interactive mockup

Edit `main.jsx`, then run:

```sh
npm --prefix tasks/mockup ci
npm --prefix tasks/mockup run build
```

The build writes `tasks/ui-mockup-looksalike-demo.html` as one self-contained file. Open it directly or through a local preview server. React, Material UI, and Emotion are bundled locally; the mockup makes no API, CDN, or font requests.

It demonstrates the upload, ZIP, preview, loading, and illustrative-results flow. It does not perform a live search or look up ZIP locations.

The loading screen keeps the photo visible and advances through upload, Lens identification, optional photo detail checking, eBay search, and match checking. This preview includes the Venice fallback and uses deterministic timers totaling 13 seconds; these are simulated transitions, not measured requests. `SearchLoading.jsx` accepts the current step and a step list, with the Venice step omitted by default. Future live wiring must use actual stage events and include that step only when the fallback runs. No percentage or countdown is shown.

Back stops the timers and restores the selected photo and ZIP. New searches, page exit, and unmount invalidate pending transitions. The loading and results headings receive keyboard focus; a polite live region announces stage changes. Reduced-motion preferences show a static activity indicator. The older ZIP, Craigslist results, and walkthrough remain unchanged in this loading-screen preview; live Rails search is still disabled.

Completed results survive a reload in the same tab using session storage, including the ZIP, reference photo, and whether the walkthrough is open. Uploaded photos use a small local preview for restoration; image bytes are not sent anywhere. “Search again” clears the saved view.

`SearchWalkthrough.jsx` models one flow for the purple couch in ZIP 94103: upload, Lens, Images, and listing selection. `SearchFlowDiagram.jsx` shows a black-on-white architecture sketch above those details, with the browser, Rails, local ZIP/area files, and three SerpApi calls. The SVG is bundled locally and scrolls horizontally on narrow screens. Visitors do not choose a search approach. The UI uses completed-search wording to preview the finished design. Response excerpts and filtering counts are illustrative, not captured API results. No timings or provider calls are measured by this mockup.

The user selected the example photo from [this Pinterest pin](https://www.pinterest.com/pin/victorian-purple-couch--563018694468707/) for the local mockup. The pin's [image URL](https://i.pinimg.com/736x/74/fd/ab/74fdab9ef5fd818bfdef7b7725248e9f.jpg) is saved as `assets/victorian-purple-couch.jpg` and embedded by esbuild as a data URL in the standalone HTML. Permission for public reuse has not been established.

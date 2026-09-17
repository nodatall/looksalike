# Interactive mockup

Edit `main.jsx`, then run:

```sh
npm --prefix tasks/mockup ci
npm --prefix tasks/mockup run build
```

The build writes `tasks/ui-mockup-looksalike-demo.html` as one self-contained file. Open it directly or through a local preview server. React, Material UI, and Emotion are bundled locally; the mockup makes no API, CDN, or font requests.

It demonstrates the upload, ZIP, preview, loading, and illustrative-results flow. It does not perform a live search or look up ZIP locations.

Completed results survive a reload in the same tab using session storage, including the ZIP, reference photo, and whether the walkthrough is open. Uploaded photos use a small local preview for restoration; image bytes are not sent anywhere. “Search again” clears the saved view.

`SearchWalkthrough.jsx` models one flow for the purple couch in ZIP 94103: upload, Lens, Images, and listing selection. `SearchFlowDiagram.jsx` shows a black-on-white architecture sketch above those details, with the browser, Rails, local ZIP/area files, and three SerpApi calls. The SVG is bundled locally and scrolls horizontally on narrow screens. Visitors do not choose a search approach. The UI uses completed-search wording to preview the finished design. Response excerpts and filtering counts are illustrative, not captured API results. No timings or provider calls are measured by this mockup.

The user selected the example photo from [this Pinterest pin](https://www.pinterest.com/pin/victorian-purple-couch--563018694468707/) for the local mockup. The pin's [image URL](https://i.pinimg.com/736x/74/fd/ab/74fdab9ef5fd818bfdef7b7725248e9f.jpg) is saved as `assets/victorian-purple-couch.jpg` and embedded by esbuild as a data URL in the standalone HTML. Permission for public reuse has not been established.

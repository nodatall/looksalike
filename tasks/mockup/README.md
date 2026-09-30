# Interactive mockup

Run `npm --prefix tasks/mockup run build` to regenerate `tasks/ui-mockup-looksalike-demo.html`.

The standalone HTML and Rails app share the photo upload, preparation, progress, eBay cards, saved-view validation, and explanation components under `app/javascript/search`. The app never imports from `tasks/`. The mockup models upload progress with timers and then offers the example; it makes no provider requests. The Rails app reads actual NDJSON events from `/searches`. Choosing the example fills the photo preview, and submitting it immediately replays the recorded search without artificial loading.

The reference is Phillip Goldsberry's [green sofa on Unsplash](https://unsplash.com/photos/green-fabric-sofa-fZuleEfeA1Q), reused under the [Unsplash License](https://unsplash.com/license). The runtime copy is `app/javascript/search/assets/modern-sofa.jpg`, identical to the licensed research reference. Full source, license and hash evidence is in `docs/examples/modern-sofa-2026-09-28.json`. The earlier Pinterest photo is no longer used in this mockup.

The six actual eBay cards and sanitized explanation come from that September 28, 2026 snapshot. Listing availability has not been rechecked. Listing thumbnails load remotely from `i.ebayimg.com`; permission to bundle them remains unresolved. They have not been downloaded or bundled. This is not a complete offline example or a public-release approval. React, Material UI, Emotion and the licensed reference are bundled locally; listing thumbnails are the only remote images.

Completed success/empty views save a validated normalized result, an at-most-160px JPEG reference thumbnail, and explanation open state in this tab's versioned session storage. Reload makes zero upload/search calls. Unfinished work does not resume. Search again clears the saved view and photo. Invalid, legacy or unavailable storage returns a usable upload screen. Original uploaded bytes and provider photo references are never saved.

Use an approved browser surface for verification. Do not serve a blocked `file://` preview through another URL to bypass a browser denial.

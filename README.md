# LooksAlike

A furniture photo search demo under development, built with Rails, React, and Material UI. The approved flow is photo upload → Google Lens → a short search phrase → US-located eBay listings. It needs no ZIP code. Search and example actions remain disabled in the app while this flow is tested; the current screen still reflects the earlier Craigslist design.

The [query-v3 repair](docs/experiments/query-v3/README.md) now requires agreement across Lens titles and preserves names such as “coffee table.” It corrects both saved category errors. In the [fresh live comparison](docs/experiments/ebay-flow-v2/README.md), the modern sofa passed, but the ornate sofa and wooden chair failed: the phrases “sofa” and “chair” were too broad. Testing stopped after two failures, leaving the coffee table and dresser untested. All executed provider calls succeeded within 55 seconds. Feature work and deployment remain paused until search quality passes.

The latest batch used six searches and three uploads, bringing recorded development usage to 29 searches. The user approved extending the original 15-search limit. All earlier experiments remain preserved, including the [previous full-flow comparison](docs/experiments/ebay-flow-v1/README.md) and [country-filter diagnostic](docs/experiments/ebay-no-country-v1/README.md). eBay requests omit the provider country filter; explicit US location is checked in returned data.

## Local setup

Use Ruby 3.4.10, Node 22.22.3, and libvips. On Apple Silicon macOS:

```sh
brew install ruby@3.4 vips
export PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH"
```

Check `ruby --version` and `node --version` against `.ruby-version` and `.node-version`. Use your Node version manager to select the pinned Node version.

Then install and prepare the app:

```sh
bin/setup --skip-server
bin/dev
```

Open [localhost:3000](http://localhost:3000). The health check is `/up`. `bin/setup` installs dependencies, builds JavaScript, prepares SQLite, and starts Rails.

During frontend development, run `npm run build -- --watch` in another terminal and reload the page after changes. Rails remains the only web server.

Development and test load environment configuration through `dotenv-rails`. Copy `.env.example` to `.env.local` only if you do not already have that local file, and keep any key there. Normal checks do not need a key. The example lists current Rails settings and planned search limits; those limits are not wired yet. SQLite databases live under `storage/`. Production reads configuration from the host environment.

## Browser assets

`app/javascript/application.jsx` mounts one React root in the ERB page. The shared Material UI theme lives in `app/javascript/search/theme.js`. The app uses local system fonts and bundled dependencies; it needs no CDN requests.

`npm run build` uses esbuild to write `app/assets/builds/application.js`. Rails `assets:precompile` automatically installs the locked npm dependencies and runs this build through `jsbundling-rails`, then Propshaft fingerprints the assets for production. Keep Node and npm available during the deployment build, including esbuild's development dependency.

To verify production asset compilation without real credentials:

```sh
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

Run `bin/rails assets:clobber` and `npm run build` before returning to local development so the production manifest does not hide later rebuilds.

The approved screen mockup and execution plan remain under `tasks/`; the mockup contains illustrative results only.

## Troubleshooting

JSON 3.0.2 rejects the positional options passed by Rails 8.1.3.1 in `ActiveSupport::JSON.decode`. A fresh page worked, but a repeat load with its session cookie failed while rendering CSRF metadata. The Gemfile constrains JSON to the compatible 2.x series; `test/integration/home_test.rb` covers both requests with the same cookie.

## Checks

Run `bin/check` before committing. It runs Ruby style checks, Biome formatting/lint checks, Ruby and npm dependency audits, Brakeman, the JavaScript build, test database preparation, Rails eager loading, and Minitest. The command uses the test environment, disables live search, and clears the provider key for child commands. Advisory checks need public internet access; they make no paid provider calls.

For focused work:

```sh
bin/rubocop                 # Ruby style
bin/rubocop -a              # Apply safe Ruby style fixes
npm run check              # JavaScript lint and formatting check
npm run format             # Format owned JavaScript/config files
npm run build              # Build before focused request tests
bin/rails test test/integration/home_test.rb
```

The formatting tools exclude the historical mockup, generated assets, dependencies, and private working directories. JavaScript stays JSX without a TypeScript check. GitHub Actions runs the same `bin/check` on pushes and pull requests with Ruby 3.4.10, the pinned Node 22 version, and libvips. No Git hooks are installed.

## Photo and provider boundary

The page uses `app/javascript/search/preparePhoto.js` to check JPEG/PNG/WebP headers before decoding, reject sources over 10 MB or 20 megapixels and animated PNG/WebP, and produce a JPEG of at most 450,000 bytes. The versioned `jpeg-v1` recipe starts at a 1,600-pixel longest edge with fixed quality and resize steps, applies image orientation, and flattens transparency onto white. The preview uses only the prepared image. Replacing it releases the old object URL; canceled work releases its decoded bitmap. No file leaves the browser through this page yet.

The manual fixture tool executes that exact browser module in installed Chrome, blocks external requests, and writes prepared JPEGs plus recipe/dimension/hash/browser metadata without overwriting existing files:

```sh
npm run prepare:photos -- /tmp/prepared-photos /absolute/path/to/photo.jpg
```

JPEG bytes may differ across browser encoder versions. Freeze the produced bytes and recorded browser metadata for an experiment; the recipe alone does not promise byte-identical output across machines. This preparation command does not establish provenance or score search results.

`PhotoValidator.call(upload, deadline:)` independently checks image magic, the 450,000-byte limit, dimensions, animation, and complete decoding with libvips. It ignores claimed filenames/MIME and consumes/deletes uploaded Tempfiles on success or failure. It creates no persistent image storage.

`SerpApi::Client` owns fixed HTTPS upload, Lens, and Images requests. Upload validates bytes before dispatch. Pass the **same** `SearchDeadline` to preparation and every provider call; its default is 55 seconds measured monotonically, with remaining socket timeouts and a whole-operation timer. Responses are limited to 2 MB. There are no retries, redirects, polling, or fallback searches. Public errors and object string representations omit sensitive content; Rails filters photo/image/key/reference parameters. The manual experiment ledger now enforces durable attempt accounting; public route wiring and production quotas are still planned.

Normal Ruby tests use WebMock with all external network access disabled. `npm test` exercises header, limit, compression-cap, cleanup, and cancellation rules. `bin/check` runs both JavaScript and Ruby tests. The fixture tool and manual UI probe additionally verify real browser encoding; fixture preparation makes no SerpApi calls.

## Frozen experiment preparation

`SearchQuery` builds a short phrase from a common furniture name and at most two recognized traits, using versioned category and attribute rules. It drops duplicates, marketing terms, and unsupported description words before searching. `ListingNormalizer` validates exact-area Craigslist destinations and credential-free thumbnails, deduplicates listing IDs, and keeps at most six results. Lens-only preserves provider order; the two-search route ranks title-token overlap with stable ties. Both policies are pure Ruby and make no network calls.

The [feasibility-v1 input set](docs/experiments/feasibility-v1/README.md) contains five licensed reference photos prepared by the real browser compressor, with fixed ZIPs, source provenance, request templates, and rule/data hashes. The historical frozen manifest retains its pre-run status; the separate [results](docs/experiments/feasibility-v1/results.md) and [live evidence](docs/experiments/feasibility-v1/live-evidence.json) record six search attempts, four upload attempts, and both routes stopping without passing. The historical v1 verifier (`script/verify_experiment.rb`) applies to Git revision `79e05a3`; it intentionally refuses the subsequently revised query policy. The [query-v2 comparison](docs/experiments/query-v2/README.md) preserves the old source and freezes the new policy separately. The completed [two-request diagnostic](docs/experiments/diagnostic-v1/README.md) brings combined usage to eight attempts: the modern query returned 100 links outside Craigslist, while the ornate query returned no images and an error of uncertain cause. The approved short-query follow-up used two more attempts (ten total): no accepted San Francisco listings and two New York candidates that failed manual relevance checks. The simpler rule is implemented; the original scores remain unchanged and the feasibility gate is still closed. The [manual operator instructions](docs/experiments/feasibility-v1/README.md#manual-operator-commands) describe explicit account checks, execution, and scoring. Default preflight is entirely offline and creates no ledger.

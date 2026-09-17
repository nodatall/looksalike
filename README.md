# LooksAlike

A furniture photo search demo under development. Rails serves a bundled React and Material UI entry screen. ZIP entry works; upload and example actions are disabled until the search feasibility work is complete. No provider calls or illustrative results are wired into the app.

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

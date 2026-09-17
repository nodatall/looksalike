# LooksAlike

A furniture photo search demo under development. The Rails foundation is running; search and provider calls are not implemented yet.

## Local setup

Use Ruby 3.4.10, then run:

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Open http://localhost:3000. The health check is `/up`.

Development and test load local configuration through `dotenv-rails`. Keep secrets in ignored `.env.local` files. SQLite databases live under `storage/`.

The approved screen mockup and execution plan remain under `tasks/`; the mockup contains illustrative results only.

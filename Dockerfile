# syntax=docker/dockerfile:1
FROM node:22.22.3-bookworm-slim AS node
FROM ruby:3.4.10-slim-bookworm AS base
WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    LIVE_SEARCH_ENABLED=false \
    RAILS_MAX_THREADS=3
RUN apt-get update -qq && apt-get install --no-install-recommends -y libvips42 gosu ca-certificates && rm -rf /var/lib/apt/lists/*

FROM base AS build
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential git pkg-config libyaml-dev && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /usr/local/bundle/cache
COPY package.json package-lock.json ./
RUN npm ci --include=dev
COPY . .
RUN mkdir -p app/assets/builds && SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile && rm -rf node_modules tmp/cache

FROM base
RUN groupadd --gid 1000 rails && useradd --uid 1000 --gid 1000 --create-home --shell /bin/sh rails
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app
RUN mkdir -p /app/storage /app/tmp /app/log && chown -R rails:rails /app/tmp /app/log && chmod +x bin/docker-entrypoint bin/production-start
EXPOSE 3000
ENTRYPOINT ["/app/bin/docker-entrypoint"]

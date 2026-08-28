# DS Catalog Browser stack

A two-container demo stack for browsing a federated catalog through the
new `ds-catalog-broker-rs` management API:

- **`ds-catalog-broker-rs`** (`vendor/ds-catalog-broker-rs`, pinned to the
  still-open `feature/federated-catalog-management-api` branch tip,
  [PR #6](https://github.com/ds-labs-org/ds-catalog-broker-rs/pull/6)) -
  serves `POST /api/management/v4/catalogs/request`, an
  `edc-federated-catalog-client`-wire-compatible Management API route, on
  top of its documented in-memory seeded sample catalog (no
  `CRAWLER_CONFIG_PATH` configured). Its OAuth2 bearer gate
  (`check_oauth2_bearer`) stays open: no `OAUTH2_JWKS_URI` is set in this
  stack.
- **`ds-catalog-browser-ui`** (`vendor/ds-catalog-browser-ui`, pinned to
  its `main` tip) - a minimal read-only Yew UI that fetches offers from
  that same route and renders them as an expandable table. Served by
  nginx, which proxies the UI's own `catalog_path`
  (`/api/management/v4/catalogs/request`, baked into its
  `configuration.json`) straight through to the broker container.

This is unrelated to the `dcp-test-env` content elsewhere in this repo
(root `README.md`, `run-*.sh`, `seed/`) - that's a separate DCP/IdentityHub
validation environment, not part of this stack.

## Prerequisites

```bash
git submodule update --init --recursive
```

`ds-catalog-broker-rs` pulls in its own nested submodules (`vendor/contreforts-kg`,
`vendor/contreforts-core`, `vendor/contreforts-config`) - budget a little
extra time for that first init.

## Run

```bash
docker compose -f docker-compose.yml up --build -d
```

Budget several minutes for the two real Rust builds (both stages of both
Dockerfiles compile from source, no prebuilt images).

Then open **http://localhost:8092/** - the UI fetches offers from the
broker's seeded sample catalog (currently two datasets,
`CAT0101`/`CAT0102`, under `sample-catalog`) and renders them.

`docker-compose.yml` publishes the UI on host port `8092` (not `80`) and
the broker on host port `8091` (not `8080`) - ports `80` and `8080` were
already bound to unrelated processes on the host this was built and
verified on. Edit the `ports:` mapping for either service if `8091`/`8092`
collide for you too; the container-internal ports (`80` and `8080`, what
nginx's proxy target and `HTTP_API_ADDR` use) don't need to change.

The broker's own port is also published directly, for debugging:
`http://localhost:8091/catalog` (`GET`, DSP catalog view) and
`http://localhost:8091/api/management/v4/catalogs/request` (`POST`, the
same management API route the UI calls, proxied through nginx at `/`).

## Verify the chain end to end

```bash
docker compose ps

curl -s http://localhost:8092/ | head -5   # the app's real index.html, not an nginx default page

curl -s -X POST http://localhost:8092/api/management/v4/catalogs/request \
  -H "Content-Type: application/json" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}' \
  | jq .
```

The last command should return a JSON array of offers, each with `@id`,
`@type`, `participantId`, and
`http://www.w3.org/ns/dcat#dataset` keys - proving nginx -> broker -> the
seeded sample catalog works end to end, not just that the containers
started.

## Tear down

```bash
docker compose -f docker-compose.yml down
```

# DS Catalog Browser stack

A four-container demo stack for browsing a federated catalog through the
new `ds-catalog-broker-rs` management API - now backed by a **real
background crawl** over two mock DSP participants, not just the broker's
built-in placeholder:

- **`ds-catalog-broker-rs`** (`vendor/ds-catalog-broker-rs`, pinned to the
  still-open `feature/federated-catalog-management-api` branch tip,
  [PR #6](https://github.com/ds-labs-org/ds-catalog-broker-rs/pull/6)) -
  serves `POST /api/management/v4/catalogs/request`, an
  `edc-federated-catalog-client`-wire-compatible Management API route.
  `CRAWLER_CONFIG_PATH` is set (to a bind-mounted
  `docker/ds-catalog-broker-rs/participants.toml`), so this connector runs
  its real `crates/crawler` background harvest loop against the two mock
  participants below every `interval_secs` (5s) instead of falling back
  to its documented in-memory seeded sample catalog
  (`seed_sample_catalog`, one participant / two datasets). Its OAuth2
  bearer gate (`check_oauth2_bearer`) stays open: no `OAUTH2_JWKS_URI` is
  set in this stack.
- **`mock-harvest-d`** / **`mock-harvest-e`** (`docker/mock-participant/`)
  - two bare nginx containers, each answering
  `POST /api/dsp/2025-1/catalog/request` with a static JSON DSP
  catalog-request response: `harvest-d` (3 datasets, `HARVEST-D-01..03`)
  and `harvest-e` (7 datasets, `HARVEST-E-01..07`). These reuse the exact
  participant ids, dataset ids, and `interval_secs` (5) from
  `vendor/ds-catalog-broker-rs`'s own published harvesting benchmark,
  [`compliance/harvest-benchmark-2026-08-27.md`](https://github.com/ds-labs-org/ds-catalog-broker-rs/blob/0933bb94c5141c1570e54eec102f7d29a18b7561/compliance/harvest-benchmark-2026-08-27.md)
  - real Eclipse EDC 0.18.0 participants there, static nginx fixtures with
  the same shape here, for direct traceability to that published, verified
  result: crawling 2 real DSP participants totaling 10 datasets, not one
  seeded placeholder totaling 2.
- **`ds-catalog-browser-ui`** (`vendor/ds-catalog-browser-ui`, pinned to
  the still-open `feature/patternfly-theme` branch tip,
  [PR #1](https://github.com/ds-labs-org/ds-catalog-browser-ui/pull/1)) -
  a minimal read-only Yew UI that fetches offers from that same route and
  renders them as an expandable table, themed with the real
  `patternfly-yew` component library at the same PatternFly/FontAwesome
  asset versions as `dataspace-rs/edc-web-ui` (see that PR). Served by
  nginx, which proxies the UI's own `catalog_path`
  (`/api/management/v4/catalogs/request`, baked into its
  `configuration.json`) straight through to the broker container. Its
  Dockerfile's build stage installs Node/npm via apt, since Trunk now
  shells out to npm to pull the PatternFly/FontAwesome asset packages
  (`Trunk.toml`'s `[[node_packages]]`) that `rust:*-bookworm` doesn't ship
  by default.

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
Dockerfiles compile from source, no prebuilt images) plus a lighter,
faster build for each `mock-harvest-*` nginx fixture.

Then wait a few seconds past `interval_secs` (5s, in
`docker/ds-catalog-broker-rs/participants.toml`) for the broker's first
crawl cycle to finish, and open **http://localhost:8092/** - the UI
fetches offers from the broker's now-real crawl result: 2 participants
(`HARVEST-D`, `HARVEST-E`), 10 datasets total
(`HARVEST-D-01..03`, `HARVEST-E-01..07`) - and renders them.

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

RESP=$(curl -s -X POST http://localhost:8092/api/management/v4/catalogs/request \
  -H "Content-Type: application/json" \
  -d '{"@context":{"@vocab":"https://w3id.org/edc/v0.0.1/ns/"},"@type":"QuerySpec"}')

echo "$RESP" | jq .

# Real counts, not eyeballed:
echo "$RESP" | jq '[.[] | {participant: .participantId["@id"], count: (.["http://www.w3.org/ns/dcat#dataset"] | length)}]'
echo "$RESP" | jq '[.[]["http://www.w3.org/ns/dcat#dataset"][]."@id"] | length'   # -> 10
```

The array should contain exactly two offers - `participantId` `HARVEST-D`
(3 datasets) and `HARVEST-E` (7 datasets) - 10
`http://www.w3.org/ns/dcat#dataset` entries in total, ids
`HARVEST-D-01..03`/`HARVEST-E-01..07`, matching
`vendor/ds-catalog-broker-rs`'s own harvesting benchmark exactly - proving
nginx -> broker -> a real background crawl of both mock participants
works end to end, not just that the containers started.

**Known gotcha:** if you recreate only the `ds-catalog-broker-rs`
container in an already-running stack (e.g. `docker compose up --build
ds-catalog-broker-rs` on its own) without also restarting
`ds-catalog-browser-ui`, its container gets a new internal IP that
nginx's `proxy_pass` resolved once at startup and cached - the UI's proxy
then 502s until you `docker compose restart ds-catalog-browser-ui`. A
full `docker compose up --build -d` (or `down` + `up`) for the whole
stack, as above, doesn't hit this - both containers start together.

## Tear down

```bash
docker compose -f docker-compose.yml down
```

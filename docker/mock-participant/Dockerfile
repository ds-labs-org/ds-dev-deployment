# Mock DSP catalog-participant fixture, shared by the two
# docker-compose.yml services `mock-harvest-d` / `mock-harvest-e` via the
# FIXTURE build arg - same nginx image and config, different static JSON
# body, rather than two near-duplicate Dockerfiles for what is otherwise
# identical: a bare nginx container answering
# `POST /api/dsp/2025-1/catalog/request` with a static file.
# `crates/crawler`'s own `parse_catalog_response`
# (vendor/ds-catalog-broker-rs/crates/crawler/src/lib.rs) parses the
# response body leniently by field name only - it never inspects the
# request body it POSTs, and doesn't care that this "server" is static -
# so no real DSP participant implementation is needed for this demo.
#
# These two fixtures stand in for the two real Eclipse EDC 0.18.0
# participants (`HARVEST-D`, 3 datasets; `HARVEST-E`, 7 datasets) that
# vendor/ds-catalog-broker-rs's own published harvesting benchmark
# (compliance/harvest-benchmark-2026-08-27.md in that submodule) crawled -
# same participant ids, same dataset ids, for direct traceability to that
# real, verified result. See README.catalog-browser.md.
#
# Build context is the repo root (matches this repo's other docker/
# Dockerfiles), so both docker/mock-participant/*.json fixtures and this
# Dockerfile's own nginx config are reachable from here.
FROM nginx:1.28.0-bookworm

# Which participant's static catalog response this image serves -
# docker-compose.yml passes a different value per service.
ARG FIXTURE=harvest-d.json

ADD docker/mock-participant/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY docker/mock-participant/${FIXTURE} /usr/share/nginx/html/catalog-response.json

EXPOSE 80

# Build context for this Dockerfile is the repo root (see
# docker-compose.yml), so this Dockerfile's own nginx/default.conf (which
# lives alongside it under docker/, not inside the vendor/
# ds-catalog-browser-ui submodule) can be ADDed below too. Same proven
# two-stage pattern as dataspace/vendor/dataspace-rs-ui/Dockerfile: a
# rust+trunk build stage producing dist/, then nginx serving that dist/
# as a static site.
FROM rust:1.97.1-bookworm AS build-stage

RUN rustup target add wasm32-unknown-unknown && \
    cargo install trunk@0.22.0-beta.2

ADD vendor/ds-catalog-browser-ui /sources

WORKDIR /sources

RUN trunk build --release

FROM nginx:1.28.0-bookworm

COPY --from=build-stage /sources/dist /usr/share/nginx/html

EXPOSE 80

ADD docker/ds-catalog-browser-ui/nginx/default.conf /etc/nginx/conf.d/default.conf

# The repo's own configuration.json (copied into dist/ by trunk's own
# copy-file directive in index.html) already has this exact shape - this
# RUN just makes that guarantee explicit and independent of upstream
# changing its own file: catalog_path has to match nginx's proxy
# location above exactly (see that file's comment), and bearer_token is
# omitted because this compose stack's ds-catalog-broker-rs has no
# OAUTH2_JWKS_URI configured, so its bearer gate stays open.
RUN echo '{"catalog_path": "/api/management/v4/catalogs/request"}' > /usr/share/nginx/html/configuration.json

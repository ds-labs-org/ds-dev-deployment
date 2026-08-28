# Build context for this Dockerfile is vendor/ds-catalog-broker-rs itself
# (see docker-compose.yml) - that submodule's own root Cargo.toml is a
# workspace whose members include its nested git submodules
# (vendor/contreforts-kg, vendor/contreforts-core,
# vendor/contreforts-core/declaration, vendor/contreforts-config), so the
# whole checked-out tree (including those already-initialized nested
# submodules) has to be present for `cargo build` to resolve the
# workspace - see that repo's own Cargo.toml comment on why they're
# first-class workspace members rather than a separate nested workspace.
#
# PRODUCT_CRATES below matches vendor/ds-catalog-broker-rs/.github/workflows/ci.yml
# exactly: the 5 crates this workspace actually ships as its own product.
# Building `--workspace` instead would also directly build the vendored
# contreforts-kg with its own default features (including oxigraph's
# RocksDB backend, a from-source C++/cmake build this product never
# needs at runtime) - see that CI workflow's comment and
# crates/rdf-store/Cargo.toml.
FROM rust:1.97.1-bookworm AS build-stage

WORKDIR /sources

COPY . .

RUN cargo build --release \
    -p catalog-core -p rdf-store -p ds-catalog-broker-rs -p dcp-core -p crawler

FROM debian:bookworm-slim

# ca-certificates: this connector's own DCP holder path and the optional
# OAUTH2_JWKS_URI fetch both go out over TLS via reqwest's rustls-tls
# backend, which still needs a system root store to validate certs
# against. Unused by this compose stack's demo config (no
# CRAWLER_CONFIG_PATH, no OAUTH2_JWKS_URI) but harmless and cheap to keep
# the image correct for the configurations that do need it.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build-stage /sources/target/release/ds-catalog-broker-rs /usr/local/bin/ds-catalog-broker-rs

# Default HTTP_API_ADDR is 127.0.0.1:8080 (loopback-only - see
# crates/ds-catalog-broker-rs/src/main.rs) which is unreachable from other
# containers on a compose bridge network. docker-compose.yml overrides
# HTTP_API_ADDR to 0.0.0.0:8080 for exactly this reason - EXPOSE here is
# documentation of that same port, not a substitute for the override.
EXPOSE 8080

# CRAWLER_CONFIG_PATH is intentionally left unset: this connector falls
# back to its documented in-memory seeded sample catalog
# (seed_sample_catalog), giving GET /catalog and
# POST /api/management/v4/catalogs/request real (if small) demo data
# without a full harvester/participant setup.
ENTRYPOINT ["/usr/local/bin/ds-catalog-broker-rs"]

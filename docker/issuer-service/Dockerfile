# syntax=docker/dockerfile:1
#
# Builds and runs eclipse-edc/IdentityHub's "issuer-service" launcher with
# the dcp-test-env seed extension attached. See README.md for the
# protocol background and ../../run-issuer-service.sh for the bare-metal
# equivalent of everything this Dockerfile and entrypoint.sh do.
#
# Build context is the REPO ROOT (not this directory) - see
# docker-compose.yml - same reasoning as docker/identityhub/Dockerfile.

# ---- builder: real Gradle build of upstream identity-hub, plus the seed extension ----
FROM eclipse-temurin:24.0.2_12-jdk-alpine AS builder

RUN apk add --no-cache bash

WORKDIR /build/vendor/identity-hub
COPY vendor/identity-hub/ ./

# shadowJar merges every runtime dependency (including nimbus-jose-jwt)
# into one jar - see launcher/issuer-service/build.gradle.kts.
RUN --mount=type=cache,target=/root/.gradle,sharing=locked \
    ./gradlew --no-daemon :launcher:issuer-service:shadowJar

WORKDIR /build/seed
COPY seed/src ./src
RUN mkdir -p out/META-INF/services && \
    javac -cp /build/vendor/identity-hub/launcher/issuer-service/build/libs/issuer-service.jar \
        -d out src/GenerateIssuerKey.java src/IssuerServiceSeedExtension.java && \
    printf 'IssuerServiceSeedExtension\n' > out/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension && \
    cd out && jar cf ../issuer-service-seed.jar \
        GenerateIssuerKey.class \
        IssuerServiceSeedExtension.class \
        META-INF/services/org.eclipse.edc.spi.system.ServiceExtension

# ---- runtime: same base image/shape as upstream's own launcher/issuer-service/Dockerfile ----
FROM eclipse-temurin:24.0.2_12-jre-alpine

RUN apk --no-cache add curl bash

WORKDIR /app

COPY --from=builder /build/vendor/identity-hub/launcher/issuer-service/build/libs/issuer-service.jar /app/issuer-service.jar
COPY --from=builder /build/seed/issuer-service-seed.jar /app/issuer-service-seed.jar
COPY docker/issuer-service/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Port map (see README.md "Port map") - identical to run-issuer-service.sh.
EXPOSE 9090 9091 9092 9093 9094 9095

# Same env var block as run-issuer-service.sh, verbatim.
ENV WEB_HTTP_PORT=9090 \
    WEB_HTTP_PATH=/api \
    WEB_HTTP_IDENTITY_PORT=9091 \
    WEB_HTTP_IDENTITY_PATH=/api/identity \
    WEB_HTTP_ISSUERADMIN_PORT=9092 \
    WEB_HTTP_ISSUERADMIN_PATH=/api/issueradmin \
    WEB_HTTP_DID_PORT=9093 \
    WEB_HTTP_DID_PATH=/ \
    WEB_HTTP_STS_PORT=9094 \
    WEB_HTTP_STS_PATH=/sts \
    WEB_HTTP_ISSUANCE_PORT=9095 \
    WEB_HTTP_ISSUANCE_PATH=/api/issuance \
    EDC_IAM_DID_WEB_USE_HTTPS=false \
    SEED_ISSUER_DID_HOST=localhost:9093 \
    KEYS_DIR=/app/keys \
    SEED_KEYS_DIR=/app/keys

HEALTHCHECK --interval=5s --timeout=5s --retries=10 CMD curl --fail http://localhost:9090/api/check/health

ENTRYPOINT ["/app/entrypoint.sh"]

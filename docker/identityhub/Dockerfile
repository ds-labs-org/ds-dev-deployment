# syntax=docker/dockerfile:1
#
# Builds and runs eclipse-edc/IdentityHub's "identityhub" launcher (the
# holder/wallet + embedded STS + Presentation API side of DCP) with the
# dcp-test-env seed extension attached. See README.md for the protocol
# background and ../../run-identityhub.sh for the bare-metal equivalent
# of everything this Dockerfile and entrypoint.sh do.
#
# Build context is the REPO ROOT (not this directory) - see
# docker-compose.yml - because this needs both vendor/identity-hub/ (the
# real upstream source, built from here rather than pre-built) and
# seed/src/ (this repo's own seed extension).

# ---- builder: real Gradle build of upstream identity-hub, plus the seed extension ----
# Matches the runtime JRE tag below (24.0.2_12) so the JDK that compiles
# the code is the same major/update version as the JRE that runs it.
FROM eclipse-temurin:24.0.2_12-jdk-alpine AS builder

RUN apk add --no-cache bash

WORKDIR /build/vendor/identity-hub
COPY vendor/identity-hub/ ./

# shadowJar merges every runtime dependency (including nimbus-jose-jwt,
# which both the seed extension and GenerateIssuerKey need) into one jar
# with mergeServiceFiles()/duplicatesStrategy=INCLUDE - see
# launcher/identityhub/build.gradle.kts.
RUN --mount=type=cache,target=/root/.gradle,sharing=locked \
    ./gradlew --no-daemon :launcher:identityhub:shadowJar

# Compile this repo's own seed extension (+ the key-generator helper)
# against the shadow jar's classpath, exactly like run-identityhub.sh
# does against a captured launcher classpath.
WORKDIR /build/seed
COPY seed/src ./src
RUN mkdir -p out/META-INF/services && \
    javac -cp /build/vendor/identity-hub/launcher/identityhub/build/libs/identity-hub.jar \
        -d out src/GenerateIssuerKey.java src/IdentityHubSeedExtension.java && \
    printf 'IdentityHubSeedExtension\n' > out/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension && \
    cd out && jar cf ../identityhub-seed.jar \
        GenerateIssuerKey.class \
        IdentityHubSeedExtension.class \
        'IdentityHubSeedExtension$SeedEnv.class' \
        META-INF/services/org.eclipse.edc.spi.system.ServiceExtension

# ---- runtime: same base image/shape as upstream's own launcher/identityhub/Dockerfile ----
FROM eclipse-temurin:24.0.2_12-jre-alpine

RUN apk --no-cache add curl bash

WORKDIR /app

COPY --from=builder /build/vendor/identity-hub/launcher/identityhub/build/libs/identity-hub.jar /app/identity-hub.jar
COPY --from=builder /build/seed/identityhub-seed.jar /app/identityhub-seed.jar
COPY docker/identityhub/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Port map (see README.md "Port map") - identical to run-identityhub.sh.
EXPOSE 9080 9081 9082 9083 9084

# Same env var block as run-identityhub.sh, verbatim - DID hosts stay
# "localhost:PORT" because both services run with network_mode: host
# (see docker-compose.yml and the README's networking note) so plain
# localhost resolution keeps working exactly as it does bare-metal.
ENV WEB_HTTP_PORT=9080 \
    WEB_HTTP_PATH=/api \
    WEB_HTTP_IDENTITY_PORT=9081 \
    WEB_HTTP_IDENTITY_PATH=/api/identity \
    WEB_HTTP_CREDENTIALS_PORT=9082 \
    WEB_HTTP_CREDENTIALS_PATH=/api/credentials \
    WEB_HTTP_DID_PORT=9083 \
    WEB_HTTP_DID_PATH=/ \
    WEB_HTTP_STS_PORT=9084 \
    WEB_HTTP_STS_PATH=/sts \
    EDC_IAM_DID_WEB_USE_HTTPS=false \
    SEED_IDENTITYHUB_DID_HOST=localhost:9083 \
    SEED_ISSUER_DID_HOST=localhost:9093 \
    SEED_CREDENTIALS_BASE_URL=http://localhost:9082/api/credentials \
    KEYS_DIR=/app/keys \
    SEED_KEYS_DIR=/app/keys \
    SEED_INFO_FILE=/app/keys/seed-info.json

HEALTHCHECK --interval=5s --timeout=5s --retries=10 CMD curl --fail http://localhost:9080/api/check/health

ENTRYPOINT ["/app/entrypoint.sh"]

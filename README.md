# dcp-test-env

A local, throwaway Decentralized Claims Protocol (DCP) environment for
validating `http-api`'s upcoming DCP-based catalog auth
(`DspAuthMode::Dcp`, the "narrowed (b)" scope from
`compliance/benchmark-2026-08-27.md`'s follow-up work). It runs two real
`eclipse-edc/IdentityHub` v0.18.0 launchers - an **Identity Hub**
(holder/wallet + embedded STS + Presentation API) and an **Issuer
Service** - seeded with a real holder participant, a real issuer
participant, and a genuinely ES256-signed Verifiable Credential.

**This is test/validation infrastructure only.** It is not, and must not
be read as, a decision about the `dataspace` study repo's `authority/`
placeholder - see that repo's `CLAUDE.md` on why `authority/` stays a
placeholder until an ADR says otherwise. Vendoring
`dataspace/vendor/identity-hub` here is the same kind of reference/test
acquisition as vendoring `eclipse-edc-connector` and `tractus-x-edc`
already were.

## Why an Identity Hub *and* an Issuer Service

The user ask this exists to satisfy: "prepare a test environment with an
identity hub and an issuer ... properly seeded ... to validate the DCP
implementation." Both components are real, running EDC code (not
stubs) - only the *choreography* connecting them is simplified (see
"What's simplified" below).

## Why there's a third "verifier" participant

Real DCP's presentation-query protocol requires **proof of original
possession**: the self-issued token a holder sends to a relying party
embeds a nested "presentation access token" claim, but the relying party
can't just forward that nested token as-is to the holder's Presentation
API - the API requires whatever bearer token it receives to itself carry
a nested `token` claim, re-signed by the party presenting it. In other
words, the *receiver* of the holder's SI token (the "verifier" role -
eventually federated-catalog-rs) must re-package the extracted nested
token into a *new* self-issued token, signed with the verifier's own
key, before the Presentation API accepts it.

This isn't a simplification - it's how DCP works, discovered the hard
way while getting `validate.py` to pass (see its step 2 and the trail of
`401`s it took to get there, summarized below). Since
federated-catalog-rs's Rust code doesn't exist yet, this environment
hosts a **third participant, "verifier"**, in the same IdentityHub
instance, purely so `validate.py` can exercise the *complete* real
protocol end to end before any Rust code is written. When Rust's actual
DCP verifier is implemented, it most likely won't depend on this
IdentityHub's STS for its own re-packaging step (a local, in-process
JWT-sign using Rust's own keypair is simpler and has no runtime
dependency on this test environment) - but it will need *an* identity of
its own (a keypair and a way to be resolved, e.g. a `did:web` document
it self-hosts) to play the same "verifier" role for real, whatever
mechanism it uses for it.

## What's simplified (and what isn't)

**Genuinely real:** the ES256 signatures on the SI tokens, the VP, and
the VC; both DIDs (`did:web:localhost%3A9083:dcp-test-client` and
`did:web:localhost%3A9093:issuer`) are hosted by real, independently
running IdentityHub/Issuer-Service processes and resolve to real,
matching public keys; the STS token-exchange protocol (including the
proof-of-possession re-packaging step above) is exercised via
IdentityHub's real, unmodified `/sts/token` endpoint; the Presentation
API round trip (`POST .../presentations/query`) is IdentityHub's real,
unmodified controller.

**Simplified:** the seeded credential is inserted directly into the
holder's `CredentialStore` by `IdentityHubSeedExtension`
(`seed/src/IdentityHubSeedExtension.java`), rather than being delivered
through the live, asynchronous DCP *issuance* protocol (credential
offer → holder requests it → issuer's `IssuanceProcessManager` state
machine processes it → callback delivers it) between the Issuer Service
and IdentityHub. That machinery exists in `vendor/identity-hub` (see
`core/issuerservice/issuerservice-issuance`) and is exercised by that
project's own `e2e-tests/tck-tests` against the real
`eclipse-dataspacetck/dcp-tck` suite - reusing it here was judged
disproportionate to what's actually being validated (Rust's
*verification* of an incoming presentation, not the issuance
choreography). The credential's signature is still genuine, signed with
the same keypair the Issuer Service participant holds - only the
issuer-to-holder *delivery* is shortcut.

## Layout

- `seed/src/GenerateIssuerKey.java` - one-shot P-256 keypair generator,
  compiled directly against the already-built `nimbus-jose-jwt` jar (no
  extra Gradle project needed).
- `seed/src/IdentityHubSeedExtension.java` - `ServiceExtension` added to
  the IdentityHub launcher's classpath at boot. Creates the
  `dcp-test-client` (holder) and `verifier` participant contexts, and
  seeds the `FederatedCatalogAccessCredential`.
- `seed/src/IssuerServiceSeedExtension.java` - same pattern for the
  Issuer Service launcher: creates the `issuer` participant context
  with the same keypair the seeded credential is signed with.
- `vendor/identity-hub` - `eclipse-edc/IdentityHub` vendored as a git
  submodule, pinned to `v0.18.0` - makes this repo self-contained; the
  Docker build (and the bare-metal scripts, via `IDENTITY_HUB_DIR`) both
  build against it directly, no external checkout required.
- `docker/identityhub/`, `docker/issuer-service/` - `Dockerfile` +
  `entrypoint.sh` per service; see "Running it" below.
- `docker-compose.yml` - wires both services together for
  `docker compose up`.
- `run-identityhub.sh`, `run-issuer-service.sh` - the bare-metal
  alternative: build (once) and run each seeded launcher directly with
  Gradle/`java`. Idempotent: safe to re-run, capture the launcher's
  classpath once per checkout (`seed/*-classpath.txt`, gitignored -
  regenerate by deleting them) rather than re-invoking Gradle on every
  start.
- `validate.py` - the actual end-to-end DCP validation described above.
  No Rust/federated-catalog-rs dependency.
- `keys/` (gitignored) - generated keypairs and `seed-info.json` (DIDs +
  STS client credentials for `validate.py` and, eventually, Rust's own
  test client). Regenerated fresh on first run, whether via
  `docker compose up` or either `run-*.sh` script; delete the whole
  directory to force fresh keys/participants.

## Running it

Docker is the primary, recommended way to run this environment - it's
self-contained (this repo vendors `eclipse-edc/IdentityHub` itself as a
git submodule at `vendor/identity-hub`, pinned to `v0.18.0`) and needs
nothing but Docker and Docker Compose on the host:

```bash
git submodule update --init
docker compose up --build -d   # first run builds both services via Gradle inside Docker - budget several minutes
docker compose ps              # wait for both to report "healthy"
python3 validate.py
docker compose down
```

`docker-compose.yml` runs both services with `network_mode: host`
(Linux-only - see "Networking note" below) so they resolve each other's
`did:web` documents, and are themselves resolved by `validate.py`
running on the host, via the exact same `localhost:9080-9084` /
`localhost:9090-9095` ports documented below - no DID host, port, or env
var differs from the bare-metal path. `docker/identityhub/Dockerfile`
and `docker/issuer-service/Dockerfile` build each launcher from
`vendor/identity-hub` (multi-stage: a builder stage runs the real
upstream Gradle `shadowJar` build and compiles this repo's seed
extension against it, then a runtime stage matching upstream's own
`launcher/*/Dockerfile` shape). Both containers bind-mount the same
host `./keys` directory (gitignored, regenerated fresh on first run,
same as the bare-metal path below) since `issuer-key` must be shared
between them - see `seed/src/GenerateIssuerKey.java`.

### Networking note

`network_mode: host` only works on Linux (Docker Desktop on macOS/
Windows runs containers in a VM, where host networking doesn't expose
container ports to the host the same way) - this is a real limitation
of this compose file, not glossed over. It's used here because the
seeded DIDs and every `SEED_*_DID_HOST` value are hardcoded to plain
`localhost:PORT` (see "DID hosting" details throughout this doc);
bridge networking would give each container its own hostname/IP and
break that DID resolution without changing the seed extensions.

### Bare-metal alternative

If you have your own JDK/Gradle setup and want to skip Docker
entirely, `run-identityhub.sh` and `run-issuer-service.sh` still work
exactly as before:

```bash
cd ds-dev-deployment
./run-identityhub.sh &      # first run builds identity-hub via Gradle - budget several minutes
./run-issuer-service.sh &   # same for issuer-service
sleep 5
python3 validate.py
```

These default to a *sibling* `dataspace/vendor/identity-hub` checkout
(`IDENTITY_HUB_DIR`, see the scripts) rather than this repo's own
`vendor/identity-hub` submodule - override `IDENTITY_HUB_DIR` if you'd
rather point them at the submodule.

## Port map

| Service | Port | Context |
|---|---:|---|
| Identity Hub | 9080 | base (health check) |
| | 9081 | Identity API (participant/DID/key management - protected) |
| | 9082 | Credentials API (Presentation + Storage - public, DCP-protocol) |
| | 9083 | DID hosting (`did:web` documents - public) |
| | 9084 | STS (`/sts/token` - public, OAuth2-client-credentials-shaped) |
| Issuer Service | 9090 | base |
| | 9091 | Identity API |
| | 9092 | Issuer Admin API |
| | 9093 | DID hosting |
| | 9094 | STS |
| | 9095 | Issuance protocol API (unused by this environment - see above) |

The default single-port launch mode (no `WEB_HTTP_*_PORT` overrides)
blanket-401s *every* path, including ones that must be public per DCP
(STS, Presentation API, DID hosting) - this is why both scripts
configure explicit per-context ports rather than relying on defaults.

`EDC_IAM_DID_WEB_USE_HTTPS=false` is required in this local, plain-HTTP
setup - `did:web` resolution defaults to HTTPS per spec, and without
this setting DID resolution fails with an SSL handshake error against
the plain-HTTP did-hosting port (the same fix the `dataspace` repo's own
`eclipse-edc-connector` benchmark run needed - see
`federated-catalog-rs/compliance/benchmark-2026-08-27.md`).

`ParticipantManifest.Builder.active(true)` does **not** actually
activate a participant context on this IdentityHub version -
`IdentityHubParticipantContextServiceImpl.convert()` unconditionally
sets `CREATED`. Both seed extensions call
`participantContextService.updateParticipant(id, IdentityHubParticipantContext::activate)`
explicitly afterward; skipping this leaves the DID document unpublished
(`did:web` resolution returns an empty `204`) with only a warning logged,
not an error - easy to miss.

## Cleanup

Docker path:

```bash
docker compose down
```

Bare-metal path:

```bash
pkill -f 'org.eclipse.edc.boot.system.runtime.BaseRuntime.*identity-hub'
```

or find the two PIDs (`pgrep -af BaseRuntime`) and kill them directly -
both run as plain `java -cp ... BaseRuntime` processes, not under
Gradle, once started via the `run-*.sh` scripts (the scripts' first-run
classpath capture does briefly start one under Gradle - see script
comments).

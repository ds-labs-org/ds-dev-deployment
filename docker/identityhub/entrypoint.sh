#!/bin/bash
# Generates any missing key file(s) under $KEYS_DIR, then execs the
# seeded IdentityHub launcher. Mirrors run-identityhub.sh's key-generation
# step, but at container startup instead of shell-script startup, and
# guards it with a simple mkdir-lock because issuer-key is *shared* with
# the issuer-service container via the same bind-mounted $KEYS_DIR (see
# GenerateIssuerKey.java's doc comment) - docker compose starts both
# containers concurrently, so without a lock both could decide
# simultaneously that issuer-key is missing and generate two different
# keys, racing on which one lands on disk.
set -euo pipefail

KEYS_DIR="${KEYS_DIR:-/app/keys}"
LOCK_DIR="$KEYS_DIR/.keygen.lock"
mkdir -p "$KEYS_DIR"

acquire_lock() {
  for _ in $(seq 1 150); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  echo "Timed out waiting for key-generation lock at $LOCK_DIR" >&2
  return 1
}
release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock
trap release_lock EXIT

for key_id in issuer-key dcp-test-client-key verifier-key; do
  if [ ! -f "$KEYS_DIR/$key_id-private.jwk.json" ]; then
    echo "Generating $key_id ..."
    java -cp /app/identity-hub.jar:/app/identityhub-seed.jar GenerateIssuerKey "$KEYS_DIR" "$key_id"
  fi
done

release_lock
trap - EXIT

echo "Starting seeded IdentityHub on :9080-9084 ..."
exec java -cp /app/identity-hub.jar:/app/identityhub-seed.jar org.eclipse.edc.boot.system.runtime.BaseRuntime

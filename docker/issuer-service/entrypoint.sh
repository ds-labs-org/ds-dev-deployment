#!/bin/bash
# Generates the shared issuer-key under $KEYS_DIR if it's not already
# there (e.g. generated first by the identityhub container), then execs
# the seeded Issuer Service launcher. See
# docker/identityhub/entrypoint.sh for why the mkdir-lock is needed -
# issuer-key is shared between both containers via the same
# bind-mounted $KEYS_DIR.
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

if [ ! -f "$KEYS_DIR/issuer-key-private.jwk.json" ]; then
  echo "Generating issuer-key ..."
  java -cp /app/issuer-service.jar:/app/issuer-service-seed.jar GenerateIssuerKey "$KEYS_DIR" issuer-key
fi

release_lock
trap - EXIT

echo "Starting seeded Issuer Service on :9090-9095 ..."
exec java -cp /app/issuer-service.jar:/app/issuer-service-seed.jar org.eclipse.edc.boot.system.runtime.BaseRuntime

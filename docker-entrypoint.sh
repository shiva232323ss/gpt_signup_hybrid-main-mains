#!/bin/sh
set -eu

APP_DIR="/app/gpt_signup_hybrid"
RUNTIME_DIR="${RUNTIME_DIR:-${APP_DIR}/runtime}"

echo "========================================"
echo " gpt_signup_hybrid - Container Startup"
echo "========================================"

echo "[startup] APP_DIR=${APP_DIR}"
echo "[startup] RUNTIME_DIR=${RUNTIME_DIR}"

# ------------------------------------------------------------
# Prepare runtime directories.
# Railway/Docker volume mounts can replace the runtime/
# directory created during image build, so create them again
# at container startup.
# ------------------------------------------------------------

echo "[startup] Creating runtime directories..."

mkdir -p \
    "${RUNTIME_DIR}" \
    "${RUNTIME_DIR}/sessions" \
    "${RUNTIME_DIR}/outlook_state"

# Useful application subdirectories
mkdir -p \
    "${RUNTIME_DIR}/sessions" \
    "${RUNTIME_DIR}/outlook_state"

# ------------------------------------------------------------
# Fix ownership for the non-root application user.
# This is especially important when Railway mounts an empty
# persistent volume over /app/gpt_signup_hybrid/runtime.
# ------------------------------------------------------------

echo "[startup] Fixing runtime ownership..."

chown -R appuser:appuser "${RUNTIME_DIR}"

# ------------------------------------------------------------
# Verify directories
# ------------------------------------------------------------

echo "[startup] Runtime directory:"
ls -ld "${RUNTIME_DIR}"

echo "[startup] Sessions directory:"
ls -ld "${RUNTIME_DIR}/sessions"

echo "[startup] Outlook state directory:"
ls -ld "${RUNTIME_DIR}/outlook_state"

# ------------------------------------------------------------
# Run database migrations.
# The project's migration command treats missing/empty state
# directories as zero-record migrations.
# ------------------------------------------------------------

echo "[startup] Running database migration..."

gosu appuser python -m gpt_signup_hybrid migrate

echo "[startup] Database migration completed."

# ------------------------------------------------------------
# Start the application.
# The Docker CMD is passed here and remains PID-visible through
# tini -> entrypoint -> gosu -> application.
# ------------------------------------------------------------

echo "[startup] Starting application..."

exec gosu appuser "$@"

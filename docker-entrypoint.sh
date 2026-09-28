#!/bin/sh
set -eu

# ============================================================
# gpt_signup_hybrid - Railway Docker Entrypoint
# ============================================================

APP_DIR="/app/gpt_signup_hybrid"
RUNTIME_DIR="${RUNTIME_DIR:-${APP_DIR}/runtime}"

echo "=================================================="
echo " gpt_signup_hybrid - Container Startup"
echo "=================================================="

echo "[startup] APP_DIR=${APP_DIR}"
echo "[startup] RUNTIME_DIR=${RUNTIME_DIR}"

# ------------------------------------------------------------
# Create runtime directories.
#
# Railway persistent-volume mounts can hide directories that
# were created during Docker image build, so we ALWAYS create
# them again at container startup.
# ------------------------------------------------------------

echo "[startup] Creating runtime directories..."

mkdir -p "${RUNTIME_DIR}"
mkdir -p "${RUNTIME_DIR}/sessions"
mkdir -p "${RUNTIME_DIR}/outlook_state"

# Useful runtime location for generated session outputs
mkdir -p "${RUNTIME_DIR}/sessions"

# ------------------------------------------------------------
# Make runtime writable by application user.
# ------------------------------------------------------------

echo "[startup] Fixing runtime ownership..."

chown -R appuser:appuser "${RUNTIME_DIR}"

# ------------------------------------------------------------
# Verify paths.
# ------------------------------------------------------------

echo "[startup] Runtime directory:"
ls -ld "${RUNTIME_DIR}"

echo "[startup] Sessions directory:"
ls -ld "${RUNTIME_DIR}/sessions"

echo "[startup] Outlook state directory:"
ls -ld "${RUNTIME_DIR}/outlook_state"

# ------------------------------------------------------------
# Run database migration.
# ------------------------------------------------------------

echo "[startup] Running database migration..."

gosu appuser python -m gpt_signup_hybrid migrate

echo "[startup] Database migration completed."

# ------------------------------------------------------------
# Start application.
#
# "$@" comes from Docker CMD.
# We drop privileges to appuser before starting the actual app.
# ------------------------------------------------------------

echo "[startup] Starting application..."

exec gosu appuser "$@"

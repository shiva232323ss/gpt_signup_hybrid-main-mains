#!/bin/sh
set -e

# Fix runtime/ ownership when a Docker volume is mounted as root.
# Named volumes mounted over a path override the directory's ownership set
# during the image build, so we repair it here while still running as root
# (before gosu drops us to appuser). chown is a no-op if already correct.
RUNTIME_DIR="${RUNTIME_DIR:-/app/gpt_signup_hybrid/runtime}"
mkdir -p "$RUNTIME_DIR"
chown appuser:appuser "$RUNTIME_DIR"

# Drop to appuser for all subsequent work (migrate + exec CMD).
# gosu re-execs this script's remaining logic as appuser so the process
# tree is clean and signals are forwarded correctly through tini.
if [ "$(id -u)" = "0" ]; then
    exec gosu appuser "$0" "$@"
fi

# Migrate idempotent (version-based) — chạy trước mọi command (web/hme/cli).
# DB engine tự tạo runtime/ + data.db (db/engine.py mkdir parents).
# Migrate không cần X display nên KHÔNG bọc xvfb-run ở đây; chỉ CMD
# (web/browser job) mới cần display, đã bọc xvfb-run trong CMD/compose command.
python -m gpt_signup_hybrid migrate

exec "$@"

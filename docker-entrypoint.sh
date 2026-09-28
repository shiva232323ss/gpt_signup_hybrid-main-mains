#!/bin/bash
set -e

# Run database migrations if needed (idempotent)
# Uncomment if your app has migrations:
# python -m gpt_signup_hybrid migrate

# Drop privileges from root to appuser and exec the main command
exec gosu appuser "$@"


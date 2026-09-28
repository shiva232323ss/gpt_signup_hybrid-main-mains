# syntax=docker/dockerfile:1

# ============================================================
# gpt_signup_hybrid
# Railway / Linux Docker deployment
# ============================================================

# ============================================================
# STAGE 1: BUILDER
# ============================================================
FROM python:3.13-slim-bookworm AS builder

ENV HOME=/home/appuser \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright

# Create non-root application user
RUN useradd -m -u 10001 appuser

# Build dependencies for packages such as Cython/lxml/curl_cffi
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    pkg-config \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# ------------------------------------------------------------
# requirements.txt is at repository root
# ------------------------------------------------------------
COPY requirements.txt .

# ------------------------------------------------------------
# Create isolated Python virtual environment
# ------------------------------------------------------------
RUN python -m venv /opt/venv

ENV PATH=/opt/venv/bin:$PATH

# Upgrade installer tooling
RUN pip install --upgrade pip setuptools wheel

# ------------------------------------------------------------
# Remove macOS-only PyObjC packages if they are still present
# in requirements.txt.
#
# This allows the same requirements file to work on Linux
# even if it was originally generated on macOS.
# ------------------------------------------------------------
RUN grep -ivE '^(pyobjc-core|pyobjc-framework-Cocoa)(==|$)' \
    requirements.txt > requirements.linux.txt

RUN pip install -r requirements.linux.txt

# ------------------------------------------------------------
# Install Playwright Firefox
# ------------------------------------------------------------
RUN playwright install firefox

# ------------------------------------------------------------
# Download Camoufox browser + GeoIP data during BUILD,
# not when the Railway container starts.
# ------------------------------------------------------------
RUN python -m camoufox fetch

RUN python -c "\
from camoufox.locale import MMDB_FILE, download_mmdb; \
MMDB_FILE.exists() or download_mmdb() \
"


# ============================================================
# STAGE 2: RUNTIME
# ============================================================
FROM python:3.13-slim-bookworm AS runtime

ENV HOME=/home/appuser \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/venv/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright \
    RUNTIME_DIR=/app/gpt_signup_hybrid/runtime

# Create same user as builder
RUN useradd -m -u 10001 appuser

# ------------------------------------------------------------
# Runtime packages
#
# xvfb      = virtual X display
# xauth     = xvfb-run dependency
# curl      = HTTP/network diagnostics
# tini      = proper PID 1 / signal handling
# gosu      = safely drop from root to appuser
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    xauth \
    curl \
    tini \
    gosu \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Copy Python virtual environment
# ------------------------------------------------------------
COPY --from=builder /opt/venv /opt/venv

# ------------------------------------------------------------
# Install Firefox runtime system libraries
# ------------------------------------------------------------
RUN playwright install-deps firefox \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Copy pre-downloaded browser cache
# ------------------------------------------------------------
COPY --from=builder --chown=appuser:appuser \
    /home/appuser/.cache \
    /home/appuser/.cache

# ============================================================
# APPLICATION SOURCE
# ============================================================
#
# IMPORTANT:
# GitHub repository currently has:
#
# /
# ├── Dockerfile
# ├── requirements.txt
# ├── docker-entrypoint.sh
# └── gpt_signup_hybrid-main/
#     └── actual application source
#
# Therefore we copy the nested project directory into the
# runtime application directory.
# ============================================================

COPY --chown=appuser:appuser \
    gpt_signup_hybrid-main/ \
    /app/gpt_signup_hybrid/

# ------------------------------------------------------------
# Install startup entrypoint
# ------------------------------------------------------------
COPY --chown=root:root \
    docker-entrypoint.sh \
    /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# ------------------------------------------------------------
# Create runtime directories INSIDE THE IMAGE.
#
# These may later be hidden by a Railway volume mount, which
# is why docker-entrypoint.sh recreates them at startup too.
# ------------------------------------------------------------
RUN mkdir -p \
    /app/gpt_signup_hybrid/runtime \
    /app/gpt_signup_hybrid/runtime/sessions \
    /app/gpt_signup_hybrid/runtime/outlook_state \
    && chown -R appuser:appuser \
    /app/gpt_signup_hybrid/runtime

# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------
WORKDIR /app/gpt_signup_hybrid

# ------------------------------------------------------------
# Railway exposes its own PORT environment variable.
# 8083 remains the application's local fallback.
# ------------------------------------------------------------
EXPOSE 8083

# ------------------------------------------------------------
# Healthcheck
#
# Railway's proxy uses the externally exposed port. This
# healthcheck is mainly useful for container-level diagnostics.
# ------------------------------------------------------------
HEALTHCHECK --interval=30s \
    --timeout=10s \
    --start-period=40s \
    --retries=5 \
    CMD sh -c 'curl -fsS "http://127.0.0.1:${PORT:-8083}/" || exit 1'

# ------------------------------------------------------------
# tini -> entrypoint
#
# entrypoint:
#   1. creates runtime/
#   2. creates sessions/
#   3. creates outlook_state/
#   4. fixes ownership
#   5. runs migration
#   6. starts the web application
# ------------------------------------------------------------
ENTRYPOINT [
    "/usr/bin/tini",
    "--",
    "/usr/local/bin/docker-entrypoint.sh"
]

# ------------------------------------------------------------
# Start web server.
#
# Use Railway's PORT when available; otherwise use 8083.
# 0.0.0.0 is required inside a Railway container so the
# platform proxy can reach the process.
# ------------------------------------------------------------
CMD [
    "sh",
    "-c",
    "exec xvfb-run -a python -m gpt_signup_hybrid web --host 0.0.0.0 --port ${PORT:-8083} --unsafe-expose-network"
]

# syntax=docker/dockerfile:1

# ============================================================
# gpt_signup_hybrid
# Railway / Linux Docker deployment
# ============================================================

# ============================================================
# STAGE 1 - BUILDER
# ============================================================

FROM python:3.13-slim-bookworm AS builder

ENV HOME=/home/appuser \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright

# ------------------------------------------------------------
# Create application user
# ------------------------------------------------------------

RUN useradd -m -u 10001 appuser

# ------------------------------------------------------------
# Build dependencies
# ------------------------------------------------------------

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    pkg-config \
    libffi-dev \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# ------------------------------------------------------------
# Copy requirements from repository root
# ------------------------------------------------------------

COPY requirements.txt /build/requirements.txt

# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------

RUN python -m venv /opt/venv

ENV PATH=/opt/venv/bin:$PATH

RUN pip install --upgrade pip setuptools wheel

# ------------------------------------------------------------
# Remove macOS-only PyObjC dependencies if present.
# They are not needed on Linux.
# ------------------------------------------------------------

RUN grep -ivE '^(pyobjc-core|pyobjc-framework-Cocoa)(==|$)' \
    /build/requirements.txt \
    > /build/requirements.linux.txt

# ------------------------------------------------------------
# Install Python dependencies
# ------------------------------------------------------------

RUN pip install -r /build/requirements.linux.txt

# ------------------------------------------------------------
# Install Playwright Firefox
# ------------------------------------------------------------

RUN playwright install firefox

# ------------------------------------------------------------
# Pre-download Camoufox during image build.
# This avoids downloading the browser when the Railway
# container starts.
# ------------------------------------------------------------

RUN python -m camoufox fetch

# ------------------------------------------------------------
# Download GeoIP database if Camoufox does not already have it.
# ------------------------------------------------------------

RUN python -c "from camoufox.locale import MMDB_FILE, download_mmdb; MMDB_FILE.exists() or download_mmdb()"


# ============================================================
# STAGE 2 - RUNTIME
# ============================================================

FROM python:3.13-slim-bookworm AS runtime

ENV HOME=/home/appuser \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/venv/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright \
    RUNTIME_DIR=/app/gpt_signup_hybrid/runtime \
    GSH_DB_PATH=/app/gpt_signup_hybrid/runtime/data.db

# ------------------------------------------------------------
# Create application user
# ------------------------------------------------------------

RUN useradd -m -u 10001 appuser

# ------------------------------------------------------------
# Runtime packages
#
# xvfb  -> virtual display for browser automation
# xauth  -> required by xvfb-run
# curl   -> HTTP diagnostics
# tini   -> proper PID 1 / signal handling
# gosu   -> safely run application as non-root
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
# Copy Python virtual environment from builder
# ------------------------------------------------------------

COPY --from=builder /opt/venv /opt/venv

# ------------------------------------------------------------
# Install Firefox runtime libraries
# ------------------------------------------------------------

RUN playwright install-deps firefox \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Copy pre-built browser cache
# ------------------------------------------------------------

COPY --from=builder --chown=appuser:appuser \
    /home/appuser/.cache \
    /home/appuser/.cache

# ============================================================
# APPLICATION SOURCE
# ============================================================
#
# Current GitHub repository structure:
#
# /
# ├── Dockerfile
# ├── docker-entrypoint.sh
# ├── requirements.txt
# └── gpt_signup_hybrid-main/
#     └── application source
#
# Copy the nested application directory into /app.
# ============================================================

COPY --chown=appuser:appuser \
    gpt_signup_hybrid-main/ \
    /app/gpt_signup_hybrid/

# ------------------------------------------------------------
# Copy Railway entrypoint from repository root
# ------------------------------------------------------------

COPY --chown=root:root \
    docker-entrypoint.sh \
    /usr/local/bin/docker-entrypoint.sh

RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# ------------------------------------------------------------
# Create runtime directories during image build.
#
# docker-entrypoint.sh creates them again after any Railway
# persistent volume is mounted.
# ------------------------------------------------------------

RUN mkdir -p \
    /app/gpt_signup_hybrid/runtime \
    /app/gpt_signup_hybrid/runtime/sessions \
    /app/gpt_signup_hybrid/runtime/outlook_state \
    && chown -R appuser:appuser \
    /app/gpt_signup_hybrid/runtime

# ------------------------------------------------------------
# Application working directory
# ------------------------------------------------------------

WORKDIR /app/gpt_signup_hybrid

# ------------------------------------------------------------
# Default/fallback port.
# Railway provides its own PORT environment variable at runtime.
# ------------------------------------------------------------

EXPOSE 8083

# ------------------------------------------------------------
# tini -> docker-entrypoint.sh
#
# Entrypoint:
#   1. creates runtime/
#   2. creates runtime/sessions/
#   3. creates runtime/outlook_state/
#   4. fixes ownership
#   5. runs migration
#   6. starts web server
# ------------------------------------------------------------

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]

# ------------------------------------------------------------
# Start web application.
#
# Railway's PORT is used automatically.
# 8083 is only the fallback when PORT is unavailable.
#
# 0.0.0.0 is required so Railway's proxy can reach the app.
# ------------------------------------------------------------

CMD ["sh", "-c", "exec xvfb-run -a python -m gpt_signup_hybrid web --host 0.0.0.0 --port ${PORT:-8083} --unsafe-expose-network"]

# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: Builder
# ============================================================
FROM python:3.13-slim-bookworm AS builder

ENV HOME=/home/appuser \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright

RUN useradd -m -u 10001 appuser

# Build tools required by some Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    pkg-config \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Your requirements.txt is in the GitHub ROOT
COPY requirements.txt .

# Create virtual environment
RUN python -m venv /opt/venv

ENV PATH=/opt/venv/bin:$PATH

# Upgrade pip and install Python dependencies
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

# Install Playwright Firefox
RUN playwright install firefox

# Install Camoufox browser + GeoIP database
RUN python -m camoufox fetch && \
    python -c "from camoufox.locale import MMDB_FILE, download_mmdb; MMDB_FILE.exists() or download_mmdb()"


# ============================================================
# Stage 2: Runtime
# ============================================================
FROM python:3.13-slim-bookworm AS runtime

ENV HOME=/home/appuser \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/venv/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/home/appuser/.cache/ms-playwright \
    RUNTIME_DIR=/app/gpt_signup_hybrid/runtime

RUN useradd -m -u 10001 appuser

# Runtime dependencies:
# Xvfb = virtual display
# xauth = required by xvfb-run
# curl = health checks
# tini = proper PID 1
# gosu = drop privileges to appuser
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    xauth \
    curl \
    tini \
    gosu \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python virtual environment
COPY --from=builder /opt/venv /opt/venv

# Firefox/Camoufox system libraries
RUN playwright install-deps firefox

# Browser cache from builder
COPY --from=builder --chown=appuser:appuser \
    /home/appuser/.cache \
    /home/appuser/.cache

# ============================================================
# IMPORTANT:
# Your actual project is inside:
# gpt_signup_hybrid-main/
#
# Copy that project into /app/gpt_signup_hybrid
# ============================================================
COPY --chown=appuser:appuser \
    gpt_signup_hybrid-main/ \
    /app/gpt_signup_hybrid/

# Use the REAL entrypoint from the project folder
COPY --chown=root:root \
    gpt_signup_hybrid-main/docker-entrypoint.sh \
    /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create runtime directory
RUN mkdir -p /app/gpt_signup_hybrid/runtime && \
    chown -R appuser:appuser /app/gpt_signup_hybrid

WORKDIR /app/gpt_signup_hybrid

# ============================================================
# Railway port
# ============================================================
EXPOSE 8083

# tini as PID 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]

# Railway automatically provides $PORT
CMD ["sh", "-c", "exec xvfb-run -a python -m gpt_signup_hybrid web --host 0.0.0.0 --port ${PORT:-8083} --unsafe-expose-network"]

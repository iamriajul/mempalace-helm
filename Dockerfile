# ──────────────────────────────────────────────
# Stage 1 – build
# ──────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies (gcc for compiled extensions used by chromadb)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ──────────────────────────────────────────────
# Stage 2 – runtime
# ──────────────────────────────────────────────
FROM python:3.11-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/OWNER/mempalace-helm"
LABEL org.opencontainers.image.description="MemPalace – AI-powered memory palace application"
LABEL org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    # Default data paths – overridden by Helm ConfigMap in Kubernetes
    PALACE_DATA_PATH=/data/palace \
    CHROMA_DATA_PATH=/data/chroma

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY . .

# Non-root user for security.
# Data dirs are created here for local/Docker Compose runs; in Kubernetes
# they are replaced by PVC mounts (fsGroup in podSecurityContext handles ownership).
RUN addgroup --system mempalace \
    && adduser --system --ingroup mempalace mempalace \
    && mkdir -p /data/palace /data/chroma \
    && chown -R mempalace:mempalace /app /data

USER mempalace

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/healthz')" || exit 1

# Single worker – MemPalace uses in-process Chroma which is not safe to share
# across workers without an external Chroma server.  See README for details.
CMD ["python", "-m", "uvicorn", "mempalace.main:app", \
     "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

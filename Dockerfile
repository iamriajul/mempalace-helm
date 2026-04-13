# ──────────────────────────────────────────────
# Stage 1 – build
# ──────────────────────────────────────────────
# MemPalace is published to PyPI (pip install mempalace).
# This repo does not contain the application source — only the packaging.
FROM python:3.11-slim AS builder

WORKDIR /build

# gcc / g++ are required for chromadb's compiled extensions (hnswlib).
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc g++ build-essential \
    && rm -rf /var/lib/apt/lists/*

# Pin a specific MemPalace release via build-arg; defaults to latest.
# docker build --build-arg MEMPALACE_VERSION=3.1.0 .
ARG MEMPALACE_VERSION=
RUN if [ -n "$MEMPALACE_VERSION" ]; then \
        pip install --no-cache-dir --prefix=/install \
            "mempalace==${MEMPALACE_VERSION}" mcp-proxy; \
    else \
        pip install --no-cache-dir --prefix=/install \
            mempalace mcp-proxy; \
    fi

# ──────────────────────────────────────────────
# Stage 2 – runtime
# ──────────────────────────────────────────────
FROM python:3.11-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/iamriajul/mempalace-helm"
LABEL org.opencontainers.image.description="MemPalace MCP server exposed over SSE via mcp-proxy"
LABEL org.opencontainers.image.licenses="MIT"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# /data is the single PVC mount point.
#   /data/palace  → ChromaDB + knowledge_graph.sqlite3 + palace YAML files
#   /data/.mempalace/wal → write-ahead log (HOME is set to /data)
# Setting HOME=/data ensures expanduser("~/.mempalace") resolves inside the PVC.
ENV HOME=/data

COPY --from=builder /install /usr/local

# Non-root user.  In Kubernetes, podSecurityContext.fsGroup=1000 handles
# PVC ownership so the process can write to the mounted volume.
RUN addgroup --system --gid 1000 mempalace \
    && adduser --system --uid 1000 --gid 1000 --no-create-home mempalace \
    && mkdir -p /data/palace \
    && chown -R mempalace:mempalace /data

USER mempalace

EXPOSE 8080

# mcp-proxy bridges the stdio MemPalace MCP server to SSE/Streamable-HTTP so
# multiple AI agents can connect to a single pod over the network.
# --pass-environment forwards all container env vars (MEMPALACE_PALACE_PATH,
# etc.) into the spawned mempalace subprocess.
CMD ["mcp-proxy", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--pass-environment", \
     "--", \
     "python", "-m", "mempalace.mcp_server", \
     "--palace", "/data/palace"]

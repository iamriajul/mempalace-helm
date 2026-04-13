# mempalace-helm

Helm chart and container image build pipeline for
[MemPalace](https://github.com/MemPalace/mempalace) — the highest-scoring AI
memory system ever benchmarked, backed by ChromaDB and SQLite.

---

## How it works

MemPalace is a **stdio-based MCP server** (`python -m mempalace.mcp_server`).
It communicates via JSON-RPC over stdin/stdout — it has no built-in HTTP server.

This chart wraps it with **[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)**,
which bridges the stdio server to SSE/Streamable-HTTP. This lets multiple AI
agents connect to a **single shared pod** over the network:

```
Agent A ──SSE──┐
Agent B ──SSE──┤──► mcp-proxy :8080 ──stdio──► mempalace.mcp_server
Agent C ──SSE──┘                                      │
                                              /data/palace/
                                        (ChromaDB + knowledge graph
                                           + palace YAML + WAL)
```

All agents share one palace. Each agent gets its own wing and diary inside it.

---

## What this repo ships

| Artifact | Location |
|---|---|
| `Dockerfile` | Installs `mempalace` + `mcp-proxy` from PyPI; no source copy |
| Helm chart | `helm/mempalace/` |
| Image CI | `.github/workflows/image.yml` — builds & pushes to GHCR with cache |
| Helm CI | `.github/workflows/helm-release.yml` — lints, packages & publishes OCI |

---

## What the chart deploys

- `Deployment` running `mcp-proxy` → `mempalace.mcp_server` (1 replica)
- `PersistentVolumeClaim` at `/data` (palace files, ChromaDB index, WAL)
- `ClusterIP` Service on port 80 → container port 8080
- Optional `Ingress` for external agent access
- `ConfigMap` with `MEMPALACE_PALACE_PATH`
- `ServiceAccount` (token automounting disabled)

---

## Quick start

### Prerequisites

- `kubectl` connected to a cluster
- `helm` ≥ 3.14

### Install

The chart is public — no login required.

```bash
helm install mempalace \
  oci://ghcr.io/iamriajul/charts/mempalace \
  --version 0.1.0 \
  --namespace mempalace --create-namespace
```

### Connect an agent

mcp-proxy exposes two endpoints on port 8080:

| Transport | Path | MCP spec version |
|---|---|---|
| SSE (legacy, widely supported) | `/sse` | 2024-11-05 |
| Streamable HTTP (recommended) | `/mcp` | 2025-03-26+ |

**Claude Code** (one-time setup per agent machine):

```bash
# 1. Get the service URL
#    In-cluster: use the Kubernetes DNS name directly
SERVICE_URL="http://mempalace.mempalace.svc.cluster.local"

#    Outside the cluster: port-forward for local testing
kubectl port-forward svc/mempalace 8080:80 -n mempalace
SERVICE_URL="http://127.0.0.1:8080"

# 2. Register MemPalace as an MCP server in Claude Code
claude mcp add mempalace --transport sse "${SERVICE_URL}/sse"

# 3. Verify it is registered
claude mcp list
```

This writes the following into your Claude Code config (`~/.claude.json`):

```json
{
  "mcpServers": {
    "mempalace": {
      "type": "sse",
      "url": "http://mempalace.mempalace.svc.cluster.local/sse"
    }
  }
}
```

On next launch Claude Code connects automatically and the 19 MemPalace tools
(`mempalace_search`, `mempalace_add_drawer`, `mempalace_kg_query`, …) are
available without any further configuration.

---

## Building and pushing the image

The Dockerfile installs MemPalace and mcp-proxy from PyPI — no application
source lives in this repo.

```bash
# Build (pin a version with --build-arg MEMPALACE_VERSION=3.1.0)
docker build -t ghcr.io/iamriajul/mempalace:local .

# Push
docker login ghcr.io -u YOUR_GITHUB_USER -p YOUR_PAT
docker push ghcr.io/iamriajul/mempalace:local
```

The CI workflow (`.github/workflows/image.yml`) triggers on push to `main` and
on `v*.*.*` tags. BuildKit registry cache is stored in GHCR — no extra storage
needed.

---

## Helm chart operations

```bash
# Lint
helm lint helm/mempalace --strict

# Dry-run render
helm template mempalace ./helm/mempalace --debug

# Package
helm package helm/mempalace --destination /tmp/helm-packages

# Publish to GHCR OCI
helm registry login ghcr.io -u YOUR_GITHUB_USER -p YOUR_PAT
helm push /tmp/helm-packages/mempalace-0.1.0.tgz oci://ghcr.io/iamriajul/charts

# Verify
helm pull oci://ghcr.io/iamriajul/charts/mempalace --version 0.1.0
```

---

## Key values

| Value | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/iamriajul/mempalace` | Container image |
| `image.tag` | *(chart appVersion)* | Image tag |
| `replicaCount` | `1` | Must stay 1 — see [Replica count](#replica-count) |
| `service.type` | `ClusterIP` | Service type |
| `ingress.enabled` | `false` | Expose SSE endpoint externally |
| `persistence.enabled` | `true` | PVC-backed palace storage |
| `persistence.size` | `10Gi` | PVC size |
| `persistence.storageClass` | *(cluster default)* | StorageClass |
| `config.palacePath` | `/data/palace` | Palace directory inside the PVC |
| `resources.requests.memory` | `512Mi` | ChromaDB HNSW index is in-memory |
| `resources.limits.memory` | `2Gi` | Grows with palace size |
| `env.extraEnv` | `[]` | Extra env vars passed to MemPalace subprocess |

Full reference: [`helm/mempalace/values.yaml`](helm/mempalace/values.yaml).

---

## Persistence

A single PVC is mounted at `/data`. It holds everything:

| Path | Contents |
|---|---|
| `/data/palace/` | ChromaDB files, `knowledge_graph.sqlite3`, palace YAML |
| `/data/.mempalace/wal/` | Write-ahead log (`HOME=/data` in container) |

The PVC has `helm.sh/resource-policy: keep` — it **survives `helm uninstall`**.
Delete manually only when you no longer need the data:

```bash
kubectl delete pvc mempalace-data -n mempalace
```

When `persistence.enabled: false` the volume uses `emptyDir` — data is lost on
pod restart. Use only for ephemeral testing.

---

## Auth

MemPalace has **no application-level authentication**. Auth is enforced at the
network layer:

- **In-cluster agents**: use a `NetworkPolicy` to restrict which pods can reach
  the `mempalace` Service.
- **External access via Ingress**: configure your ingress controller's auth
  mechanism — e.g. nginx `auth-secret`, `oauth2-proxy`, or mTLS.

---

## Ingress example (external agents)

```yaml
# values-prod.yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # Restrict to internal clients or add auth via oauth2-proxy
  hosts:
    - host: mempalace.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mempalace-tls
      hosts:
        - mempalace.example.com
```

```bash
helm upgrade mempalace ./helm/mempalace -f values-prod.yaml -n mempalace

# Agents connect to:
#   https://mempalace.example.com/sse
```

---

## Upgrade notes

```bash
helm upgrade mempalace oci://ghcr.io/iamriajul/charts/mempalace \
  --version 0.2.0 --namespace mempalace --reuse-values
```

The Deployment uses `strategy: Recreate` — the old pod terminates before the
new one starts (required for `ReadWriteOnce` PVCs). Expect brief downtime. For
zero-downtime upgrades, use a `ReadWriteMany` StorageClass and switch to
`RollingUpdate`.

---

## Replica count

**Keep `replicaCount: 1`.**

mcp-proxy spawns exactly one `mempalace.mcp_server` subprocess. That subprocess
holds an exclusive in-process ChromaDB connection and writes directly to the PVC.
Running a second replica would create a second ChromaDB client against the same
`ReadWriteOnce` PVC — either the mount fails or the HNSW index is corrupted.

Multiple **agents** connecting is fine — they all share the same single pod via
SSE. That is the intended multi-agent architecture.

---

## Known limitations

- Single replica only (see above).
- `readOnlyRootFilesystem` is disabled — ChromaDB writes its HNSW index and
  temp files at runtime. Hardening path: mount a writable `emptyDir` at `/tmp`
  and re-enable the flag.
- No `NetworkPolicy` is shipped. Add one to restrict which agent pods can reach
  the Service.
- mcp-proxy does not expose an HTTP health endpoint; probes use `tcpSocket`.

---

## Repository layout

```
.
├── Dockerfile                     # pip install mempalace + mcp-proxy from PyPI
├── .dockerignore
├── README.md
├── .github/
│   └── workflows/
│       ├── image.yml              # build & push container image
│       └── helm-release.yml       # lint, package & publish Helm chart OCI
└── helm/
    └── mempalace/
        ├── Chart.yaml
        ├── values.yaml
        ├── .helmignore
        ├── charts/
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── service.yaml
            ├── ingress.yaml
            ├── pvc.yaml
            ├── configmap.yaml
            ├── secret.yaml        # comment-only; auth is at network layer
            ├── serviceaccount.yaml
            └── NOTES.txt
```

---

## License

MIT

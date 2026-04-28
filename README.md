# mempalace-helm

Helm chart and container image build pipeline for
[MemPalace](https://github.com/MemPalace/mempalace) — the highest-scoring AI
memory system ever benchmarked, backed by ChromaDB and SQLite.

---

## Quick start

### Prerequisites

- `kubectl` connected to a cluster
- `helm` ≥ 3.14

### Install

The chart is public — no login required.

```bash
helm install mempalace \
  oci://ghcr.io/iamriajul/helm-charts/mempalace \
  --version 0.1.1 \
  --namespace mempalace --create-namespace
```

### Connect an agent

Use Streamable HTTP (`/mcp`, recommended) or SSE (`/sse`, legacy).

**One-time setup on each agent machine:**

```bash
# Set your MemPalace base URL
SERVICE_URL="http://mempalace.mempalace.svc.cluster.local"

# Install + configure MCP + hooks
curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | \
  bash -s -- --url "${SERVICE_URL}" --transport http --scope user
```

Optional bearer token:

```bash
MCP_BEARER_TOKEN="<YOUR_TOKEN>" curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | \
  bash -s -- --url "${SERVICE_URL}" --transport http --scope user
```

If `--url` is omitted, installer prompts for `SERVICE_URL`. MCP registration now uses `npx --yes add-mcp`, so agent machines need `npx` available. Restart your CLI after setup.

Need deeper details? Jump to [Technical reference](#technical-reference).

---

## Quick run with Docker

No Kubernetes? Run MemPalace locally with a single command:

```bash
docker run -d \
  --name mempalace \
  -p 8080:8080 \
  -v mempalace-data:/data \
  ghcr.io/iamriajul/mempalace:latest
```

Then register MCP + hooks (headless-safe):

```bash
~/.mempalace/hooks/install.sh --url http://127.0.0.1:8080 --transport http --scope user
```

Data is persisted in the `mempalace-data` Docker volume across container restarts.

---

## Auto-save hooks (efficiency)

MemPalace ships two hook scripts for automatic saves.

| Hook | Event | What it does |
|---|---|---|
| `mempal_save_hook.sh` | `Stop` (every response) | Counts messages; every 15 blocks Claude from stopping and forces a structured diary + palace save |
| `mempal_precompact_hook.sh` | `PreCompact` | Always blocks before context compression — emergency full save before the window shrinks |

Hooks only emit block decisions; actual memory writes happen through connected MCP tools.

### CLI setup (recommended)

Run this once on each agent machine:

```bash
curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | bash
```

If `SERVICE_URL`/`--url` is not provided, the installer asks interactively.
It also optionally asks for a bearer token (or use `--token` / `MCP_BEARER_TOKEN`).

Then run full headless setup directly:

```bash
curl -fsSL https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/install.sh | \
  bash -s -- --url http://mempalace.mempalace.svc.cluster.local --transport http --scope user
```

### Manual setup

If you prefer to bootstrap only the local hook CLI first:

```bash
mkdir -p ~/.mempalace/hooks
curl -fsSL -o ~/.mempalace/hooks/install.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/install.sh
curl -fsSL -o ~/.mempalace/hooks/mempal_save_hook.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/mempal_save_hook.sh
curl -fsSL -o ~/.mempalace/hooks/mempal_precompact_hook.sh \
  https://raw.githubusercontent.com/iamriajul/mempalace-helm/master/hooks/mempal_precompact_hook.sh
chmod +x ~/.mempalace/hooks/install.sh \
         ~/.mempalace/hooks/mempal_save_hook.sh \
         ~/.mempalace/hooks/mempal_precompact_hook.sh
~/.mempalace/hooks/install.sh --url http://mempalace.mempalace.svc.cluster.local --transport http --scope user
```

This installs MCP config via `add-mcp` into detected agent configs and writes Claude hook config to `~/.claude/settings.local.json` for `--scope user` (or `./.claude/settings.local.json` for `--scope project`).

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

The CI workflow (`.github/workflows/image.yml`) triggers on push to `master` and
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
helm push /tmp/helm-packages/mempalace-0.1.1.tgz oci://ghcr.io/iamriajul/helm-charts

# Verify
helm pull oci://ghcr.io/iamriajul/helm-charts/mempalace --version 0.1.1
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

MemPalace has **no built-in application auth**, so this chart provides an
optional auth sidecar. When `auth.enabled=true`, an unprivileged NGINX sidecar
listens on port `8080`, requires `Authorization: Bearer <token>`, and proxies
to the internal `mcp-proxy` listener on `8081`.

Enable it with a generated token:

```bash
helm upgrade --install mempalace ./helm/mempalace \
  --namespace mempalace --create-namespace \
  --set auth.enabled=true \
  --set auth.token=$(openssl rand -hex 32)
```

Or use an existing Secret:

```bash
helm upgrade --install mempalace ./helm/mempalace \
  --namespace mempalace --create-namespace \
  --set auth.enabled=true \
  --set auth.existingSecret=mempalace-auth
```

This is transport-layer protection for the exposed HTTP/SSE endpoints. You may
still want `NetworkPolicy`, ingress-level auth, or both, depending on where the
service is reachable from.

### Automatic TLS

If your cluster has cert-manager installed, the chart can request and renew the
Ingress certificate automatically.

```bash
helm upgrade --install mempalace ./helm/mempalace \
  --namespace mempalace --create-namespace \
  --set ingress.enabled=true \
  --set ingress.className=public \
  --set ingress.hosts[0].host=mempalace.example.com \
  --set ingress.certManager.enabled=true \
  --set ingress.certManager.clusterIssuer=cert-manager-global
```

When `ingress.certManager.enabled=true`, the chart adds the cert-manager issuer
annotation and renders the `spec.tls` block automatically. The TLS secret name
defaults to `<release>-tls`, but can be overridden with
`ingress.certManager.secretName`.

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

# Agents connect to (Streamable HTTP, recommended):
#   https://mempalace.example.com/mcp
# Legacy SSE:
#   https://mempalace.example.com/sse
```

---

## Upgrade notes

```bash
helm upgrade mempalace oci://ghcr.io/iamriajul/helm-charts/mempalace \
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

## Technical reference

### How it works

MemPalace is a **stdio-based MCP server** (`python -m mempalace.mcp_server`).
It communicates via JSON-RPC over stdin/stdout — it has no built-in HTTP server.

This chart wraps it with **[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)**,
which bridges the stdio server to SSE/Streamable-HTTP:

```
Agent A ──HTTP /mcp──┐
Agent B ──HTTP /mcp──┤──► mcp-proxy :8080 ──stdio──► mempalace.mcp_server
Agent C ──SSE  /sse──┘                                      │
                                              /data/palace/
                                        (ChromaDB + knowledge graph
                                           + palace YAML + WAL)
```

All agents share one palace. Each agent gets its own wing and diary inside it.

### What this repo ships

| Artifact | Location |
|---|---|
| `Dockerfile` | Installs `mempalace` + `mcp-proxy` from PyPI; no source copy |
| Helm chart | `helm/mempalace/` |
| Image CI | `.github/workflows/image.yml` — builds & pushes to GHCR with cache |
| Helm CI | `.github/workflows/helm-release.yml` — lints, packages & publishes OCI |

### What the chart deploys

- `Deployment` running `mcp-proxy` → `mempalace.mcp_server` (1 replica)
- `PersistentVolumeClaim` at `/data` (palace files, ChromaDB index, WAL)
- `ClusterIP` Service on port 80 → container port 8080
- Optional `Ingress` for external agent access
- `ConfigMap` with `MEMPALACE_PALACE_PATH`
- `ServiceAccount` (token automounting disabled)

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

# mempalace-helm

Helm chart and container image build pipeline for
[MemPalace](https://github.com/OWNER/mempalace) — an AI-powered memory palace
application backed by [ChromaDB](https://www.trychroma.com/).

---

## What this repo is

This repository ships:

| Artifact | Location |
|---|---|
| `Dockerfile` | Multi-stage Python 3.11 image for MemPalace |
| Helm chart | `helm/mempalace/` |
| Image CI | `.github/workflows/image.yml` — builds & pushes to GHCR |
| Helm CI | `.github/workflows/helm-release.yml` — lints, packages & publishes to GHCR OCI |

The Helm chart is the **primary deployment mechanism**. Raw manifests are not provided.

---

## What it deploys

- MemPalace application container (single replica by design — see [Replica note](#replica-count))
- `PersistentVolumeClaim` for palace data
- `PersistentVolumeClaim` for ChromaDB data
- `ClusterIP` Service
- Optional `Ingress`
- `ConfigMap` for non-sensitive runtime config
- Optional `Secret` for the auth token
- `ServiceAccount` (automounting disabled)

---

## Quick start

### Prerequisites

- `kubectl` connected to a cluster
- `helm` ≥ 3.14 (OCI support enabled by default)

### Install from source (local chart)

```bash
git clone https://github.com/OWNER/mempalace-helm.git
cd mempalace-helm

helm install mempalace ./helm/mempalace \
  --namespace mempalace --create-namespace \
  --set image.repository=ghcr.io/OWNER/mempalace \
  --set image.tag=main
```

### Install from GHCR OCI

```bash
helm registry login ghcr.io --username YOUR_GITHUB_USER --password YOUR_PAT

helm install mempalace \
  oci://ghcr.io/OWNER/charts/mempalace \
  --version 0.1.0 \
  --namespace mempalace --create-namespace
```

---

## Building and pushing the container image

### Manually

```bash
# Build
docker build -t ghcr.io/OWNER/mempalace:local .

# Push (requires docker login ghcr.io first)
docker login ghcr.io -u YOUR_GITHUB_USER -p YOUR_PAT
docker push ghcr.io/OWNER/mempalace:local
```

### Via GitHub Actions

The workflow `.github/workflows/image.yml` triggers automatically on:

- Push to `main` → tags image as `main` + `sha-<short-sha>`
- Push of a `v*.*.*` tag → tags as semver (`1.2.3`, `1.2`) + `sha-<short-sha>`
- Manual `workflow_dispatch`

BuildKit registry cache is stored in GHCR alongside the image
(`ghcr.io/OWNER/mempalace:buildcache`) — no extra storage required.

---

## Helm chart operations

### Lint

```bash
helm lint helm/mempalace --strict
```

### Render templates locally (dry run)

```bash
helm template mempalace ./helm/mempalace --debug
```

### Package

```bash
helm package helm/mempalace --destination /tmp/helm-packages
```

### Publish to GHCR OCI manually

```bash
helm registry login ghcr.io -u YOUR_GITHUB_USER -p YOUR_PAT

helm push /tmp/helm-packages/mempalace-0.1.0.tgz \
  oci://ghcr.io/OWNER/charts
```

### Verify the published chart

```bash
helm pull oci://ghcr.io/OWNER/charts/mempalace --version 0.1.0
```

---

## Key values to customize

| Value | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/OWNER/mempalace` | Container image repository |
| `image.tag` | *(chart appVersion)* | Image tag |
| `replicaCount` | `1` | See [Replica note](#replica-count) |
| `service.type` | `ClusterIP` | `ClusterIP`, `NodePort`, or `LoadBalancer` |
| `ingress.enabled` | `false` | Enable Kubernetes Ingress |
| `persistence.enabled` | `true` | Enable PVC-backed storage |
| `persistence.palace.size` | `1Gi` | PVC size for palace data |
| `persistence.chroma.size` | `5Gi` | PVC size for ChromaDB data |
| `persistence.storageClass` | *(cluster default)* | StorageClass for both PVCs |
| `auth.enabled` | `false` | Inject `AUTH_TOKEN` env var |
| `auth.token` | `""` | Token value (use `auth.existingSecret` in production) |
| `auth.existingSecret` | `""` | Use a pre-existing Secret (must have key `token`) |
| `resources.requests.memory` | `256Mi` | Pod memory request |
| `resources.limits.memory` | `1Gi` | Pod memory limit |
| `env.extraEnv` | `[]` | Extra env vars (e.g. `OPENAI_API_KEY`) |

Full list: see [`helm/mempalace/values.yaml`](helm/mempalace/values.yaml).

---

## Persistence

Two PVCs are created when `persistence.enabled: true` (the default):

| PVC | Mount path | Default size |
|---|---|---|
| `<release>-palace` | `/data/palace` | `1Gi` |
| `<release>-chroma` | `/data/chroma` | `5Gi` |

Both PVCs carry `helm.sh/resource-policy: keep` — they **survive `helm uninstall`**
to prevent accidental data loss. Delete them manually when no longer needed:

```bash
kubectl delete pvc mempalace-palace mempalace-chroma -n mempalace
```

When `persistence.enabled: false` both paths use `emptyDir` — data is lost on pod
restart. Use this for ephemeral testing only.

---

## Auth

```yaml
# Dev: inline token
auth:
  enabled: true
  token: "my-secret-token"

# Production: reference a pre-existing Secret
auth:
  enabled: true
  existingSecret: my-external-secret   # must have a key named "token"
```

When `auth.enabled: true` the chart mounts `AUTH_TOKEN` into the container.
Never commit real tokens. Pass via `--set auth.token=...` at deploy time, or use
Sealed Secrets / External Secrets Operator.

---

## Ingress example

```yaml
# values-prod.yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
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
```

---

## Upgrade notes

```bash
helm upgrade mempalace oci://ghcr.io/OWNER/charts/mempalace \
  --version 0.2.0 \
  --namespace mempalace \
  --reuse-values
```

The Deployment uses `strategy.type: Recreate` because PVCs default to
`ReadWriteOnce`. The old pod is terminated before the new one starts — expect a
brief downtime during upgrades. For zero-downtime upgrades, switch to a
`ReadWriteMany` StorageClass and change the strategy to `RollingUpdate`.

---

## Replica count

**Keep `replicaCount: 1`.**

MemPalace runs ChromaDB in embedded (in-process) mode writing directly to the
`/data/chroma` PVC. Running multiple replicas against the same `ReadWriteOnce`
PVC will either fail at mount time or corrupt the ChromaDB index.

To scale horizontally, deploy a standalone
[Chroma server](https://docs.trychroma.com/production/deployment) and configure
MemPalace to connect via `CHROMA_HOST` / `CHROMA_PORT` env vars (use
`env.extraEnv`). Once ChromaDB is external, replicas can be increased safely.

---

## Known limitations

- Single-replica only (see above).
- The `Dockerfile` `CMD` targets `mempalace.main:app` (uvicorn/ASGI). Adjust
  if the upstream project uses a different entry point.
- `readOnlyRootFilesystem` is disabled because ChromaDB writes temp files at
  startup. Mount a writable `emptyDir` at `/tmp` and re-enable for hardening.
- No `NetworkPolicy` is shipped. Add one appropriate to your CNI if needed.

---

## Repository layout

```
.
├── Dockerfile
├── .dockerignore
├── README.md
├── .github/
│   └── workflows/
│       ├── image.yml          # build & push container image
│       └── helm-release.yml   # lint, package & publish Helm chart
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
            ├── secret.yaml
            ├── serviceaccount.yaml
            └── NOTES.txt
```

---

## License

MIT

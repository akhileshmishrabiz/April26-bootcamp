# StatefulSets & CloudNativePG Lab

Hands-on exercise to understand **StatefulSets** (ordered pods, sticky names, headless services) and why operators like **CloudNativePG (CNPG)** use **CRDs** for production Postgres on Kubernetes.

---

## What you will learn

| Demo | Folder | What it shows |
|------|--------|---------------|
| **Demo 1** | `demo1-postgres-statefulset/` | Raw StatefulSet + headless Service + Postgres |
| **Demo 2** | `demo2-cnpg-postgres/` | CNPG operator + `Cluster` CRD for HA Postgres |

### Demo 1 — StatefulSet basics

- **Ordered startup** — `postgres-0` starts before `postgres-1`, then `postgres-2`
- **Ordered shutdown** — scale down removes highest ordinal first
- **Sticky pod names** — delete `postgres-1`, the replacement is still `postgres-1`
- **Headless Service** — stable DNS per pod: `postgres-0.postgres.demo1-statefulset.svc.cluster.local`
- **One PVC per pod** — via `volumeClaimTemplates`

### Demo 2 — Why use a CRD (CNPG)?

A plain StatefulSet gives you stable names and disks, but **does not** give you:

- Automatic primary/replica roles
- Streaming replication setup
- Failover when the primary dies
- Rolling upgrades, backups, connection pooling services

CNPG installs an operator and you declare a **`Cluster`** CRD. The operator builds and manages the StatefulSet, secrets, services, and replication for you.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Internet access (Demo 2 downloads the CNPG operator manifest)

Verify:

```bash
docker info
kind version
kubectl version --client
```

---

## Project layout

```text
statefulsets-demo/
├── EXERCISE.md
├── kind-config.yaml
├── deploy.sh                         # fresh cluster + both demos
├── demo1-postgres-statefulset/
│   ├── deploy.sh
│   └── k8s/
│       ├── namespace.yaml
│       ├── secret.yaml
│       ├── service.yaml              # headless
│       └── statefulset.yaml
└── demo2-cnpg-postgres/
    ├── deploy.sh
    └── k8s/
        ├── namespace.yaml
        └── cluster.yaml              # CNPG Cluster CRD
```

---

## Step 1 — Bootstrap from scratch

```bash
cd Kubernetes-world/statefulsets-demo
bash deploy.sh
```

This script:

1. Deletes any existing `statefulsets-demo` kind cluster
2. Creates a new cluster (1 control-plane + 1 worker)
3. Deploys Demo 1 (Postgres StatefulSet)
4. Installs CloudNativePG operator
5. Deploys Demo 2 (CNPG `Cluster`)

Demo 2 can take **3–5 minutes** while Postgres pods start and replication initializes.

Confirm:

```bash
kubectl config use-context kind-statefulsets-demo
kubectl get nodes
kubectl -n demo1-statefulset get pods
kubectl -n demo2-cnpg get cluster,pods,svc
```

---

## Step 2 — Demo 1: StatefulSet with Postgres

> **Important:** Demo 1 runs **three independent Postgres instances** (one database per pod). That is intentional — we are teaching StatefulSet mechanics, not HA replication. Demo 2 shows proper HA Postgres.

### 2.1 See ordered pod startup

If you just ran `deploy.sh`, pods are already up. To replay ordered startup:

```bash
kubectl -n demo1-statefulset delete statefulset postgres --cascade=orphan
kubectl -n demo1-statefulset delete pod -l app=postgres
kubectl apply -f demo1-postgres-statefulset/k8s/statefulset.yaml
```

Watch in another terminal:

```bash
kubectl -n demo1-statefulset get pods -l app=postgres -w
```

**Pass:** Pods appear in order: `postgres-0` → Ready, then `postgres-1` → Ready, then `postgres-2` → Ready.

### 2.2 See ordered scale-down

```bash
kubectl -n demo1-statefulset scale statefulset postgres --replicas=1
kubectl -n demo1-statefulset get pods -l app=postgres -w
```

**Pass:** `postgres-2` terminates first, then `postgres-1`, leaving only `postgres-0`.

Scale back up:

```bash
kubectl -n demo1-statefulset scale statefulset postgres --replicas=3
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-2 --timeout=180s
```

### 2.3 Headless Service — stable DNS per pod

Inspect the Service:

```bash
kubectl -n demo1-statefulset get svc postgres
```

**Pass:** `CLUSTER-IP` is `None` (headless).

Resolve DNS from inside the cluster:

```bash
kubectl -n demo1-statefulset run dns-test --rm -it --restart=Never \
  --image=busybox:1.36 -- \
  nslookup postgres-0.postgres.demo1-statefulset.svc.cluster.local
```

**Pass:** nslookup returns the pod IP for `postgres-0`.

Each pod gets its own hostname:

```text
postgres-0.postgres.demo1-statefulset.svc.cluster.local
postgres-1.postgres.demo1-statefulset.svc.cluster.local
postgres-2.postgres.demo1-statefulset.svc.cluster.local
```

### 2.4 Write data and prove name stickiness

Connect to `postgres-0` and insert a row:

```bash
kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \
  "CREATE TABLE IF NOT EXISTS demo (id serial PRIMARY KEY, note text, pod text);"

kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \
  "INSERT INTO demo (note, pod) VALUES ('first write', 'postgres-0');"

kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \
  "SELECT * FROM demo;"
```

Delete the pod:

```bash
kubectl -n demo1-statefulset delete pod postgres-0
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-0 --timeout=120s
```

Read the data again:

```bash
kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c "SELECT * FROM demo;"
```

**Pass:**

1. Pod name is still **`postgres-0`** (not a random Deployment name)
2. Row `first write` is **still there** (same PVC reattached)

Check the per-pod PVCs:

```bash
kubectl -n demo1-statefulset get pvc
```

**Pass:** `data-postgres-0`, `data-postgres-1`, `data-postgres-2` — one disk per ordinal.

### 2.5 Prove pods do NOT share data (Demo 1 limitation)

```bash
kubectl -n demo1-statefulset exec postgres-1 -- psql -U postgres -c "SELECT * FROM demo;"
```

**Pass:** Error or empty — `postgres-1` has its **own** empty database. This is why raw StatefulSet is not enough for HA Postgres.

---

## Step 3 — Demo 2: CloudNativePG (CRD)

### 3.1 See the CRD and operator

```bash
kubectl get crd clusters.postgresql.cnpg.io
kubectl -n cnpg-system get pods
kubectl -n demo2-cnpg get cluster demo-pg
```

**Pass:** CRD exists, operator pod is Running, Cluster status shows `Ready`.

### 3.2 Compare what CNPG created vs Demo 1

```bash
kubectl -n demo2-cnpg get pods
kubectl -n demo2-cnpg get svc
kubectl -n demo2-cnpg get pvc
```

**Pass:** You should see:

| Resource | Names |
|----------|-------|
| Pods | `demo-pg-1`, `demo-pg-2`, `demo-pg-3` |
| Services | `demo-pg-rw`, `demo-pg-ro`, `demo-pg-r` |
| PVCs | one per instance |

You declared **one** `Cluster` manifest. The operator created StatefulSet, secrets, services, and replication.

### 3.3 Find the primary and connect

```bash
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='Primary: {.status.currentPrimary}{"\n"}'
```

Connect via the read-write service (always hits the primary):

```bash
kubectl -n demo2-cnpg exec demo-pg-1 -- psql -U postgres -c "SELECT version();"
```

Or use the app user (password from bootstrap secret):

```bash
kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT current_user, current_database();"
```

Write data on the primary:

```bash
kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c \
  "CREATE TABLE IF NOT EXISTS orders (id serial PRIMARY KEY, item text);"

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c \
  "INSERT INTO orders (item) VALUES ('laptop'), ('keyboard');"

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

### 3.4 Prove replicas have the same data

Pick a non-primary pod (replace `demo-pg-2` if needed):

```bash
kubectl -n demo2-cnpg exec demo-pg-2 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

**Pass:** Same rows on the replica — **shared database**, unlike Demo 1.

### 3.5 Failover demo (optional, ~2 min)

Find the primary:

```bash
PRIMARY=$(kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='{.status.currentPrimary}')
echo "Primary is: $PRIMARY"
```

Kill the primary pod:

```bash
kubectl -n demo2-cnpg delete pod "$PRIMARY"
```

Watch CNPG elect a new primary:

```bash
kubectl -n demo2-cnpg get cluster demo-pg -w
```

After the cluster is `Ready` again:

```bash
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='New primary: {.status.currentPrimary}{"\n"}'
kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

**Pass:** New primary elected automatically; data still readable.

---

## Step 4 — Side-by-side comparison (presenter script)

| | Demo 1: StatefulSet | Demo 2: CNPG CRD |
|--|---------------------|------------------|
| **You write** | StatefulSet + headless Service + Secret | One `Cluster` CR |
| **Pod names** | `postgres-0`, `postgres-1`, … | `demo-pg-1`, `demo-pg-2`, … |
| **Storage** | 1 PVC per pod, isolated data | 1 PVC per pod, **replicated** data |
| **Replication** | Manual (not configured) | Automatic streaming replication |
| **Failover** | Manual | Operator handles it |
| **Connect** | `postgres-0.postgres...` (specific pod) | `demo-pg-rw` (always primary) |
| **Good for** | Learning StatefulSet behavior | Running Postgres in production |

**One-liner for the audience:**

> StatefulSet gives every pod a name and a disk. CNPG gives you a **database cluster** — it uses StatefulSets internally, but the CRD hides replication, failover, and upgrades.

---

## Architecture

### Demo 1

```text
Headless Service "postgres" (ClusterIP: None)
        │
        ├── postgres-0  ── PVC data-postgres-0  ── own Postgres DB
        ├── postgres-1  ── PVC data-postgres-1  ── own Postgres DB
        └── postgres-2  ── PVC data-postgres-2  ── own Postgres DB
```

### Demo 2

```text
Cluster CR "demo-pg"
        │
        ▼
CNPG Operator
        │
        ├── demo-pg-1 (primary)  ── replicates to ──► demo-pg-2, demo-pg-3
        │
        ├── Service demo-pg-rw  → primary only
        ├── Service demo-pg-ro  → replicas only
        └── Service demo-pg-r   → any instance
```

---

## Cleanup

```bash
kind delete cluster --name statefulsets-demo
```

Redeploy anytime:

```bash
bash deploy.sh
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Demo 1 pod stuck `Pending` | Check PVC: `kubectl -n demo1-statefulset get pvc,pv` |
| Demo 1 only postgres-0 starts | Wait — StatefulSet starts ordinals sequentially |
| CNPG install fails | Need internet; retry `bash demo2-cnpg-postgres/deploy.sh` |
| Cluster not `Ready` after 5 min | `kubectl -n demo2-cnpg describe cluster demo-pg` |
| `psql` auth fails | Demo 1 password: `demo-password` (user `postgres`). Demo 2 app user: `appuser` / `demo-password` |
| Wrong context | `kubectl config use-context kind-statefulsets-demo` |

---

## Quick reference

```bash
# Full setup
cd Kubernetes-world/statefulsets-demo
bash deploy.sh

# Demo 1
kubectl -n demo1-statefulset get pods -l app=postgres -w
kubectl -n demo1-statefulset get svc postgres
kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c "SELECT * FROM demo;"
kubectl -n demo1-statefulset delete pod postgres-0

# Demo 2
kubectl -n demo2-cnpg get cluster demo-pg
kubectl -n demo2-cnpg get pods,svc
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='{.status.currentPrimary}{"\n"}'
kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

# StatefulSet & CloudNativePG — One Exercise

Follow this guide **top to bottom**. You deploy both demos once, then walk through StatefulSet behavior (Demo 1) and CNPG HA Postgres (Demo 2) in a single session.

**Time:** ~45 minutes  
**Cluster:** 1 kind cluster, 2 namespaces, 2 Postgres setups side by side

---

## What you will learn

| Part | Demo | Key idea |
|------|------|----------|
| A | StatefulSet + Postgres | Stable pod names, ordered scaling, one disk per pod |
| B | CloudNativePG (CNPG) | One CRD gives you HA Postgres, replication, failover, backups, pooling |

**One-liner:** StatefulSet gives every pod a name and a disk. CNPG gives you a **database cluster**.

---

## Before you start

**Prerequisites:** Docker, kind, kubectl, internet (CNPG operator download)

```bash
docker info && kind version && kubectl version --client
cd Kubernetes-world/statefulsets-demo
```

---

## Part 0 — Deploy everything

### Step 0.1 — Create cluster and both demos

```bash
bash deploy.sh
```

This script:
1. Creates a fresh `statefulsets-demo` kind cluster
2. Deploys Demo 1 — Postgres StatefulSet (`demo1-statefulset`)
3. Installs CloudNativePG operator
4. Deploys Demo 2 — CNPG cluster with backups + pooler (`demo2-cnpg`)

Demo 2 takes **3–5 minutes**. Wait for the script to finish.

### Step 0.2 — Confirm both demos are up

```bash
kubectl config use-context kind-statefulsets-demo
kubectl -n demo1-statefulset get pods
kubectl -n demo2-cnpg get cluster,pods,svc,pooler
```

**Expected:**

| Namespace | Pods | Status |
|-----------|------|--------|
| `demo1-statefulset` | `postgres-0`, `postgres-1`, `postgres-2` | All Running |
| `demo2-cnpg` | `demo-pg-1`, `demo-pg-2`, `demo-pg-3` + pooler pods | All Running |
| `demo2-cnpg` | Cluster `demo-pg` | Ready |

---

## Part A — StatefulSet (Demo 1)

> Demo 1 runs **three independent Postgres instances** — one database per pod. That is intentional. We learn StatefulSet mechanics here; Demo 2 shows real HA.

### Step A.1 — Ordered pod startup

Replay ordered startup:

```bash
kubectl -n demo1-statefulset delete statefulset postgres --cascade=orphan
kubectl -n demo1-statefulset delete pod -l app=postgres
kubectl apply -f demo1-postgres-statefulset/k8s/statefulset.yaml
kubectl -n demo1-statefulset get pods -l app=postgres -w
```

**Expected:** `postgres-0` → Ready, then `postgres-1` → Ready, then `postgres-2` → Ready (Ctrl+C to stop watch).

### Step A.2 — Ordered scale-down

```bash
kubectl -n demo1-statefulset scale statefulset postgres --replicas=1
kubectl -n demo1-statefulset get pods -l app=postgres -w
```

**Expected:** `postgres-2` dies first, then `postgres-1`, only `postgres-0` remains.

Scale back up:

```bash
kubectl -n demo1-statefulset scale statefulset postgres --replicas=3
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-2 --timeout=180s
```

### Step A.3 — Headless Service (stable DNS per pod)

```bash
kubectl -n demo1-statefulset get svc postgres
```

**Expected:** `CLUSTER-IP` is `None` (headless).

Each pod gets stable DNS:

```text
postgres-0.postgres.demo1-statefulset.svc.cluster.local
postgres-1.postgres.demo1-statefulset.svc.cluster.local
postgres-2.postgres.demo1-statefulset.svc.cluster.local
```

### Step A.4 — Sticky name + persistent data

Write data on `postgres-0`:

```bash
kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \
  "CREATE TABLE IF NOT EXISTS demo (id serial PRIMARY KEY, note text);"

kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c \
  "INSERT INTO demo (note) VALUES ('first write');"

kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c "SELECT * FROM demo;"
```

Delete the pod and read again:

```bash
kubectl -n demo1-statefulset delete pod postgres-0
kubectl -n demo1-statefulset wait --for=condition=Ready pod/postgres-0 --timeout=120s
kubectl -n demo1-statefulset exec postgres-0 -- psql -U postgres -c "SELECT * FROM demo;"
```

**Expected:**
1. Pod name is still `postgres-0`
2. Row `first write` is still there (same PVC reattached)

Check one PVC per pod:

```bash
kubectl -n demo1-statefulset get pvc
```

**Expected:** `data-postgres-0`, `data-postgres-1`, `data-postgres-2`

### Step A.5 — Pods do NOT share data (StatefulSet limitation)

```bash
kubectl -n demo1-statefulset exec postgres-1 -- psql -U postgres -c "SELECT * FROM demo;"
```

**Expected:** Empty or error — `postgres-1` has its own separate database.

**Takeaway:** StatefulSet gives names and disks, but not replication. That is why we need CNPG next.

---

## Part B — CloudNativePG (Demo 2)

### Step B.1 — See what one CRD created

```bash
kubectl get crd clusters.postgresql.cnpg.io
kubectl -n cnpg-system get pods
kubectl -n demo2-cnpg get cluster demo-pg
kubectl -n demo2-cnpg get pods,svc,pvc,pooler
```

**Expected:**

| Resource | What CNPG created |
|----------|-------------------|
| Pods | `demo-pg-1`, `demo-pg-2`, `demo-pg-3` |
| Services | `demo-pg-rw` (primary), `demo-pg-ro` (replicas), `demo-pg-r` (any) |
| Pooler | `demo-pg-pooler-rw` (PgBouncer in front of primary) |
| Backups | MinIO store + `ScheduledBackup` |

You wrote **one** `Cluster` manifest. The operator built everything else.

### Step B.2 — Connect to the primary and write data

```bash
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='Primary: {.status.currentPrimary}{"\n"}'

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT current_user, current_database();"

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c \
  "CREATE TABLE IF NOT EXISTS orders (id serial PRIMARY KEY, item text);"

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c \
  "INSERT INTO orders (item) VALUES ('laptop'), ('keyboard');"

kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

**Expected:** Two rows inserted on the primary.

### Step B.3 — Prove replicas share the same data

```bash
kubectl -n demo2-cnpg exec demo-pg-2 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

**Expected:** Same rows on the replica — unlike Demo 1, this is one shared database.

### Step B.4 — Failover (kill the primary)

```bash
PRIMARY=$(kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='{.status.currentPrimary}')
echo "Primary is: $PRIMARY"
kubectl -n demo2-cnpg delete pod "$PRIMARY"
kubectl -n demo2-cnpg get cluster demo-pg -w
```

Wait until status is `Ready` again (Ctrl+C), then:

```bash
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='New primary: {.status.currentPrimary}{"\n"}'
kubectl -n demo2-cnpg exec demo-pg-1 -- env PGPASSWORD=demo-password \
  psql -U appuser -d appdb -h 127.0.0.1 -c "SELECT * FROM orders;"
```

**Expected:** New primary elected automatically; data still readable.

### Step B.5 — Backups

```bash
kubectl -n demo2-cnpg get backup,scheduledbackup
```

Trigger a manual backup:

```bash
kubectl apply -f demo2-cnpg-postgres/k8s/backup-on-demand.yaml
kubectl -n demo2-cnpg get backup demo-pg-manual -w
```

**Expected:** Backup status becomes `completed`.

### Step B.6 — Connection pooling

Connect via PgBouncer pooler instead of direct primary service:

```bash
kubectl -n demo2-cnpg run psql-pool --rm -it --restart=Never \
  --image=postgres:16 --env PGPASSWORD=demo-password -- \
  psql -h demo-pg-pooler-rw -U appuser -d appdb -c "SELECT * FROM orders;"
```

**Expected:** Same data, routed through `demo-pg-pooler-rw`.

| Service | Use when |
|---------|----------|
| `demo-pg-rw` | Direct connection to primary |
| `demo-pg-pooler-rw` | Pooled connections (transaction mode) |
| `demo-pg-ro` | Read-only queries to replicas |

---

## Part C — Compare both demos

Run this and fill in what you observe:

```bash
echo "=== Demo 1: StatefulSet ==="
kubectl -n demo1-statefulset get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
kubectl -n demo1-statefulset get pvc --no-headers | wc -l | xargs echo "PVC count:"

echo "=== Demo 2: CNPG ==="
kubectl -n demo2-cnpg get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
kubectl -n demo2-cnpg get cluster demo-pg -o jsonpath='Primary: {.status.currentPrimary}{"\n"}'
```

| | Demo 1: StatefulSet | Demo 2: CNPG |
|--|---------------------|--------------|
| **You write** | StatefulSet + headless Service + Secret | One `Cluster` CR |
| **Pod names** | `postgres-0`, `postgres-1`, … | `demo-pg-1`, `demo-pg-2`, … |
| **Data** | Isolated per pod | Replicated across pods |
| **Failover** | Manual | Automatic |
| **Backups / pooling** | Not included | MinIO backups + PgBouncer pooler |
| **Good for** | Learning StatefulSet behavior | Production Postgres on K8s |

---

## Reset & cleanup

```bash
# Redeploy from scratch
bash deploy.sh

# Delete cluster
kind delete cluster --name statefulsets-demo
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Demo 1 pod stuck Pending | `kubectl -n demo1-statefulset get pvc,pv` |
| Only postgres-0 starts | Wait — StatefulSet starts ordinals in order |
| CNPG cluster not Ready | `kubectl -n demo2-cnpg describe cluster demo-pg` |
| Backup stuck | `kubectl -n demo2-cnpg get pods -l app=minio` — MinIO must be Running |
| Wrong context | `kubectl config use-context kind-statefulsets-demo` |
| Demo 1 password | user `postgres`, password `demo-password` |
| Demo 2 app user | user `appuser`, password `demo-password` |

---

## File reference

```text
statefulsets-demo/
├── EXERCISE.md                         ← this guide
├── deploy.sh                           ← deploy both demos
├── demo1-postgres-statefulset/k8s/     ← StatefulSet + headless Service
└── demo2-cnpg-postgres/k8s/            ← CNPG Cluster, backup, pooler
    ├── cluster.yaml
    ├── backup.yaml / backup-schedule.yaml
    └── pooler.yaml
```

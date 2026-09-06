# Kubernetes Volumes Lab — Hands-on Exercise

Learn how **PersistentVolumes** and **PersistentVolumeClaims** behave in two real scenarios:

1. **Demo 1** — Data survives when a pod is deleted and recreated
2. **Demo 2** — Multiple pods read and write the same disk at the same time

You will run everything locally with **kind** (Kubernetes in Docker).

---

## What you will be able to show

| Demo | Story | Proof |
|------|-------|-------|
| Demo 1 | A pod writes to disk every 5 seconds. You kill the pod. A new pod starts and keeps writing. | The log file still contains lines from the **old** pod name and the **new** pod name |
| Demo 2 | Three pods share one volume. Each pod writes its own name to a shared file. | One file contains timestamps from **three different pod names** |

---

## Prerequisites

Install these before you start:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

Verify:

```bash
docker info
kind version
kubectl version --client
```

---

## Project layout

```text
stateful-workload-k8s/
├── EXERCISE.md                 ← you are here
├── kind-config-vol.yaml        ← kind cluster + host volume mount
├── deploy.sh                   ← creates cluster and deploys both demos
├── demo1-pod-persistence/      ← Demo 1 manifests + deploy script
├── demo2-shared-volume/        ← Demo 2 manifests + deploy script
└── host-volume-data/           ← data written by pods (created at runtime)
    ├── demo1/events.log
    └── demo2/shared.log
```

---

## Step 0 — Configure the host volume path (required once)

kind runs Kubernetes inside Docker containers. To persist data on your laptop, we bind-mount **this project folder** into every kind node.

1. Open `kind-config-vol.yaml`
2. Replace the `hostPath` value with the **absolute path** to this folder on your machine

Example (update to match your username and path):

```yaml
hostPath: /Users/yourname/projects/April26-bootcamp/Kubernetes-world/stateful-workload-k8s
```

Both the control-plane and worker node entries must use the same path.

---

## Step 1 — Start from a clean slate

Open a terminal and go to this directory:

```bash
cd Kubernetes-world/stateful-workload-k8s
```

Remove any leftover data from a previous run (recommended for a clean demo):

```bash
rm -rf host-volume-data/demo1 host-volume-data/demo2
```

Create a fresh kind cluster and deploy both demos (~1 minute):

```bash
bash deploy.sh
```

Expected output ends with:

```text
Demo 1 ready (namespace: demo1-persistence)
Demo 2 ready (namespace: demo2-shared)
All demos deployed on cluster 'stateful-vol'.
```

Confirm the cluster is up:

```bash
kubectl config use-context kind-stateful-vol
kubectl get nodes
kubectl get pv,pvc -A
```

You should see:

- 2 nodes (`stateful-vol-control-plane`, `stateful-vol-worker`)
- PV `demo1-volume` bound to PVC `demo1-claim`
- PV `demo2-shared-volume` bound to PVC `demo2-shared-claim`

---

## Step 2 — Demo 1: Data persists across pod lifecycle

### Concept

- One **Deployment** with **1 replica**
- One **PVC** (`demo1-claim`) mounted at `/data` inside the pod
- The pod appends to `/data/events.log` every 5 seconds
- When the pod dies, the **volume stays**. The replacement pod mounts the same PVC.

### 2.1 Watch the pod write data

Terminal 1 — follow the log live:

```bash
kubectl -n demo1-persistence exec deploy/data-writer -- tail -f /data/events.log
```

Terminal 2 — note the current pod name:

```bash
kubectl -n demo1-persistence get pods -l app=data-writer
```

Example output:

```text
NAME                           READY   STATUS    RESTARTS   AGE
data-writer-69f775b-abc12      1/1     Running   0          30s
```

In the log you should see:

```text
=== Pod started: data-writer-69f775b-abc12 at ... ===
2026-09-06T07:00:00Z | pod=data-writer-69f775b-abc12
2026-09-06T07:00:05Z | pod=data-writer-69f775b-abc12
```

**Write down the pod name** (e.g. `data-writer-69f775b-abc12`). You will compare it after the kill step.

### 2.2 Kill the pod

Stop `tail -f` with `Ctrl+C`, then:

```bash
kubectl -n demo1-persistence delete pod -l app=data-writer
kubectl -n demo1-persistence wait --for=condition=Ready pod -l app=data-writer --timeout=60s
kubectl -n demo1-persistence get pods -l app=data-writer
```

The new pod has a **different name** (e.g. `data-writer-69f775b-xyz99`).

### 2.3 Validate persistence

```bash
kubectl -n demo1-persistence exec deploy/data-writer -- cat /data/events.log
```

**Pass criteria — you should see all of this in one file:**

1. `=== Pod started: <OLD-POD-NAME> ===` — from before you deleted the pod
2. Lines with `pod=<OLD-POD-NAME>`
3. `=== Pod started: <NEW-POD-NAME> ===` — from the replacement pod
4. Lines with `pod=<NEW-POD-NAME>`

That proves the **volume outlived the pod**.

### 2.4 Bonus — see the same file on your laptop

```bash
cat host-volume-data/demo1/events.log
```

The PV uses a hostPath under this project folder, so the data is visible outside the cluster.

---

## Step 3 — Demo 2: Multiple pods share one disk

### Concept

- One **Deployment** with **3 replicas**
- One **ReadWriteMany** PVC (`demo2-shared-claim`) shared by all three pods
- Each pod appends its pod name to `/data/shared.log` every 5 seconds

> **Note:** ReadWriteMany on hostPath works here because kind mounts the same host folder into every node. In production you would use NFS, EFS, CephFS, or another shared storage backend.

### 3.1 List the three pods

```bash
kubectl -n demo2-shared get pods -l app=shared-writer -o wide
```

You should see **3 Running pods**.

### 3.2 Watch the shared log

```bash
kubectl -n demo2-shared exec deploy/shared-writer -- tail -f /data/shared.log
```

Every few seconds you should see **three different pod names** in the same file:

```text
2026-09-06T07:00:00Z | pod=shared-writer-848c9fd94b-aaa | node=stateful-vol-worker
2026-09-06T07:00:00Z | pod=shared-writer-848c9fd94b-bbb | node=stateful-vol-worker
2026-09-06T07:00:00Z | pod=shared-writer-848c9fd94b-ccc | node=stateful-vol-worker
```

**Pass criteria:** One file, three distinct pod names, updating together.

### 3.3 See per-pod files on the same volume

```bash
POD=$(kubectl -n demo2-shared get pod -l app=shared-writer -o jsonpath='{.items[0].metadata.name}')
kubectl -n demo2-shared exec "$POD" -- ls -la /data/pods/
```

Each pod also maintains its own file: `/data/pods/<pod-name>.txt`.

### 3.4 Bonus — host file

```bash
tail -f host-volume-data/demo2/shared.log
```

---

## Step 4 — Presenting the demo (suggested script)

Use two terminals side by side for impact.

### Demo 1 script (~3 min)

1. **Setup:** “This pod writes to a PersistentVolumeClaim every 5 seconds.”
   ```bash
   kubectl -n demo1-persistence exec deploy/data-writer -- tail -f /data/events.log
   ```
2. **Action:** “I am deleting the pod. Kubernetes will create a new one.”
   ```bash
   kubectl -n demo1-persistence delete pod -l app=data-writer
   ```
3. **Proof:** “The new pod mounted the same volume. Old data is still here.”
   ```bash
   kubectl -n demo1-persistence exec deploy/data-writer -- cat /data/events.log
   ```

### Demo 2 script (~2 min)

1. **Setup:** “Three pods, one shared PVC.”
   ```bash
   kubectl -n demo2-shared get pods -l app=shared-writer
   ```
2. **Proof:** “All three write to the same file.”
   ```bash
   kubectl -n demo2-shared exec deploy/shared-writer -- tail -f /data/shared.log
   ```

---

## What is happening under the hood

```text
Your laptop (host)
└── host-volume-data/
    ├── demo1/          ← Demo 1 PV (ReadWriteOnce)
    └── demo2/          ← Demo 2 PV (ReadWriteMany)

kind node (Docker container)
└── /mnt/host-volume/   ← bind-mount of this project folder

Pod
└── /data/              ← PVC mounted here
```

| Resource | Demo 1 | Demo 2 |
|----------|--------|--------|
| Namespace | `demo1-persistence` | `demo2-shared` |
| Deployment | `data-writer` (1 replica) | `shared-writer` (3 replicas) |
| PVC | `demo1-claim` | `demo2-shared-claim` |
| Access mode | ReadWriteOnce | ReadWriteMany |
| Data file | `/data/events.log` | `/data/shared.log` |

---

## Cleanup

Remove the kind cluster:

```bash
kind delete cluster --name stateful-vol
```

Remove local data (optional):

```bash
rm -rf host-volume-data/demo1 host-volume-data/demo2
```

Redeploy anytime:

```bash
bash deploy.sh
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `hostPath` not found / pod stuck Pending | Check `kind-config-vol.yaml` uses the correct **absolute** path on your machine |
| Old log lines from a previous session | Run `rm -rf host-volume-data/demo1 host-volume-data/demo2` then `bash deploy.sh` |
| PVC stays Pending | Ensure PV and PVC `storageClassName` match (`local-host`) and access modes align |
| Demo 2 shows only one pod name | Wait 10–15 seconds; all three pods write every 5 seconds |
| Wrong kubectl context | `kubectl config use-context kind-stateful-vol` |

---

## Quick reference

```bash
# Full setup from scratch
cd Kubernetes-world/stateful-workload-k8s
rm -rf host-volume-data/demo1 host-volume-data/demo2
bash deploy.sh

# Demo 1
kubectl -n demo1-persistence exec deploy/data-writer -- tail -f /data/events.log
kubectl -n demo1-persistence delete pod -l app=data-writer
kubectl -n demo1-persistence exec deploy/data-writer -- cat /data/events.log

# Demo 2
kubectl -n demo2-shared get pods -l app=shared-writer
kubectl -n demo2-shared exec deploy/shared-writer -- tail -f /data/shared.log
```

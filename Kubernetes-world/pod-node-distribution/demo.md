# Pod Node Distribution — Hands-on Exercise

Follow this guide **top to bottom**. Each section has numbered steps, commands to copy-paste, and what you should see.

**Time:** ~30 minutes  
**Cluster:** 1 kind cluster, 4 deployments, 6 pods total

---

## What you will learn

| Exercise | Concept | Deployment |
|----------|---------|------------|
| 1 | Taints & tolerations — reserve a node | `toleration-demo` |
| 2 | Node affinity — attract pods to a node | `affinity-demo` |
| 3 | Pod anti-affinity — keep replicas apart | `anti-affinity-demo` |
| 4 | Topology spread — balance pods across nodes | `spread-demo` |

---

## Before you start

**Prerequisites:** Docker, kind, kubectl

```bash
docker info >/dev/null && echo "docker: ok"
kind version
kubectl version --client
```

**Go to the lab directory:**

```bash
cd Kubernetes-world/pod-node-distribution
```

---

## Exercise 0: Deploy the lab

### Step 0.1 — Create the cluster and deploy all workloads

```bash
bash deploy.sh
```

This creates a kind cluster named `pod-scheduling` with 3 worker nodes, labels them, taints one node, and deploys 4 deployments.

### Step 0.2 — Check that all pods are running

```bash
kubectl get pods -n scheduling-demo -o wide
```

**You should see 6 pods, all `Running`:**

| Pod | Expected node | Why |
|-----|---------------|-----|
| `toleration-demo` | `pod-scheduling-worker3` | Only pod with toleration for tainted node |
| `affinity-demo` | `pod-scheduling-worker` | Requires `node-role=frontend` label |
| `anti-affinity-demo` (×2) | `worker` + `worker2` | One replica per node |
| `spread-demo` (×2) | `worker` + `worker2` | Spread evenly across nodes |

### Step 0.3 — See how nodes are set up

```bash
kubectl get nodes -L node-role,demo-zone
```

**You should see:**

```
NAME                           NODE-ROLE   DEMO-ZONE
pod-scheduling-worker          frontend    zone-a
pod-scheduling-worker2         backend     zone-b
pod-scheduling-worker3         special     zone-c      ← tainted
```

Check the taint on worker3:

```bash
kubectl describe node pod-scheduling-worker3 | grep Taints
```

**Expected:** `special=true:NoSchedule`

---

## Exercise 1: Taints & Tolerations

**Goal:** Understand how a node can repel pods, and how a toleration lets specific pods in.

**Idea:** worker3 is reserved. Normal pods stay away. Only `toleration-demo` has a "pass" to schedule there.

### Step 1.1 — Confirm toleration-demo is on the tainted node

```bash
kubectl get pods -n scheduling-demo -l app=toleration-demo -o wide
```

**Expected:** `NODE` column shows `pod-scheduling-worker3`

### Step 1.2 — Confirm no other demo pod is on worker3

```bash
kubectl get pods -n scheduling-demo -o wide | grep worker3
```

**Expected:** Only the `toleration-demo` pod appears. All other pods avoid worker3.

### Step 1.3 — Look at the toleration in the deployment

```bash
kubectl get deployment toleration-demo -n scheduling-demo -o yaml | grep -A8 tolerations
```

**Expected:**

```yaml
tolerations:
- effect: NoSchedule
  key: special
  operator: Equal
  value: "true"
```

### Step 1.4 — See what happens without a toleration

Try to run a one-off pod on worker3 using a nodeSelector (no toleration):

```bash
kubectl run test-no-toleration -n scheduling-demo --image=nginx:1.27-alpine \
  --overrides='{"spec":{"nodeSelector":{"node-role":"special"}}}' -- sleep 3600
```

Wait a few seconds, then check:

```bash
kubectl get pod test-no-toleration -n scheduling-demo -o wide
```

**Expected:** `STATUS` is `Pending` — the node is tainted and this pod has no toleration.

See why:

```bash
kubectl describe pod test-no-toleration -n scheduling-demo | tail -5
```

**Expected:** Message mentions `untolerated taint`

Clean up:

```bash
kubectl delete pod test-no-toleration -n scheduling-demo
```

**What you learned:** Taints push pods away. Tolerations are the exception that allows scheduling on tainted nodes.

---

## Exercise 2: Node Affinity

**Goal:** Force a pod to run only on nodes with a specific label.

**Idea:** `affinity-demo` must run on the node labeled `node-role=frontend` (worker).

### Step 2.1 — Confirm affinity-demo is on the frontend node

```bash
kubectl get pods -n scheduling-demo -l app=affinity-demo -o wide
```

**Expected:** Pod is on `pod-scheduling-worker`

### Step 2.2 — See the affinity rule on the pod

```bash
kubectl get pod -n scheduling-demo -l app=affinity-demo -o yaml | grep -A12 nodeAffinity
```

**Expected:** `requiredDuringSchedulingIgnoredDuringExecution` with `node-role In frontend`

### Step 2.3 — Break scheduling by removing the label

Delete the pod so it gets recreated, then remove the frontend label:

```bash
kubectl delete pod -n scheduling-demo -l app=affinity-demo
kubectl label node pod-scheduling-worker node-role-
```

Check the new pod:

```bash
kubectl get pods -n scheduling-demo -l app=affinity-demo -o wide
```

**Expected:** `STATUS` is `Pending`

See why:

```bash
kubectl describe pod -n scheduling-demo -l app=affinity-demo | grep -A3 "FailedScheduling\|Events:" | tail -6
```

**Expected:** Scheduler says no nodes match the node affinity rule.

### Step 2.4 — Fix it by restoring the label

```bash
kubectl label node pod-scheduling-worker node-role=frontend
```

Wait a few seconds, then check:

```bash
kubectl get pods -n scheduling-demo -l app=affinity-demo -o wide
```

**Expected:** Pod moves to `Running` on `pod-scheduling-worker`

**What you learned:** Node affinity pulls pods toward matching nodes. With `requiredDuringScheduling`, the pod stays Pending if no node matches.

---

## Exercise 3: Pod Anti-Affinity

**Goal:** Keep replicas of the same app on different nodes.

**Idea:** Two `anti-affinity-demo` replicas must not share a node.

### Step 3.1 — Confirm replicas are on different nodes

```bash
kubectl get pods -n scheduling-demo -l app=anti-affinity-demo \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

**Expected:** Two pods, two different nodes (worker and worker2)

### Step 3.2 — See the anti-affinity rule

```bash
kubectl get deployment anti-affinity-demo -n scheduling-demo -o yaml | grep -A8 podAntiAffinity
```

**Expected:** `topologyKey: kubernetes.io/hostname` — means "not on the same node"

### Step 3.3 — Try to add a third replica (should fail)

Block one node so only one eligible node remains:

```bash
kubectl cordon pod-scheduling-worker2
kubectl scale deployment anti-affinity-demo -n scheduling-demo --replicas=3
```

Check pods:

```bash
kubectl get pods -n scheduling-demo -l app=anti-affinity-demo -o wide
```

**Expected:** 2 `Running`, 1 `Pending` — the third pod cannot sit on the same node as an existing replica

See why:

```bash
kubectl get pods -n scheduling-demo -l app=anti-affinity-demo --field-selector=status.phase=Pending \
  -o name | xargs -I{} kubectl describe {} -n scheduling-demo | tail -5
```

### Step 3.4 — Restore

```bash
kubectl scale deployment anti-affinity-demo -n scheduling-demo --replicas=2
kubectl uncordon pod-scheduling-worker2
kubectl get pods -n scheduling-demo -l app=anti-affinity-demo -o wide
```

**Expected:** Both pods `Running` on different nodes again

**What you learned:** Pod anti-affinity prevents replicas from co-locating on the same node (hostname).

---

## Exercise 4: Topology Spread Constraints

**Goal:** Spread pods evenly across nodes.

**Idea:** `spread-demo` keeps pod count balanced across worker nodes with `maxSkew: 1`.

### Step 4.1 — Confirm even distribution

```bash
kubectl get pods -n scheduling-demo -l app=spread-demo -o wide
```

Count pods per node:

```bash
kubectl get pods -n scheduling-demo -l app=spread-demo \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

**Expected:** One pod on worker, one pod on worker2 (counts of 1 each)

### Step 4.2 — See the spread constraint

```bash
kubectl get deployment spread-demo -n scheduling-demo -o yaml | grep -A8 topologySpreadConstraints
```

**Expected:** `maxSkew: 1`, `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: DoNotSchedule`

### Step 4.3 — Delete a pod and watch it respread

```bash
kubectl delete pod -n scheduling-demo -l app=spread-demo --field-selector=status.phase=Running
```

Watch replacement (Ctrl+C to stop):

```bash
kubectl get pods -n scheduling-demo -l app=spread-demo -o wide -w
```

**Expected:** New pod comes up on the node that had fewer spread-demo pods

### Step 4.4 — Try 3 replicas (should leave one Pending)

Only 2 nodes accept these pods (worker3 is tainted). With `maxSkew: 1`, 3 pods cannot fit evenly:

```bash
kubectl scale deployment spread-demo -n scheduling-demo --replicas=3
kubectl get pods -n scheduling-demo -l app=spread-demo -o wide
```

**Expected:** 2 `Running`, 1 `Pending`

Restore:

```bash
kubectl scale deployment spread-demo -n scheduling-demo --replicas=2
```

**What you learned:** Topology spread constraints balance pod count across nodes. `DoNotSchedule` leaves pods Pending when the constraint cannot be met.

---

## Exercise 5: Compare all four concepts

Run this single command to see the full picture:

```bash
kubectl get pods -n scheduling-demo -o custom-columns=\
POD:.metadata.name,DEMO:.metadata.labels.demo,NODE:.spec.nodeName,STATUS:.status.phase
```

**Expected output pattern:**

```
POD                                   DEMO               NODE                     STATUS
toleration-demo-...                   taint-toleration   pod-scheduling-worker3   Running
affinity-demo-...                     node-affinity      pod-scheduling-worker    Running
anti-affinity-demo-...                pod-anti-affinity  pod-scheduling-worker    Running
anti-affinity-demo-...                pod-anti-affinity  pod-scheduling-worker2   Running
spread-demo-...                       topology-spread    pod-scheduling-worker    Running
spread-demo-...                       topology-spread    pod-scheduling-worker2   Running
```

**Quick comparison:**

| Concept | Who sets it | Effect |
|---------|-------------|--------|
| Taint + toleration | Node taint + pod toleration | Node pushes pods away unless tolerated |
| Node affinity | Pod spec | Pod pulls toward matching nodes |
| Pod anti-affinity | Pod spec | Pod pushes away from other pods |
| Topology spread | Pod spec | Scheduler balances pod count across nodes |

---

## Reset & cleanup

**Redeploy from scratch** (fixes anything broken during exercises):

```bash
bash deploy.sh
```

**Delete the cluster entirely:**

```bash
kind delete cluster --name pod-scheduling
```

---

## File reference

```
pod-node-distribution/
├── demo.md                      ← this exercise guide
├── deploy.sh                    ← run this first
├── setup-nodes.sh               ← labels + taints (called by deploy.sh)
├── kind-config.yaml             ← 1 control-plane + 3 workers
└── k8s/
    ├── namespace.yaml
    ├── 01-toleration-demo.yaml
    ├── 02-affinity-demo.yaml
    ├── 03-anti-affinity-demo.yaml
    └── 04-spread-demo.yaml
```

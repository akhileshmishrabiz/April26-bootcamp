# Observability & Service Mesh Stack — Hands-On Exercises

Hands-on lab guide for the **Kind + Cilium + Hubble + Monitoring + E-Commerce + NetworkPolicies + Linkerd** demo stack under `microservices/observibility/`.

All commands assume you start from the observability directory unless noted otherwise:

```bash
cd microservices/observibility
```

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick Reference — URLs & Credentials](#2-quick-reference--urls--credentials)
3. [Exercise 1 — Deploy the Full Stack (Kind + Cilium + Monitoring + App)](#3-exercise-1--deploy-the-full-stack-kind--cilium--monitoring--app)
4. [Exercise 2 — Explore the Monitoring Stack](#4-exercise-2--explore-the-monitoring-stack)
5. [Exercise 3 — E-Commerce App & Seed Data](#5-exercise-3--e-commerce-app--seed-data)
6. [Exercise 4 — Generate Traffic for Dashboards](#6-exercise-4--generate-traffic-for-dashboards)
7. [Exercise 5 — Network Policies (Cilium Enforcement + Hubble Drops)](#7-exercise-5--network-policies-cilium-enforcement--hubble-drops)
8. [Exercise 6 — Linkerd Service Mesh + Viz](#8-exercise-6--linkerd-service-mesh--viz) · [**Dedicated lab →**](exercise-service-mesh.md)
9. [Exercise 7 — k6 Load Testing](#9-exercise-7--k6-load-testing)
10. [Exercise 8 — Chaos Testing Under Load](#10-exercise-8--chaos-testing-under-load)
11. [Cleanup](#11-cleanup)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

| Tool | Purpose | Install (macOS) |
|------|---------|-----------------|
| Docker | Kind nodes, image loading | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Kind | Local Kubernetes cluster | `brew install kind` |
| kubectl | Cluster management | `brew install kubectl` |
| Helm | Chart deployment | `brew install helm` |
| curl | Health checks, API calls | pre-installed |
| python3 | Traffic script JSON parsing | pre-installed |
| k6 | Load testing (Exercise 7+) | `brew install k6` |
| hubble CLI | Observe dropped flows (optional) | `brew install hubble` |
| linkerd CLI | Mesh diagnostics (optional) | `brew install linkerd` |

**Verify:**

```bash
docker info
kind version
kubectl version --client
helm version
```

**Expected:** Docker daemon running; all tools report a version without error.

---

## 2. Quick Reference — URLs & Credentials

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://localhost:3030 | `admin` / `admin` |
| **Prometheus** | http://localhost:9090 | — |
| **Loki** | http://localhost:3100 | Query via Grafana |
| **Frontend** | http://localhost:4000 | — |
| **API Gateway** | http://localhost:9080 | — |
| **Vault UI** | http://localhost:18200 | Token: `root` |
| **RabbitMQ UI** | http://localhost:16672 | `rabbitmq` / `rabbitmq_secure_password_789` |
| **Mailpit UI** | http://localhost:8025 | — |
| **Hubble UI** | http://localhost:12000 | — |
| **Linkerd Viz** | http://localhost:8084 | — |

**Seeded test user (traffic scripts & manual login):**

```
Email:    john.doe@example.com
Password: Password123!
```

Additional seeded users (same password): `jane.smith@example.com`, `bob.johnson@example.com`, `alice.williams@example.com`, `charlie.brown@example.com`.

**Grafana dashboards** (folder: **E-Commerce**):

| Dashboard | What it shows |
|-----------|---------------|
| Microservices Overview | HTTP metrics, latency, KPIs |
| Latency & Errors | p50/p95/p99, 4xx/5xx, error logs |
| Tracing & Correlated Logs | Tempo traces linked to Loki logs |
| Microservices Logs Explorer | Loki search & log volume |
| Infrastructure | Redis & RabbitMQ metrics |
| Linkerd Golden Metrics | Mesh success rate, RPS, latency (after Linkerd deploy) |

---

## 3. Exercise 1 — Deploy the Full Stack (Kind + Cilium + Monitoring + App)

Deploy everything with a single script: Kind cluster, **Cilium CNI + Hubble**, observability stack, and e-commerce microservices.

### Steps

**1.1** Run the main deploy script:

```bash
cd microservices/observibility
./deploy.sh
```

**What it does (high level):**

| Step | Action |
|------|--------|
| 0 | Check docker, kind, kubectl, helm |
| 1 | Create/reuse Kind cluster `ecommerce-vault` (`kind-config.yaml`) |
| 1b | Install **Cilium 1.16.5 + Hubble** via `install-cilium.sh --with-cluster` |
| 2–3 | Pull & load monitoring images into Kind |
| 4 | Sync Grafana dashboards into Helm chart |
| 5 | Deploy Prometheus, Grafana, Loki, Promtail, Tempo, OTel Collector |
| 6 | Deploy e-commerce app via `helm-cnpg-vault-deploy.sh` (includes seed job) |
| 7 | Print access URLs and run health checks |

**1.2** Verify Cilium is the active CNI (required for NetworkPolicy enforcement):

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n kube-system -l k8s-app=hubble-relay
kubectl get pods -n kube-system -l k8s-app=hubble-ui
kubectl get nodes
```

**Expected:**

- `cilium-*` pods **Running**
- `hubble-relay-*` and `hubble-ui-*` pods **Running**
- All nodes **Ready**

**1.3** Verify monitoring and app pods:

```bash
kubectl get pods -n monitoring
kubectl get pods -n ecommerce
```

**Expected:** `prometheus`, `grafana`, `loki`, `promtail`, `tempo`, `otel-collector` all running; e-commerce deployments (api-gateway, product-service, etc.) running.

**1.4** Health-check endpoints:

```bash
curl -sf http://localhost:9090/-/healthy && echo " Prometheus OK"
curl -sf http://localhost:3030/api/health && echo " Grafana OK"
curl -sf http://localhost:9080/health && echo " API Gateway OK"
```

**Expected:** Each command prints an OK message; API gateway returns a body containing `OK`.

### Variants

```bash
# Monitoring only (skip e-commerce app)
./deploy.sh --monitoring-only

# Same as above
./deploy.sh --skip-app
```

### Why Cilium (not kindnet)?

Kind's default CNI (**kindnet**) accepts NetworkPolicy objects but **does not enforce** them. This stack uses **Cilium** (eBPF) for:

- **NetworkPolicy enforcement** — drops are real, not cosmetic
- **Hubble** — live flow visibility and `DROPPED` verdict filtering

The Kind config explicitly disables the default CNI so Cilium can be installed first:

```yaml
# kind-config.yaml
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
```

### Recreate cluster with Cilium (if CNI is wrong)

If the cluster is still on **kindnet** (policies won't enforce), recreate:

```bash
kind delete cluster --name ecommerce-vault
cd microservices/observibility
./deploy.sh
```

Or install Cilium manually on a fresh cluster:

```bash
kind delete cluster --name ecommerce-vault
kind create cluster --config kind-config.yaml --name ecommerce-vault
./servicemesh-networkingpolicies/cni/install-cilium.sh --with-cluster
# Then continue with monitoring + app deploy, or re-run ./deploy.sh
```

---

## 4. Exercise 2 — Explore the Monitoring Stack

### Steps

**2.1** Open Grafana and log in:

```
http://localhost:3030
User: admin
Pass: admin
```

**2.2** Confirm datasources (Configuration → Data sources):

| Datasource | Backend |
|------------|---------|
| Prometheus | `http://prometheus:9090` |
| Loki | `http://loki:3100` |
| Tempo | `http://tempo:3200` |

**Expected:** All three datasources green/healthy.

**2.3** Open Prometheus targets:

```
http://localhost:9090/targets
```

**Expected:** Scrape targets for e-commerce services and monitoring components show **UP** (after app deploy).

**2.4** Inspect the OTel pipeline:

```bash
kubectl get pods -n monitoring -l app=otel-collector
kubectl logs -n monitoring deploy/otel-collector --tail=20
```

**Expected:** OTel collector running; logs show trace/metric export activity once traffic flows.

**2.5** Confirm Promtail is collecting logs from app namespaces:

```bash
kubectl get daemonset promtail -n monitoring
kubectl logs -n monitoring -l app=promtail --tail=10 | head
```

**Expected:** Promtail DaemonSet ready; log lines from `ecommerce` namespace appear after traffic.

---

## 5. Exercise 3 — E-Commerce App & Seed Data

The deploy script runs the seed job automatically (Step 14 of `helm-cnpg-vault-deploy.sh`). This exercise verifies seed data and explores manual re-seeding.

### Steps

**3.1** Confirm seed job completed:

```bash
kubectl get jobs -n ecommerce
kubectl logs job/seed-data-job -n ecommerce
```

**Expected:** Job status **Complete**; logs show users/products created.

**3.2** Test login via API:

```bash
curl -s -X POST http://localhost:9080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john.doe@example.com","password":"Password123!"}' | python3 -m json.tool
```

**Expected:** JSON response with a `token` field.

**3.3** Browse products:

```bash
curl -s "http://localhost:9080/api/products?limit=5" | python3 -m json.tool
```

**Expected:** List of seeded products (25 total across categories).

**3.4** Open the frontend:

```
http://localhost:4000
```

Log in with `john.doe@example.com` / `Password123!`.

**Expected:** Product catalog loads; cart may already contain demo items (seed job adds first two products to John's cart).

### Manual re-seed (optional)

If seed data is missing or you need a clean re-seed:

```bash
# From microservices/app/seed-job/
docker build -t ms-ecom-seed:latest .
kind load docker-image ms-ecom-seed:latest --name ecommerce-vault

# Allow seed job egress when NetworkPolicies are active
kubectl apply -f ../../observibility/servicemesh-networkingpolicies/network-policies/allow-seed-job.yaml

kubectl delete job seed-data-job -n ecommerce --ignore-not-found
kubectl apply -f seed-job.yaml
kubectl wait --for=condition=complete job/seed-data-job -n ecommerce --timeout=300s
kubectl logs job/seed-data-job -n ecommerce
```

**Expected:** Job completes; login test in step 3.2 succeeds.

---

## 6. Exercise 4 — Generate Traffic for Dashboards

Populate metrics, logs, and traces before exploring Grafana dashboards.

### Steps

**6.1** Single checkout flow (quick smoke):

```bash
./simulate-traffic.sh --once
```

**Expected:** Output includes `Checkout flow completed`. If login fails, seed data is missing — see Exercise 3.

**6.2** Sustained traffic (5 minutes, ~2 req/s):

```bash
./simulate-traffic.sh --duration 300 --rate 3
```

**6.2b** High-throughput gateway load (~100 req/s aggregate, 60s default):

```bash
./simulate-100rps.sh
./simulate-100rps.sh --duration 120 --rate 100
```

Uses k6 when available (`load-test/scenario-100rps.js`); falls back to a parallel curl loop. Unlike `load-test/run-load-test.sh --rps100` (100 req/s **per** microservice), this drives ~100 req/s **combined** through the API gateway so traffic fans out across all services.

**6.3** While traffic runs, open Grafana dashboards (folder **E-Commerce**):

| Dashboard | What to look for |
|-----------|------------------|
| Microservices Overview | Request rate, status codes rising |
| Latency & Errors | p95 latency, 4xx from bad logins |
| Tracing & Correlated Logs | Trace spans; click through to Loki logs |
| Microservices Logs Explorer | Log lines from `ecommerce` pods |
| Infrastructure | Redis ops, RabbitMQ queue depth |

**Expected:** Panels populate within 1–2 minutes of traffic start.

**6.4** Verify traces in Tempo (via Grafana):

1. Open **Tracing & Correlated Logs**
2. Select a recent trace
3. Confirm spans across `product-service`, `user-service`, `cart-service`, etc.

---

## 7. Exercise 5 — Network Policies (Cilium Enforcement + Hubble Drops)

This exercise demonstrates **zero-trust network segmentation** enforced by **Cilium**. Hubble shows flows that are **DROPPED** by policy.

> **Important:** NetworkPolicy enforcement on Kind requires **Cilium**. Kind's default **kindnet** CNI accepts policies but never drops traffic. Always verify Cilium is running before this exercise.

### Policy overview

Policies live in `servicemesh-networkingpolicies/network-policies/`:

| Manifest | Purpose |
|----------|---------|
| `default-deny.yaml` | Deny all ingress/egress (baseline) |
| `allow-dns.yaml` | DNS resolution (kube-system) |
| `allow-api-gateway.yaml` | North-south ingress to gateway |
| `allow-microservices.yaml` | East-west HTTP between services |
| `allow-redis-rabbitmq.yaml` | Datastore access restrictions |
| `servicetodb.yaml` | Postgres egress (CNPG clusters, port 5432) |
| `allow-cnpg-apiserver-cilium.yaml` | **CiliumNetworkPolicy** — CNPG → kube-apiserver |
| `allow-monitoring-scrape.yaml` | Prometheus scrape from monitoring ns |
| `allow-linkerd-vault.yaml` | Linkerd control plane + Vault egress |
| `allow-linkerd-viz-scrape.yaml` | Linkerd Viz metrics scrape |
| `allow-seed-job.yaml` | Seed job → API gateway egress |

### Steps

**7.1** Confirm Cilium is enforcing (prerequisite):

```bash
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl exec -n kube-system ds/cilium -- cilium status --brief
```

**Expected:** Cilium agent healthy; `KubeProxyReplacement: false` (Kind uses kube-proxy).

**7.2** Dry-run validate policies (no changes applied):

```bash
./servicemesh-networkingpolicies/network-policies/deploy-np.sh
```

**Expected:** All manifests pass client dry-run; script lists 11 YAML files and prints apply instructions.

**7.3** Check current policy state:

```bash
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --status
```

**Expected:** Lists NetworkPolicies in `ecommerce` (empty before first apply).

**7.4** Apply NetworkPolicies:

```bash
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --apply
```

**Expected:** Policies applied; `kubectl get networkpolicy -n ecommerce` shows all policies with label `app.kubernetes.io/part-of=ecommerce-network-policy`.

**7.5** Verify app still works through allowed paths:

```bash
curl -sf http://localhost:9080/health && echo " Gateway OK"
curl -sf http://localhost:4000 >/dev/null && echo " Frontend OK"
./simulate-traffic.sh --once
```

**Expected:** Health checks pass; traffic script completes checkout.

**7.6** Observe **DROPPED** traffic with Hubble CLI:

```bash
# Install CLI if needed: brew install hubble
hubble status
hubble observe --verdict DROPPED -n ecommerce -f
```

In a second terminal, generate traffic:

```bash
./simulate-traffic.sh --once
```

**Expected:** Hubble CLI shows dropped flows (DNS denials, unauthorized egress attempts, etc.) with `verdict=DROPPED`. Allowed gateway→service traffic shows `FORWARDED`.

**7.7** Observe drops in **Hubble UI**:

```
http://localhost:12000
```

If the UI is unreachable:

```bash
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```

**Expected:** Flow map with red/dropped flows when policies block traffic. Filter by namespace `ecommerce` and verdict **DROPPED**.

**7.8** Demonstrate an intentional block — unauthorized pod:

```bash
kubectl run np-test --rm -it --restart=Never -n ecommerce \
  --image=curlimages/curl -- \
  curl -m 5 http://product-service:8001/health
```

Watch Hubble in the first terminal.

**Expected:** Connection times out or fails; Hubble shows `DROPPED` flow from `np-test` → `product-service` (no allow rule for arbitrary pods).

**7.9** Remove policies (restore open networking):

```bash
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --delete
```

**Expected:** All policies removed; `deploy-np.sh --status` shows none.

**Temporarily disable (skip re-apply on next deploy):**

```bash
export DISABLE_NP=1   # deploy-np.sh --apply and deploy.sh honor this
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --delete
```

Re-enable later: `unset DISABLE_NP` then `./servicemesh-networkingpolicies/network-policies/deploy-np.sh --apply`.

### Alternative: apply via mesh deploy script (includes Cilium check)

The service mesh deploy script verifies Cilium before applying policies:

```bash
./servicemesh-networkingpolicies/deploy.sh --policies-only
```

If Cilium is missing, it aborts with instructions to run `install-cilium.sh --with-cluster` or recreate via `./deploy.sh`.

### Cilium-specific policy note

`allow-cnpg-apiserver-cilium.yaml` is a **CiliumNetworkPolicy** (not standard NetworkPolicy) because Kubernetes `ipBlock` cannot express kube-apiserver/host entity access on Kind. This is why Cilium is required — not just for enforcement but for CNPG operator connectivity.

---

## 8. Exercise 6 — Linkerd Service Mesh + Viz

> **Hands-on deep dive:** For a step-by-step service mesh deployment lab (CLI install, CNI plugin, control plane, injection, Server/AuthorizationPolicy, ServiceProfiles, troubleshooting), see **[exercise-service-mesh.md](exercise-service-mesh.md)**.

Install Linkerd mTLS, service map, tap, and golden metrics on the existing cluster.

### Prerequisites

- Exercise 1 complete (app running)
- Exercise 5 recommended (NetworkPolicies applied) — mesh and policies are installed separately

### Steps

**8.1** Install Linkerd mesh + Viz (primary):

```bash
./servicemesh-networkingpolicies/install-linkerd.sh
```

**What it installs:**

| Component | Purpose |
|-----------|---------|
| Linkerd CRDs + control plane | mTLS, proxy injection |
| Linkerd CNI plugin | Chains on Cilium (`cniEnabled: true`, `privileged=true`) |
| Linkerd Viz | Dashboard, tap, metrics-api |
| Mesh policies | Server CRs, MeshTLSAuthentication, strict AuthorizationPolicy |
| Prometheus scrape | Enables `linkerdViz.enabled=true` on observability Helm release |

NetworkPolicies are **not** applied by this script — use Exercise 5 (`deploy-np.sh --apply`) or `./servicemesh-networkingpolicies/deploy.sh --policies-only`.

**8.2** Verify meshed pods (2/2 or 3/3 containers — app + linkerd-proxy):

```bash
kubectl get pods -n ecommerce
```

**Expected:** Each app pod shows `2/2 Running` (or more with init containers).

**8.3** Open Linkerd Viz dashboard:

```
http://localhost:8084
```

Fallback port-forward:

```bash
kubectl -n linkerd-viz port-forward svc/web 8084:8084
```

**Expected:** Service topology map showing deployments and live traffic edges.

**8.4** Generate traffic and explore Viz features:

```bash
./simulate-traffic.sh --duration 120 --rate 2
```

In Linkerd Viz:

| Feature | How to use |
|---------|------------|
| **Service map** | Topology view — edges show RPS between services |
| **Golden metrics** | Click a deployment → success rate, latency, RPS |
| **Tap** | Live gRPC/HTTP stream for a selected resource |

**8.5** Linkerd CLI stats (optional):

```bash
linkerd check
linkerd viz stat deploy -n ecommerce
linkerd viz tap deploy/product-service -n ecommerce
```

**8.6** Grafana Linkerd Golden Metrics:

```
http://localhost:3030 → E-Commerce → Linkerd Golden Metrics
```

**Expected:** Per-service success rate, request rate, and latency panels populate (Prometheus scrapes linkerd-viz metrics-api after mesh deploy).

### ServiceAccounts and mesh identity

Each ecommerce workload runs under its own **Kubernetes ServiceAccount** (created by the Helm chart in `ecommerce/templates/serviceaccounts.yaml`). Linkerd assigns each meshed pod a TLS identity derived from its ServiceAccount. **AuthorizationPolicy** resources in `servicemesh-networkingpolicies/mesh/server-authorization/` tie inbound access to those identities — each policy references one **MeshTLSAuthentication** that lists the allowed caller ServiceAccounts (e.g. `product-service-callers` allows `api-gateway`, `cart-service`, `order-service`, …).

Inspect identities and policies:

```bash
kubectl get serviceaccount -n ecommerce
kubectl get authorizationpolicy,meshtlsauthentication,server -n ecommerce
linkerd viz stat deploy -n ecommerce
linkerd viz tap deploy/product-service -n ecommerce
linkerd check
```

See `servicemesh-networkingpolicies/mesh/README.md` for the full ServiceAccount → workload mapping table.

### Mesh-only options

```bash
# Primary — full mesh + Viz + workload restart
./servicemesh-networkingpolicies/install-linkerd.sh

# Skip Viz dashboard (control plane + mesh policies only)
./servicemesh-networkingpolicies/install-linkerd.sh --skip-viz

# Install mesh but defer proxy injection until manual restart
./servicemesh-networkingpolicies/install-linkerd.sh --skip-restart

# Combined mesh + NetworkPolicies (delegates mesh to install-linkerd.sh)
./servicemesh-networkingpolicies/deploy.sh

# Mesh only via deploy.sh wrapper (same as install-linkerd.sh)
./servicemesh-networkingpolicies/deploy.sh --mesh-only

# NetworkPolicies only (Cilium check) — see Exercise 5
./servicemesh-networkingpolicies/deploy.sh --policies-only
```

### Observe policy drops alongside mesh (Hubble)

With both Linkerd and Cilium policies active:

```bash
hubble observe --verdict DROPPED -n ecommerce -f
```

**Expected:** Cilium drops unrelated to Linkerd mTLS — they operate at different layers (L3/L4 policy vs L7 mTLS).

---

## 9. Exercise 7 — k6 Load Testing

Structured load tests targeting each microservice independently plus full checkout journeys.

### Prerequisites

```bash
brew install k6
curl -sf http://localhost:9080/health   # must succeed
```

### Steps

**9.1** Quick validation (20 req/s per service, 30s):

```bash
./load-test/run-load-test.sh --rps20
```

**Expected:** k6 completes; thresholds pass (relaxed for rps20).

**9.2** Default profile — 100 req/s per service, 5 min (~500+ total RPS):

```bash
./load-test/run-load-test.sh --rps100
```

**9.3** Watch dashboards during the run:

| URL | Focus |
|-----|-------|
| http://localhost:3030 | Latency & Errors, Golden Metrics |
| http://localhost:9090 | Raw Prometheus queries |
| http://localhost:8084 | Linkerd Viz (if mesh installed) |

**9.4** Progressive load suite:

```bash
./load-test/run-all-load-tests.sh
# smoke → rps50 → rps100 with 30s cooldown
```

**9.5** Extreme / soak variants:

```bash
./load-test/run-load-test.sh --rps200          # ~1000+ RPS — heavy for Kind
./load-test/run-load-test.sh --rps100-soak     # 100 req/s × 15 min
./load-test/run-all-load-tests.sh --extreme    # adds rps200
./load-test/run-all-load-tests.sh --include-soak
```

**9.6** Legacy VU-based profiles:

```bash
./load-test/run-load-test.sh --smoke     # 5 VUs × 1 min
./load-test/run-load-test.sh --load      # ramp to 50 VUs
./load-test/run-load-test.sh --stress    # ramp to 200 VUs
./load-test/run-load-test.sh --spike     # spike to 300 VUs
```

**Expected:** k6 prints per-scenario metrics; Grafana shows elevated RPS and latency. Payment endpoint may timeout (~5s) if Razorpay keys are not configured — this still generates payment-service load.

---

## 10. Exercise 8 — Chaos Testing Under Load

Combine pod kills with high RPS to observe resilience in Grafana and Linkerd Viz.

### Steps

**10.1** Kill a specific service once:

```bash
./load-test/chaos-kill.sh --target product-service
```

**Expected:** Pod deleted and recreated; brief 503/502 spikes in Grafana.

**10.2** Random chaos during load test:

```bash
# Terminal 1
./load-test/run-all-load-tests.sh --with-chaos
# Kills random microservice every 30s; CHAOS=1 relaxes k6 thresholds
```

**10.3** Maximum pain — high RPS + chaos:

```bash
./load-test/run-peak-chaos.sh           # rps100 → rps200 with random kills
./load-test/run-peak-chaos.sh --rps-only  # rps100 only
```

**10.4** Observe recovery:

| Signal | Where |
|--------|-------|
| Error rate spike | Grafana → Latency & Errors |
| Success rate dip | Linkerd Golden Metrics |
| Pod restart | `kubectl get pods -n ecommerce -w` |
| Dropped connections | Hubble → `DROPPED` during policy + chaos overlap |

**Expected:** Error rates spike during kills; services recover as Kubernetes recreates pods. Threshold failures under rps200 + chaos on a single-node Kind cluster are normal.

---

## 11. Cleanup

### Remove components individually

```bash
# NetworkPolicies
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --delete

# Linkerd
helm uninstall linkerd-viz -n linkerd-viz
helm uninstall linkerd-control-plane linkerd-cni linkerd-crds -n linkerd

# Observability
helm uninstall observability -n monitoring

# E-commerce + Vault + ESO
helm uninstall ecommerce-vault -n ecommerce
helm uninstall vault -n vault
helm uninstall external-secrets -n external-secrets

# Cilium
helm uninstall cilium -n kube-system
```

### Full teardown

```bash
kind delete cluster --name ecommerce-vault
```

---

## 12. Troubleshooting

### Nodes NotReady / pods stuck Pending

**Symptom:** Cluster created but no pod networking.

**Cause:** Cilium not installed (Kind disables default CNI).

**Fix:**

```bash
kubectl get pods -n kube-system | grep -E 'cilium|kindnet'
# If kindnet or no CNI:
kind delete cluster --name ecommerce-vault
cd microservices/observibility && ./deploy.sh
```

### NetworkPolicies have no effect

**Symptom:** Policies applied but all traffic still works (or Hubble shows no drops).

**Cause:** Cluster running **kindnet** — policies are accepted but not enforced.

**Verify:**

```bash
kubectl get pods -n kube-system -l app=kindnet
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Fix:** Recreate cluster with Cilium:

```bash
kind delete cluster --name ecommerce-vault
./deploy.sh
# Or manually:
./servicemesh-networkingpolicies/cni/install-cilium.sh --with-cluster
```

### Cilium install fails on existing cluster

**Symptom:** `install-cilium.sh` exits with "Cannot install Cilium on a cluster with an active CNI".

**Fix:** Must recreate — Cilium requires `disableDefaultCNI: true` at cluster creation:

```bash
kind delete cluster --name ecommerce-vault
./deploy.sh
```

### Login / seed data fails

**Symptom:** `simulate-traffic.sh` reports "Login failed — is seed data loaded?"

**Fix:**

```bash
kubectl get jobs -n ecommerce
kubectl logs job/seed-data-job -n ecommerce
# Re-run seed — see Exercise 3.4
```

### Seed job fails with NetworkPolicies active

**Symptom:** Seed job pod cannot reach API gateway.

**Fix:**

```bash
kubectl apply -f servicemesh-networkingpolicies/network-policies/allow-seed-job.yaml
kubectl delete job seed-data-job -n ecommerce --ignore-not-found
kubectl apply -f ../app/seed-job/seed-job.yaml
```

### Hubble CLI not connecting

```bash
hubble status
# If failing:
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
export HUBBLE_SERVER=localhost:4245
hubble observe --verdict DROPPED -n ecommerce -f
```

### Resume cluster after idle stop (`docker stop`)

**Symptom:** After `docker start ecommerce-vault-control-plane`, pods are up but API returns 504 or Linkerd logs show `invalid peer certificate: Expired`.

**Fix:**

```bash
docker start ecommerce-vault-control-plane
kubectl wait --for=condition=ready node --all --timeout=120s

# Refresh Linkerd control plane + meshed workloads
kubectl rollout restart deployment -n linkerd linkerd-identity linkerd-destination linkerd-proxy-injector
kubectl rollout restart deployment -n ecommerce --all

# Full mesh refresh if rollout restart is insufficient:
# ./servicemesh-networkingpolicies/install-linkerd.sh

# Re-apply strict mesh auth (required for east-west traffic)
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/authorization-policies.strict.yaml

# Linkerd Viz (if :8084 unreachable — cluster may predate kind-config port mapping)
kubectl -n linkerd-viz port-forward svc/web 8084:8084 &
```

**Verify:** `curl -sf http://localhost:9080/health`

### Linkerd Viz RPC error (`metrics-api` / closed network connection)

**Symptom:** Dashboard at the wrong URL (e.g. `http://localhost:4455/controlplane` from `linkerd dashboard`) or Viz at `:8084` shows:

```text
RPC error: connection to 10.96.x.x:8085 (metrics-api) — use of closed network connection
```

**Cause:** Two common issues on this lab cluster:

1. **Wrong dashboard** — Linkerd Viz is **not** the control-plane UI. Use `http://localhost:8084` (Kind maps NodePort `30884`), not `linkerd dashboard` / `:4455/controlplane`.
2. **NetworkPolicy blocks web → metrics-api** — `allow-linkerd-viz-scrape.yaml` selects `metrics-api` pods; once selected, only listed ingress is allowed. If `component: web` is missing, the Viz web pod cannot reach metrics-api on `:8085`.
3. **Stale proxy certs** — After control-plane upgrades, older Viz proxies may log `CertificateExpired` talking to `linkerd-destination`; restart Viz deployments.

**Fix:**

```bash
kubectl config use-context kind-ecommerce-vault

# Re-apply NetworkPolicy (allows web → metrics-api:8085 + Prometheus → :9995)
kubectl apply -f servicemesh-networkingpolicies/network-policies/allow-linkerd-viz-scrape.yaml

# Refresh Viz proxy certificates
kubectl rollout restart deployment -n linkerd-viz web metrics-api tap tap-injector prometheus
kubectl rollout status deployment -n linkerd-viz --timeout=180s

# Correct port-forward and URL
kubectl -n linkerd-viz port-forward svc/web 8084:8084
# Open http://localhost:8084
```

**Verify:** `curl -sf http://localhost:8084/api/version` and `curl -sf 'http://localhost:8084/api/tps-reports?resource_type=deployment&namespace=ecommerce'` return JSON (no RPC error in `kubectl logs -n linkerd-viz deploy/web -c web`).

### Linkerd injection failures after mesh install

```bash
kubectl describe pod -n ecommerce <pod-name>
# Look for proxy init errors

# CNPG/Redis/RabbitMQ probe failures — skip ports already configured:
kubectl get deploy -n ecommerce -o yaml | grep linkerd.io/skip
```

### Grafana panels empty

1. Confirm traffic: `./simulate-traffic.sh --once`
2. Check Prometheus targets: http://localhost:9090/targets
3. Check Promtail: `kubectl logs -n monitoring -l app=promtail --tail=50`
4. Allow 1–2 minutes for scrape intervals

### k6 threshold failures on Kind

Expected under `--rps200`, `--peak`, or `--with-chaos`. Use lighter profiles:

```bash
./load-test/run-load-test.sh --rps20
./load-test/run-load-test.sh --smoke
```

Set `CHAOS=1` for lenient thresholds during chaos runs.

### Port already in use

Kind maps fixed host ports (see `kind-config.yaml`). Check conflicts:

```bash
lsof -i :3030 -i :9090 -i :9080 -i :12000 -i :8084
```

### API gateway unreachable

```bash
kubectl get pods -n ecommerce -l app=api-gateway
kubectl logs -n ecommerce deploy/api-gateway --tail=50
kubectl get svc -n ecommerce
```

---

## Appendix — Script Reference

| Script / doc | Purpose |
|--------------|---------|
| `exercise-service-mesh.md` | **Dedicated Linkerd deployment lab** (step-by-step + troubleshooting) |
| `deploy.sh` | Full stack: Kind + Cilium + monitoring + app |
| `servicemesh-networkingpolicies/cni/install-cilium.sh` | Cilium + Hubble only |
| `servicemesh-networkingpolicies/install-linkerd.sh` | **Linkerd mesh + Viz + mesh policies** (`--skip-viz`, `--skip-restart`) |
| `servicemesh-networkingpolicies/network-policies/deploy-np.sh` | NetworkPolicies only (`--apply`, `--delete`, `--status`) |
| `servicemesh-networkingpolicies/deploy.sh` | Linkerd (via `install-linkerd.sh`) + NetworkPolicies |
| `simulate-traffic.sh` | Realistic e-commerce traffic generator |
| `simulate-100rps.sh` | ~100 req/s aggregate gateway load (k6 or curl fallback) |
| `load-test/run-load-test.sh` | k6 load test runner |
| `load-test/run-all-load-tests.sh` | Sequential profile runner |
| `load-test/run-peak-chaos.sh` | High RPS + random pod kills |
| `load-test/chaos-kill.sh` | Targeted pod chaos |

**Cluster name:** `ecommerce-vault`  
**App namespace:** `ecommerce`  
**Monitoring namespace:** `monitoring`  
**Cilium version:** 1.16.5  
**Linkerd version:** stable-2.14.10

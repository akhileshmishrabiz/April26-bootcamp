# Service Mesh Deployment — Linkerd Hands-On Lab

Deploy **Linkerd 2.14.10** on the existing **ecommerce-vault** Kind cluster with **Cilium CNI**, inject sidecar proxies into the e-commerce microservices, enable **Linkerd Viz**, and apply **Server / AuthorizationPolicy** identity-based auth plus **ServiceProfile** retry/timeout policies.

This lab lives under `microservices/observibility/`. All commands assume you start here unless noted:

```bash
cd microservices/observibility
```

**Related files:**

| Path | Purpose |
|------|---------|
| [`servicemesh-networkingpolicies/install-linkerd.sh`](servicemesh-networkingpolicies/install-linkerd.sh) | Automated mesh + Viz + policies install |
| [`servicemesh-networkingpolicies/deploy.sh`](servicemesh-networkingpolicies/deploy.sh) | Mesh + NetworkPolicies combined |
| [`servicemesh-networkingpolicies/mesh/`](servicemesh-networkingpolicies/mesh/) | Injection annotations, Server/Auth, ServiceProfiles |
| [`servicemesh-networkingpolicies/mesh/README.md`](servicemesh-networkingpolicies/mesh/README.md) | ServiceAccount → workload mapping |
| [`servicemesh-networkingpolicies/values.yaml`](servicemesh-networkingpolicies/values.yaml) | Control-plane Helm values (`cniEnabled: true`) |
| [`servicemesh-networkingpolicies/values-viz.yaml`](servicemesh-networkingpolicies/values-viz.yaml) | Viz Helm values |
| [`exercise.md`](exercise.md) | Full observability stack lab (Cilium, monitoring, NetworkPolicies) |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Learning Objectives](#2-learning-objectives)
3. [Architecture Overview](#3-architecture-overview)
4. [Exercise A — Fast Path (Automated Install)](#4-exercise-a--fast-path-automated-install)
5. [Exercise B — Step-by-Step Deployment (Learn Each Layer)](#5-exercise-b--step-by-step-deployment-learn-each-layer)
6. [Verify the Mesh](#6-verify-the-mesh)
7. [Explore Linkerd Viz](#7-explore-linkerd-viz)
8. [Service Identity & Authorization Policies](#8-service-identity--authorization-policies)
9. [Retry & Timeout Policies (ServiceProfiles)](#9-retry--timeout-policies-serviceprofiles)
10. [Optional — Load Simulation & Grafana Golden Metrics](#10-optional--load-simulation--grafana-golden-metrics)
11. [Optional — NetworkPolicies + Mesh Together](#11-optional--networkpolicies--mesh-together)
12. [Cleanup](#12-cleanup)
13. [Troubleshooting](#13-troubleshooting)
14. [Next Steps](#14-next-steps)

---

## 1. Prerequisites

### Cluster & app stack

Complete **Exercise 1** from [`exercise.md`](exercise.md) (or run `./deploy.sh`) so the following are running:

| Component | Verify |
|-----------|--------|
| Kind cluster `ecommerce-vault` | `kind get clusters` |
| **Cilium CNI + Hubble** (not kindnet) | `kubectl get pods -n kube-system -l k8s-app=cilium` |
| E-commerce app in `ecommerce` ns | `kubectl get deploy -n ecommerce` |
| Monitoring stack in `monitoring` ns | `kubectl get pods -n monitoring` |

```bash
kubectl config use-context kind-ecommerce-vault
curl -sf http://localhost:9080/health && echo " API Gateway OK"
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get pods -n ecommerce
```

**Expected:** Gateway returns OK; Cilium pods **Running**; ecommerce deployments **Running** (1/1 containers before mesh — no proxy yet).

> **Why Cilium?** This lab uses **Cilium** (eBPF) as the cluster CNI. Linkerd chains its CNI plugin on top of Cilium (`cniEnabled: true`). NetworkPolicy enforcement (optional Exercise 5) also requires Cilium — kindnet accepts policies but does not enforce them.

### Tools

| Tool | Purpose | Install (macOS) |
|------|---------|-----------------|
| linkerd CLI | Mesh diagnostics, tap, stat | `brew install linkerd` |
| kubectl, helm, docker | Already required by stack | — |

```bash
linkerd version --client
linkerd version --client --short   # should report stable-2.14.x
```

**Expected:** Client version reports without error. Server version appears after control plane install.

### Optional but recommended

- **NetworkPolicies applied** — see [Exercise 5 in exercise.md](exercise.md#7-exercise-5--network-policies-cilium-enforcement--hubble-drops). Mesh and policies install independently; together they demonstrate L3/L4 (Cilium) + L7/mTLS (Linkerd) defense in depth.
- **Seed data loaded** — login test in Exercise 3 of `exercise.md`.

---

## 2. Learning Objectives

After completing this lab you will be able to:

1. Install Linkerd **CRDs**, **CNI plugin**, and **control plane** on a Cilium-backed Kind cluster.
2. Enable **automatic proxy injection** and restart workloads so pods run **app + linkerd-proxy** sidecars.
3. Use **Linkerd Viz** for service topology, golden metrics, and live tap.
4. Apply **Server**, **MeshTLSAuthentication**, and **AuthorizationPolicy** for identity-based east-west access control.
5. Configure **ServiceProfile** retry budgets and 30s timeouts on outbound calls.
6. Diagnose common issues: cert expiry after cluster stop/start, proxy injection failures, Viz RPC/metrics-api errors.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Kind cluster: ecommerce-vault                                  │
│                                                                 │
│  Cilium CNI (L3/L4 NetworkPolicy)                               │
│       ↓ chains with                                             │
│  Linkerd CNI plugin (iptables redirect → proxy)                 │
│                                                                 │
│  ┌────────────── ecommerce namespace ──────────────────────┐   │
│  │  api-gateway ──mTLS──► product-service :8001            │   │
│  │       │                    ▲                             │   │
│  │       └──mTLS──► user-service :8002                     │   │
│  │  Each pod: [app container] + [linkerd-proxy sidecar]    │   │
│  │  Identity = Kubernetes ServiceAccount                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  linkerd namespace: identity, destination, proxy-injector     │
│  linkerd-viz namespace: web, metrics-api, tap                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key concepts:**

| Layer | Technology | What it enforces |
|-------|------------|------------------|
| CNI / L3-L4 | Cilium NetworkPolicy | IP/port allow lists, pod selectors |
| Data plane | Linkerd proxy (sidecar) | mTLS, golden metrics, retries |
| L7 policy | Server + AuthorizationPolicy | Caller ServiceAccount must match |
| Resilience | ServiceProfile | 30s timeout, retry on 502/503/504 |

CNPG Postgres, Redis `:6379`, and RabbitMQ have skip-injection/skip-port annotations — see [`mesh/cnpg-skip-injection.yaml`](servicemesh-networkingpolicies/mesh/cnpg-skip-injection.yaml) and [`mesh/redis-skip-ports.yaml`](servicemesh-networkingpolicies/mesh/redis-skip-ports.yaml).

---

## 4. Exercise A — Fast Path (Automated Install)

Use this when you want the full mesh in one command. The script performs every step in Exercise B automatically.

### Steps

**A.1** Install mesh + Viz + policies + workload restart:

```bash
./servicemesh-networkingpolicies/install-linkerd.sh
```

**What it installs:**

| Step | Component |
|------|-----------|
| 1 | Linkerd images loaded into Kind |
| 2 | ECDSA P-256 identity certs in `servicemesh-networkingpolicies/.certs/` |
| 3 | Linkerd CRDs |
| 4–5 | **Linkerd CNI** (`privileged=true`, chains on Cilium) |
| 6–7 | **Control plane** (`cniEnabled: true` via `values.yaml`) |
| 8 | **Linkerd Viz** (dashboard, tap, metrics-api) |
| 9 | Prometheus scrape of metrics-api (`linkerdViz.enabled=true`) |
| 10 | Mesh manifests (injection, Server, Auth, ServiceProfiles) |
| 11 | Rollout restart of ecommerce Deployments/StatefulSets |

**A.2** Skip options:

```bash
# Control plane + policies only (no Viz dashboard)
./servicemesh-networkingpolicies/install-linkerd.sh --skip-viz

# Install mesh but defer proxy injection until manual restart
./servicemesh-networkingpolicies/install-linkerd.sh --skip-restart
```

**Expected:** Script ends with `LINKERD SERVICE MESH READY`; pods in `ecommerce` show **2/2 Running**.

Continue at [Section 6 — Verify the Mesh](#6-verify-the-mesh).

---

## 5. Exercise B — Step-by-Step Deployment (Learn Each Layer)

Follow these steps to understand each install phase. Skip any step already done by Exercise A.

### B.1 — Install Linkerd CLI

```bash
brew install linkerd
linkerd version --client
```

Match the cluster version when possible:

```bash
export LINKERD_VERSION=stable-2.14.10
```

**Expected:** Client reports `stable-2.14.x`.

### B.2 — Pre-flight checks

```bash
kubectl config use-context kind-ecommerce-vault
kubectl get namespace ecommerce
kubectl get pods -n kube-system -l k8s-app=cilium
helm repo add linkerd https://helm.linkerd.io/stable
helm repo update linkerd
```

**Expected:** Context is `kind-ecommerce-vault`; Cilium Running; Helm repo updated.

### B.3 — Install Linkerd CRDs

```bash
helm install linkerd-crds linkerd/linkerd-crds \
  -n linkerd --create-namespace --timeout 5m

kubectl wait --for=condition=Established crd/servers.policy.linkerd.io --timeout=120s
kubectl wait --for=condition=Established crd/serverauthorizations.policy.linkerd.io --timeout=120s
```

**Expected:** CRDs established; no errors from `helm install`.

### B.4 — Install Linkerd CNI plugin (before control plane)

With **Cilium** as the cluster CNI, Linkerd must use its **CNI plugin** (`cniEnabled: true`) instead of init-container `NET_ADMIN` capabilities.

```bash
helm install linkerd-cni linkerd/linkerd2-cni \
  -n linkerd \
  --set privileged=true \
  --set destCNINetDir=/etc/cni/net.d \
  --set destCNIBinDir=/opt/cni/bin \
  --timeout 5m

kubectl rollout status daemonset/linkerd-cni -n linkerd --timeout=180s
```

**Expected:** `linkerd-cni` DaemonSet **Available** on all nodes.

> The install script loads images into Kind first — on a fresh manual install you may need to pull/load images or run from a network-connected host. Prefer `./install-linkerd.sh` if image loading is unfamiliar.

### B.5 — Generate identity certificates

Linkerd mTLS requires a trust anchor and issuer. The install script generates **ECDSA P-256** certs (required — RSA issuers break proxy CSR signing):

```bash
# Automated (recommended):
./servicemesh-networkingpolicies/install-linkerd.sh --skip-viz --skip-restart
# Certs land in servicemesh-networkingpolicies/.certs/
```

Or inspect existing certs:

```bash
ls servicemesh-networkingpolicies/.certs/
openssl x509 -in servicemesh-networkingpolicies/.certs/issuer.crt -noout -text | grep "Public Key Algorithm"
```

**Expected:** Files `ca.crt`, `issuer.crt`, `issuer.key`; algorithm is `id-ecPublicKey`.

### B.6 — Install control plane

```bash
CERT_DIR=servicemesh-networkingpolicies/.certs

helm install linkerd-control-plane linkerd/linkerd-control-plane \
  -n linkerd \
  -f servicemesh-networkingpolicies/values.yaml \
  --set-file identityTrustAnchorsPEM="${CERT_DIR}/ca.crt" \
  --set-file identity.issuer.tls.crtPEM="${CERT_DIR}/issuer.crt" \
  --set-file identity.issuer.tls.keyPEM="${CERT_DIR}/issuer.key" \
  --timeout 5m

kubectl wait --for=condition=available deployment/linkerd-identity -n linkerd --timeout=180s
kubectl wait --for=condition=available deployment/linkerd-destination -n linkerd --timeout=180s
kubectl wait --for=condition=available deployment/linkerd-proxy-injector -n linkerd --timeout=180s
```

**Expected:** Three control-plane deployments **Available**.

Key value in [`values.yaml`](servicemesh-networkingpolicies/values.yaml):

```yaml
cniEnabled: true   # required with Cilium — no NET_ADMIN init container
```

### B.7 — Enable proxy injection on the namespace

```bash
kubectl apply -f servicemesh-networkingpolicies/mesh/namespace-annotation.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/cnpg-skip-injection.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/redis-skip-ports.yaml
```

**Expected:**

```bash
kubectl get namespace ecommerce -o jsonpath='{.metadata.annotations.linkerd\.io/inject}'
# prints: enabled
```

Existing pods are **not** meshed until restarted — injection applies on pod creation.

### B.8 — Restart workloads for sidecar injection

```bash
kubectl rollout restart deployment -n ecommerce --all
kubectl rollout restart statefulset -n ecommerce --all
kubectl rollout status deployment -n ecommerce --timeout=600s
```

**Expected:** Pods transition to **2/2 Running** (app + `linkerd-proxy`):

```bash
kubectl get pods -n ecommerce
# NAME                              READY   STATUS
# api-gateway-xxxxx                 2/2     Running
# product-service-xxxxx             2/2     Running
```

Inspect a meshed pod:

```bash
kubectl get pod -n ecommerce -l app=product-service -o jsonpath='{.items[0].spec.containers[*].name}'
# product-service linkerd-proxy
```

### B.9 — Install Linkerd Viz

```bash
helm install linkerd-viz linkerd/linkerd-viz \
  -n linkerd-viz --create-namespace \
  -f servicemesh-networkingpolicies/values-viz.yaml \
  --timeout 5m

kubectl wait --for=condition=available deployment/web -n linkerd-viz --timeout=180s
```

**Expected:** `web`, `metrics-api`, `tap` pods Running in `linkerd-viz`.

### B.10 — Enable Prometheus scrape (Grafana golden metrics)

```bash
helm upgrade observability monitoring \
  -n monitoring \
  --reuse-values \
  --set linkerdViz.enabled=true \
  --timeout 5m
```

**Expected:** Prometheus scrapes `linkerd-viz` metrics-api; Grafana dashboard **Linkerd Golden Metrics** populates after traffic.

### B.11 — Apply mesh authorization & resilience policies

```bash
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/meshed-auth.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/servers.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/authorization-policies.strict.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/allow-prometheus-network-scrape.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/retry-timeout/service-profiles.yaml
```

**Expected:**

```bash
kubectl get server,authorizationpolicy,meshtlsauthentication,serviceprofile -n ecommerce
```

Lists Server CRs for ports 8001–8006 (plus RabbitMQ/Mailpit), strict AuthorizationPolicies, and ServiceProfiles.

---

## 6. Verify the Mesh

### 6.1 — linkerd check

```bash
linkerd check
linkerd check --proxy -n ecommerce
```

**Expected:** All checks pass (warnings about version skew are OK on Kind).

### 6.2 — Meshed pod inventory

```bash
kubectl get pods -n ecommerce -o wide
linkerd viz stat deploy -n ecommerce
```

**Expected:** Deployments show **MEShed** column; success rate near 100% after traffic.

### 6.3 — mTLS and identity

```bash
kubectl get serviceaccount -n ecommerce
linkerd viz stat deploy/product-service -n ecommerce --from deploy/api-gateway
```

**Expected:** Traffic from `api-gateway` SA to `product-service` succeeds; stat shows RPS and success rate.

### 6.4 — API gateway still works (north-south)

```bash
curl -sf http://localhost:9080/health && echo " Gateway OK"
curl -s -X POST http://localhost:9080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john.doe@example.com","password":"Password123!"}' | python3 -m json.tool
```

**Expected:** Health OK; login returns a `token`.

### 6.5 — Live tap (optional)

```bash
linkerd viz tap deploy/product-service -n ecommerce
```

In another terminal:

```bash
./simulate-traffic.sh --once
```

**Expected:** Tap stream shows HTTP requests with `:method`, `:path`, response status.

---

## 7. Explore Linkerd Viz

### Open the dashboard

**Use this URL — not the control-plane dashboard:**

```
http://localhost:8084
```

Kind maps NodePort **30884** → host **8084** (see `kind-config.yaml`). Do **not** use `linkerd dashboard` / `http://localhost:4455/controlplane` — that is the control-plane UI, not Viz.

If unreachable:

```bash
kubectl -n linkerd-viz port-forward svc/web 8084:8084
```

### Verify Viz API

```bash
curl -sf http://localhost:8084/api/version
curl -sf 'http://localhost:8084/api/tps-reports?resource_type=deployment&namespace=ecommerce'
```

**Expected:** JSON responses without RPC errors.

### Generate traffic and explore

```bash
./simulate-traffic.sh --duration 120 --rate 2
```

In Linkerd Viz:

| Feature | What to observe |
|---------|-----------------|
| **Topology** | Edges between api-gateway → product/user/cart/order/payment |
| **Golden metrics** | Click a deployment → success rate, RPS, p50/p95 latency |
| **Tap** | Live request stream for a selected pod/deployment |
| **Routes** | Per-route success rates when ServiceProfiles are active |

CLI equivalent:

```bash
linkerd viz stat deploy -n ecommerce
linkerd viz routes deploy/api-gateway -n ecommerce --to svc/user-service --to svc/order-service -o wide
```

---

## 8. Service Identity & Authorization Policies

Linkerd assigns each meshed pod a **TLS identity** derived from its **Kubernetes ServiceAccount**. Strict east-west access requires the caller's SA to appear in the target's **MeshTLSAuthentication**.

See the full mapping table in [`servicemesh-networkingpolicies/mesh/README.md`](servicemesh-networkingpolicies/mesh/README.md).

### Inspect policies

```bash
kubectl get server -n ecommerce
kubectl get meshtlsauthentication -n ecommerce
kubectl get authorizationpolicy -n ecommerce
```

Example — who may call `product-service`:

```bash
kubectl get meshtlsauthentication product-service-callers -n ecommerce -o yaml
```

**Expected:** `identityRefs` lists ServiceAccounts such as `api-gateway`, `cart-service`, `order-service`.

### How the pieces connect

```
Server (product-service-http :8001)
    ↑ targetRef
AuthorizationPolicy (product-service-authorized)
    ↑ requiredAuthenticationRefs
MeshTLSAuthentication (product-service-callers)
    ↑ identityRefs (ServiceAccount names)
```

### Demonstrate strict auth (optional)

With strict policies applied, an **unauthorized** caller gets **403** from the proxy:

```bash
# Ephemeral pod with default SA — NOT in product-service-callers
kubectl run auth-test --rm -it --restart=Never -n ecommerce \
  --image=curlimages/curl -- \
  curl -sv http://product-service:8001/health
```

**Expected:** Request denied (connection reset or HTTP 403 depending on proxy version/config).

Authorized path (api-gateway SA) continues to work:

```bash
curl -sf http://localhost:9080/api/products?limit=1
```

### Re-apply after cert refresh

If you restarted the cluster and refreshed certs, re-apply strict policies:

```bash
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/authorization-policies.strict.yaml
```

---

## 9. Retry & Timeout Policies (ServiceProfiles)

Linkerd 2.14 configures retries on the **outbound (client) proxy** via **ServiceProfile** — HTTPRoute retries are not available in this version.

Manifest: [`mesh/retry-timeout/service-profiles.yaml`](servicemesh-networkingpolicies/mesh/retry-timeout/service-profiles.yaml)

| Setting | Value |
|---------|-------|
| Request timeout | 30s (includes retry time) |
| Retry on | HTTP 502, 503, 504 + connection errors when `isRetryable: true` |
| Retry budget | 20% of original load, min 10/s, 10s TTL |

### Inspect profiles

```bash
kubectl get serviceprofile -n ecommerce
kubectl describe serviceprofile product-service.ecommerce.svc.cluster.local -n ecommerce
```

**Expected:** Profiles named after destination Service FQDNs (e.g. `user-service.ecommerce.svc.cluster.local`).

### Observe retries under chaos (optional)

```bash
# Terminal 1 — watch routes
linkerd viz routes deploy/api-gateway -n ecommerce --to svc/product-service -o wide

# Terminal 2 — kill product-service during traffic
./simulate-traffic.sh --duration 60 --rate 3 &
sleep 10
./load-test/chaos-kill.sh --target product-service
```

**Expected:** Brief success-rate dip; retries may appear in route stats during pod restart window.

---

## 10. Optional — Load Simulation & Grafana Golden Metrics

### Sustained traffic

```bash
./simulate-traffic.sh --duration 300 --rate 3
```

### High-throughput gateway load (~100 req/s aggregate)

```bash
./simulate-100rps.sh
./simulate-100rps.sh --duration 120 --rate 100
```

Uses k6 when available ([`load-test/scenario-100rps.js`](load-test/scenario-100rps.js)); falls back to parallel curl.

### Grafana Linkerd Golden Metrics

```
http://localhost:3030 → E-Commerce → Linkerd Golden Metrics
```

**Expected:** Per-service success rate, request rate, and latency panels populate within 1–2 minutes.

Compare with Linkerd Viz topology and [`exercise.md` Exercise 4](exercise.md#6-exercise-4--generate-traffic-for-dashboards) monitoring dashboards.

---

## 11. Optional — NetworkPolicies + Mesh Together

Mesh install and NetworkPolicy apply are **independent**:

```bash
# Mesh only
./servicemesh-networkingpolicies/install-linkerd.sh

# NetworkPolicies only (requires Cilium)
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --apply

# Both
./servicemesh-networkingpolicies/deploy.sh
```

Skip policies intentionally:

```bash
export DISABLE_NP=1
./servicemesh-networkingpolicies/network-policies/deploy-np.sh --delete
```

With both active, observe Cilium drops (unrelated to Linkerd mTLS):

```bash
hubble observe --verdict DROPPED -n ecommerce -f
```

**Expected:** Cilium blocks L3/L4 paths NetworkPolicy denies; Linkerd enforces mTLS + AuthorizationPolicy on allowed paths.

Important for Viz: [`network-policies/allow-linkerd-viz-scrape.yaml`](servicemesh-networkingpolicies/network-policies/allow-linkerd-viz-scrape.yaml) must allow `web → metrics-api:8085` when policies are enforced.

---

## 12. Cleanup

### Remove mesh only (keep app + Cilium)

```bash
helm uninstall linkerd-viz -n linkerd-viz
helm uninstall linkerd-control-plane linkerd-cni linkerd-crds -n linkerd

# Restart app pods to drop sidecars
kubectl rollout restart deployment -n ecommerce --all
kubectl rollout restart statefulset -n ecommerce --all
```

### Remove mesh policies (keep deployments)

```bash
kubectl delete -f servicemesh-networkingpolicies/mesh/server-authorization/ --ignore-not-found
kubectl delete -f servicemesh-networkingpolicies/mesh/retry-timeout/service-profiles.yaml --ignore-not-found
kubectl annotate namespace ecommerce linkerd.io/inject- 2>/dev/null || true
```

### Full cluster teardown

```bash
kind delete cluster --name ecommerce-vault
```

See [exercise.md — Cleanup](exercise.md#11-cleanup) for removing monitoring, NetworkPolicies, and Cilium individually.

---

## 13. Troubleshooting

### Proxy not injected (pods stay 1/1)

**Symptom:** Pods show `1/1 Running` after install.

**Checks:**

```bash
kubectl get namespace ecommerce -o yaml | grep linkerd.io/inject
kubectl get pods -n linkerd -l linkerd.io/control-plane-component=proxy-injector
kubectl describe pod -n ecommerce <pod-name> | tail -30
```

**Fix:**

```bash
kubectl apply -f servicemesh-networkingpolicies/mesh/namespace-annotation.yaml
kubectl rollout restart deployment -n ecommerce --all
```

Look for init/proxy errors in pod events. CNPG/Redis/RabbitMQ may have intentional skip annotations.

### linkerd check failures

```bash
linkerd check --verbose
kubectl get pods -n linkerd
kubectl logs -n linkerd deploy/linkerd-identity --tail=30
```

Common on Kind: resource limits — values in `values.yaml` are tuned for dev clusters.

### Cert expiry after cluster stop/start

**Symptom:** API returns 504; Linkerd logs show `invalid peer certificate: Expired`.

**Fix:**

```bash
docker start ecommerce-vault-control-plane   # if stopped
kubectl wait --for=condition=ready node --all --timeout=120s

kubectl rollout restart deployment -n linkerd \
  linkerd-identity linkerd-destination linkerd-proxy-injector
kubectl rollout restart deployment -n ecommerce --all

# Re-apply strict auth if east-west traffic fails
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/authorization-policies.strict.yaml

# Or full refresh:
# ./servicemesh-networkingpolicies/install-linkerd.sh
```

**Verify:** `curl -sf http://localhost:9080/health`

### Linkerd Viz RPC error (metrics-api)

**Symptom:** Dashboard at wrong URL (`:4455/controlplane`) or at `:8084`:

```text
RPC error: connection to 10.96.x.x:8085 (metrics-api) — use of closed network connection
```

**Causes:**

1. **Wrong dashboard** — Use `http://localhost:8084`, not `linkerd dashboard`.
2. **NetworkPolicy blocks web → metrics-api** — Re-apply Viz scrape policy.
3. **Stale proxy certs** — Restart Viz deployments.

**Fix:**

```bash
kubectl apply -f servicemesh-networkingpolicies/network-policies/allow-linkerd-viz-scrape.yaml

kubectl rollout restart deployment -n linkerd-viz web metrics-api tap tap-injector prometheus
kubectl rollout status deployment -n linkerd-viz --timeout=180s

kubectl -n linkerd-viz port-forward svc/web 8084:8084
curl -sf http://localhost:8084/api/version
```

### East-west 403 after policy apply

**Symptom:** Gateway returns 502/503; `linkerd viz stat` shows failures between services.

**Fix:** Ensure strict auth policies match current ServiceAccounts:

```bash
kubectl get serviceaccount -n ecommerce
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/meshed-auth.yaml
kubectl apply -f servicemesh-networkingpolicies/mesh/server-authorization/authorization-policies.strict.yaml
```

### CNI conflict / Linkerd CNI not ready

```bash
kubectl rollout status daemonset/linkerd-cni -n linkerd
kubectl get pods -n kube-system -l k8s-app=cilium
```

Linkerd CNI requires Cilium already running. Recreate cluster via `./deploy.sh` if CNI is wrong.

### Port 8084 already in use

```bash
lsof -i :8084
kubectl -n linkerd-viz port-forward svc/web 8085:8084   # alternate local port
```

---

## 14. Next Steps

| Lab | File |
|-----|------|
| NetworkPolicies + Hubble drops | [`exercise.md` Exercise 5](exercise.md#7-exercise-5--network-policies-cilium-enforcement--hubble-drops) |
| k6 load testing | [`exercise.md` Exercise 7](exercise.md#9-exercise-7--k6-load-testing) |
| Chaos under load | [`exercise.md` Exercise 8](exercise.md#10-exercise-8--chaos-testing-under-load) |
| Mesh policy reference | [`servicemesh-networkingpolicies/mesh/README.md`](servicemesh-networkingpolicies/mesh/README.md) |

**Quick reference:**

| Item | Value |
|------|-------|
| Cluster | `ecommerce-vault` |
| App namespace | `ecommerce` |
| Linkerd version | `stable-2.14.10` |
| Viz URL | http://localhost:8084 |
| Install script | `./servicemesh-networkingpolicies/install-linkerd.sh` |
| CNI | Cilium 1.16.5 + Linkerd CNI plugin |

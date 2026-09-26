# Ecommerce Observability

App-layer observability wiring: tells the cluster's Prometheus what to scrape, what to alert on, and delivers Grafana dashboards. Logs flow into Loki automatically (Promtail is a DaemonSet, no per-app config needed).

> **Full guide:** see [`docs/MONITORING.md`](../../docs/MONITORING.md) for architecture, metrics/logs flow, RED method, dashboard catalog, and troubleshooting.

```
observability/
├── podmonitors.tf       # PodMonitor per microservice + api-gateway
├── prometheusrules.tf   # Recording rules + alerts (service health, business, deps)
├── dashboards.tf        # ConfigMaps loading operational + SRE teaching dashboards
└── dashboards/
    ├── ecommerce-overview.json   # Service RED (rate, errors, latency p95) + pod CPU/mem
    └── ecommerce-logs.json       # Loki-backed log explorer

../../dashboards/                  # SRE teaching dashboards (8 panels-rich JSON files)
├── README.md                      # SRE curriculum + deploy instructions
├── generate.py                    # Regenerate JSON after editing queries/text
└── 00-sre-overview.json … 07-sre-logs-incidents.json
```

---

## Prerequisites

The cluster-layer LGTM stack must already be installed (`eks/k8s-services/logging-monitoring/`):

| Component | What it provides | Where |
|-----------|------------------|-------|
| `kube-prometheus-stack` | Prometheus + Grafana + Alertmanager + operator CRDs (`PodMonitor`, `PrometheusRule`, `ServiceMonitor`) + dashboard sidecar | `monitoring` ns |
| `loki-stack` | Loki + Promtail DaemonSet | `monitoring` ns |
| Grafana datasources | Prometheus (default) + Loki (added via `additionalDataSources`) | provisioned by helm |

And the app workloads from `helm-ecommerce/` must be running in the `ecommerce` namespace.

---

## What gets installed

### 1. PodMonitors (`podmonitors.tf`)

One `PodMonitor` per microservice telling Prometheus to scrape the pod's container port at `/metrics`. Service → port map lives in `variables.tf`:

| Service | Port |
|---------|------|
| product-service | 8001 |
| user-service | 8002 |
| cart-service | 8003 |
| order-service | 8004 |
| payment-service | 8005 |
| notification-service | 8006 |
| api-gateway | 80 |

Each scrape relabels `__meta_kubernetes_pod_label_app` → `service` so every app-level metric carries a stable `service` label that the rules and dashboards rely on.

> The Helm chart's `Service` objects don't name their ports, so `PodMonitor` (which targets container ports directly) is used instead of `ServiceMonitor`. If `up{job=~".*ecommerce.*"} == 0` for a service, check that the container actually exposes `/metrics` — the underlying images need a Prometheus client library wired in (Go: `prometheus/client_golang`, Python: `prometheus_client`, Node: `prom-client`).

### 2. PrometheusRules (`prometheusrules.tf`)

Four rule groups, all scoped to `namespace="ecommerce"`:

| Group | Rules |
|-------|-------|
| `ecommerce.recording` | `ecommerce:http_request_rate:5m`, `ecommerce:http_error_rate:5m`, `ecommerce:http_latency_p95:5m` (dashboards consume these) |
| `ecommerce.service-health` | `EcommerceServiceDown`, `EcommerceHighErrorRate` (>5% 5xx), `EcommerceHighLatency` (p95 >1s), `EcommercePodCrashLooping` |
| `ecommerce.business` | `EcommerceHighPaymentFailureRate`, `EcommerceNoPaymentsProcessed` |
| `ecommerce.dependencies` | `EcommerceRabbitMQDown`, `EcommerceRedisDown`, `EcommerceCNPGClusterUnhealthy` |

Recording rules pre-compute the hot RED queries so the dashboard panels stay snappy even with months of data.

### 3. Grafana dashboards (`dashboards.tf` + `dashboards/*.json` + `../../dashboards/`)

Delivered as ConfigMaps in the `monitoring` namespace with label `grafana_dashboard: "1"`. Grafana's sidecar picks them up automatically — no Grafana restart needed.

**Operational (ecommerce folder):**

| Dashboard | UID | What it shows |
|-----------|-----|---------------|
| `Ecommerce — Service RED` | `ecommerce-red` | Up/down stats, request rate, error %, p95 latency, pod CPU/mem, restarts — filterable by `service` |
| `Ecommerce — Logs (Loki)` | `ecommerce-logs` | Log volume + error-rate over time, live tail, errors-only view — filterable by `namespace`, `app`, free-text `search` |

**SRE teaching (`../../dashboards/` → Grafana folder `sre-teaching`):**

| Dashboard | UID | SRE concept |
|-----------|-----|-------------|
| `SRE Teaching — Overview` | `sre-overview` | Curriculum map + live platform snapshot |
| `SRE Teaching — Golden Signals (RED)` | `sre-golden-signals` | Rate, Errors, Duration |
| `SRE Teaching — USE Method (Kubernetes)` | `sre-use-kubernetes` | Utilization, Saturation, Errors |
| `SRE Teaching — SLO & Error Budget` | `sre-slo-error-budget` | SLI/SLO, error budget, burn rate |
| `SRE Teaching — Alerting & Incident Readiness` | `sre-alerting` | Firing alerts, severity, triage |
| `SRE Teaching — Dependencies & Blast Radius` | `sre-dependencies` | Redis, RabbitMQ, CNPG cascade |
| `SRE Teaching — Business SLIs (Ecommerce)` | `sre-business-slis` | Orders, payments, product queries |
| `SRE Teaching — Logs for Incidents (Loki)` | `sre-logs-incidents` | Log exploration during incidents |

See `../../dashboards/README.md` for the bootcamp learning path and regenerate instructions.

---

## Logs flow (already wired by the cluster layer)

```
container stdout/stderr ──▶ kubelet log files (/var/log/pods/...)
                                ▼
                       Promtail DaemonSet (loki-stack)
                                ▼
                          Loki (monitoring ns)
                                ▼
                  Grafana → Loki datasource → dashboards
```

Promtail tails every pod's logs on every node; the `ecommerce` apps are picked up automatically with labels `namespace`, `pod`, `app`, `container`. The "Ecommerce — Logs" dashboard filters on those.

To explore ad-hoc:
- Grafana → **Explore** → datasource **Loki**
- `{namespace="ecommerce"} |~ "(?i)error"`
- `{namespace="ecommerce", app="payment-service"} | json | status_code >= 500`

---

## Apply

```bash
cd eks-microservice-implementation/infra/observability
terraform init
terraform apply
```

Verify:

```bash
# PodMonitors picked up
kubectl get podmonitors -n monitoring -l app.kubernetes.io/part-of=ecommerce

# Rule loaded into Prometheus
kubectl get prometheusrules -n monitoring ecommerce-app-rules

# Dashboard ConfigMaps
kubectl get cm -n monitoring -l grafana_dashboard=1

# Targets actually scraping (port-forward Prometheus)
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# then open http://localhost:9090/targets and filter for ecommerce
```

---

## Tearing down

```bash
terraform destroy
```

Removes only the PodMonitors, PrometheusRule, and the two dashboard ConfigMaps. Prometheus/Grafana/Loki themselves are unaffected (managed by `eks/k8s-services/logging-monitoring/`).

---

## Adding a new microservice

1. Add the service to the `services` map in `variables.tf` with its container port.
2. `terraform apply` — a new `PodMonitor` appears in the monitoring namespace.
3. If the service emits app-specific metrics (e.g. business counters), add rules/alerts to `prometheusrules.tf` and panels to `dashboards/ecommerce-overview.json`.
4. The Loki dashboard needs no change — it picks up the new `app` label automatically.

---

## Reference

- Standalone (non-Kubernetes) prometheus scrape config + alerts that this module is derived from: `../../apps/monitoring/prometheus/`
- Cluster LGTM install (Prometheus, Grafana, Loki, Promtail): `../../../eks/k8s-services/logging-monitoring/`
- Grafana endpoint: https://grafana.livingdevops.org (admin/admin123)
- Prometheus endpoint: https://prometheus.livingdevops.org

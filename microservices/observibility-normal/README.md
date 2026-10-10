# Prometheus, Loki, Promtail, and Grafana on Kind

This folder installs a small metrics-and-logs stack in the same Kind cluster as
the Helm-deployed e-commerce application:

- Prometheus discovers annotated application pods in `ecommerce`.
- Prometheus Node Exporter runs on every Kind node and exposes host metrics.
- Promtail runs on every node and reads Kubernetes CRI logs from
  `/var/log/pods`.
- Loki stores logs locally.
- Grafana is provisioned with both data sources and the
  **E-commerce Services Overview** dashboard.

The setup is intended for local learning. Prometheus, Loki, and Grafana use
`emptyDir`, so their data is deleted when their pods are replaced.

## Prerequisites

Docker Desktop must be running. Install `kind` and `kubectl` first. The
application deployment also requires `helm`. The observability deployment
script can be run from any directory.

## 1. Deploy the application first

The deployment script creates/uses the `ecommerce-ms-simple` Kind cluster,
builds the local images, deploys the Helm chart into `ecommerce`, and seeds the
application.

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices
./helm-deployments-kind/helm-ms-simple/helm-deploy.sh
kubectl config use-context kind-ecommerce-ms-simple
kubectl get pods -n ecommerce
```

Wait until all six backend deployments are available:

```bash
for service in product-service user-service cart-service order-service payment-service notification-service; do
  kubectl wait --for=condition=available "deployment/${service}" -n ecommerce --timeout=180s
done
```

## 2. Install monitoring in the same cluster

Use the deployment script (preferred):

```bash
./observibility-normal/deploy-observability.sh
```

The script finds the Kind cluster containing the e-commerce app (preferring
`kind-ecommerce-ms-simple`), selects its context, validates and applies the
manifests in dependency order, waits for every workload, and prints the exact
access and verification commands. It is safe to rerun.

To install manually instead, run these commands from the `microservices`
directory:

```bash
kubectl config use-context kind-ecommerce-ms-simple
kubectl apply -f observibility-normal/00-namespace.yaml
kubectl apply -f observibility-normal/10-prometheus.yaml
kubectl apply -f observibility-normal/15-node-exporter.yaml
kubectl apply -f observibility-normal/20-loki.yaml
kubectl apply -f observibility-normal/30-promtail.yaml
kubectl apply -f observibility-normal/40-grafana.yaml
kubectl rollout restart deployment/prometheus -n observability
kubectl rollout restart daemonset/promtail -n observability
kubectl rollout status deployment/prometheus -n observability --timeout=180s
kubectl rollout status daemonset/node-exporter -n observability --timeout=180s
kubectl rollout status deployment/loki -n observability --timeout=180s
kubectl rollout status daemonset/promtail -n observability --timeout=180s
kubectl rollout status deployment/grafana -n observability --timeout=180s
kubectl get pods -n observability
```

## 3. Verify Prometheus targets

Open a dedicated terminal and keep this running:

```bash
kubectl port-forward -n observability service/prometheus 9090:9090
```

Open <http://localhost:9090/targets>. The `ecommerce-pods` job should show six
healthy targets, and the `node-exporter` job should show one healthy target per
Kind node. You can also verify them from another terminal:

```bash
kubectl get daemonset,pods -n observability \
  -l app.kubernetes.io/name=node-exporter -o wide
kubectl get endpoints node-exporter -n observability
curl -s 'http://localhost:9090/api/v1/targets?state=active' \
  | python3 -m json.tool
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=count by (app) (up{job="ecommerce-pods"} == 1)' \
  | python3 -m json.tool
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=count by (node) (up{job="node-exporter"} == 1)' \
  | python3 -m json.tool
```

Useful host-metrics PromQL:

```promql
# CPU utilization percentage per node
100 * (1 - avg by (node) (rate(node_cpu_seconds_total{job="node-exporter", mode="idle"}[5m])))

# Available memory percentage per node
100 * node_memory_MemAvailable_bytes{job="node-exporter"}
  / node_memory_MemTotal_bytes{job="node-exporter"}

# Root filesystem utilization percentage per node
100 * (
  1 - node_filesystem_avail_bytes{job="node-exporter", mountpoint="/", fstype!=""}
    / node_filesystem_size_bytes{job="node-exporter", mountpoint="/", fstype!=""}
)
```

## 4. Verify Loki and application logs

First check Promtail and Loki:

```bash
kubectl logs -n observability daemonset/promtail --tail=50
kubectl logs -n observability deployment/loki --tail=50
```

Then forward Loki in a dedicated terminal:

```bash
kubectl port-forward -n observability service/loki 3100:3100
```

From another terminal, confirm Loki is ready and has discovered e-commerce log
labels:

```bash
curl -fsS http://localhost:3100/ready
curl -sG http://localhost:3100/loki/api/v1/label/pod/values \
  --data-urlencode 'query={namespace="ecommerce"}' \
  | python3 -m json.tool
```

## 5. Open Grafana

Keep this port-forward running in a dedicated terminal:

```bash
kubectl port-forward -n observability service/grafana 3001:3000
```

Open <http://localhost:3001>, sign in with `admin` / `admin`, and open
**Dashboards → E-commerce → E-commerce Services Overview**. Prometheus and Loki
are already provisioned under **Connections → Data sources**.

## 6. Generate realistic traffic

`simulate-load.sh` runs a bounded workload for 15 minutes by default. It finds
the Kind cluster containing `ecommerce`, waits for all six backend deployments,
checks each health endpoint, and then sends a mix of:

- product browsing and searches;
- seeded-user login, profile reads, and order-list reads;
- transient cart add/read/remove operations when seed data is available;
- expected 400, 401, and 404 responses;
- direct health requests to every backend, including notification-service.

The payment requests exercise only authentication, validation, and missing
record paths. The script does not contact Razorpay, alter stock, create orders,
run chaos, or use unbounded concurrency. Credentials and JWTs are never
printed.

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices
./observibility-normal/simulate-load.sh
```

The simulator first tries `http://localhost:8080`. If it is unavailable, it
starts its own `kubectl port-forward` on a free loopback port and removes it on
exit or `Ctrl+C`. It prints status counts every 30 seconds and a final summary.
It is safe to rerun; each cart write is paired with a removal.

Common configuration:

```bash
# Two-minute smoke run at roughly one scenario per second
DURATION_SECONDS=120 REQUEST_INTERVAL_SECONDS=1 \
  ./observibility-normal/simulate-load.sh

# Use a non-default gateway or adjust reporting/health frequency
GATEWAY_URL=http://localhost:18080 \
STATUS_INTERVAL_SECONDS=15 HEALTH_INTERVAL_SECONDS=10 \
  ./observibility-normal/simulate-load.sh
```

Supported variables include:

- `DURATION_SECONDS` (default `900`)
- `REQUEST_INTERVAL_SECONDS` (default `0.5`)
- `STATUS_INTERVAL_SECONDS` (default `30`)
- `HEALTH_INTERVAL_SECONDS` (default `15`)
- `REQUEST_TIMEOUT_SECONDS` (default `5`)
- `GATEWAY_URL` (default `http://localhost:8080`)
- `LOAD_USER_EMAIL` and `LOAD_USER_PASSWORD` (default to the local seed user)

Wait for at least one Prometheus scrape after starting traffic. Useful PromQL:

```promql
# Requests per second by backend
sum by (service) (rate(service_http_requests_total[5m]))

# Percentage of responses that are 4xx or 5xx
100 *
sum by (service) (rate(service_http_requests_total{status_code=~"4..|5.."}[5m]))
/
clamp_min(sum by (service) (rate(service_http_requests_total[5m])), 0.001)

# p95 latency by backend
histogram_quantile(
  0.95,
  sum by (le, service) (
    rate(service_http_request_duration_seconds_bucket[5m])
  )
)

# Requests currently in flight
sum by (service) (service_http_requests_in_flight)
```

Promtail provides `namespace`, `app`, `pod`, `container`, `node`, `stream`,
and `job` labels. HTTP status is a structured field in the Go service logs,
not an indexed Loki label, so parse it at query time:

```logql
# All backend application logs
{namespace="ecommerce", app=~".+-service"}

# One application's logs
{namespace="ecommerce", app="cart-service"}

# Structured client/server errors from Go service request logs
{namespace="ecommerce", app=~"product-service|order-service"}
  | json
  | status >= 400

# Log volume by Kubernetes app label
sum by (app) (
  count_over_time({namespace="ecommerce", app=~".+-service"}[5m])
)

# Status text in Flask/Werkzeug request logs
{namespace="ecommerce", app=~"payment-service|notification-service"}
  |~ " (400|401|404|500|503) "
```

## 7. Cleanup

Stop the port-forward commands with `Ctrl+C`. Remove only monitoring with:

```bash
kubectl delete -f observibility-normal/40-grafana.yaml
kubectl delete -f observibility-normal/30-promtail.yaml
kubectl delete -f observibility-normal/20-loki.yaml
kubectl delete -f observibility-normal/15-node-exporter.yaml
kubectl delete -f observibility-normal/10-prometheus.yaml
kubectl delete -f observibility-normal/00-namespace.yaml
```

Remove the application release but keep the cluster with:

```bash
helm uninstall ecommerce -n ecommerce
kubectl delete namespace ecommerce
```

Or remove the entire local cluster:

```bash
kind delete cluster --name ecommerce-ms-simple
```

## Notes

- Scraping is opt-in through `prometheus.io/*` pod annotations in the Helm
  templates.
- Node Exporter is pinned to `v1.8.2`; it mounts `/proc`, `/sys`, and `/`
  read-only and runs without privilege escalation or Linux capabilities.
- Promtail adds `namespace`, `app`, `pod`, `container`, `node`, `stream`, and
  `job` labels to Kubernetes pod logs. The CRI parsing stage supplies the
  `stream` label.
- The shared dashboard contract is
  `service_http_requests_total`,
  `service_http_request_duration_seconds`, and
  `service_http_requests_in_flight`, all labeled by `service`.
- Promtail reached upstream end-of-life in March 2026. It is pinned here
  because this exercise explicitly uses Promtail; use Grafana Alloy for a new
  production deployment.
- The `admin` / `admin` Grafana login and ephemeral storage are only suitable
  for a local Kind learning environment.

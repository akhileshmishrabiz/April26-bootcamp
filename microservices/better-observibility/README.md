# Better observability for the e-commerce app

This installs the following into a local Kind cluster with Helm:

- Prometheus Operator, Prometheus, Alertmanager, and Grafana
- Loki in single-binary mode
- Promtail on every node
- scraping for the six e-commerce services
- CloudNativePG metrics
- three local Grafana dashboards

The defaults expect the app in namespace `ecommerce` and monitoring in
namespace `monitoring`.

Monitoring data uses the Rancher local-path `standard` StorageClass:

- Prometheus: 10 GiB
- Loki: 10 GiB
- Grafana: 2 GiB
- Alertmanager: 2 GiB

## Quick install

It is safe to install this before or after the application.

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/better-observibility
chmod +x install.sh golden-dashboards/apply-dashboards.sh alerts/*.sh
./install.sh
```

Deploy the application with:

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/helm-deployments-kind/helm-ms-cnpg-vault-eso
./helm-cnpg-vault-deploy.sh
```

## Manual copy/paste commands

These are the important commands from `install.sh`:

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/better-observibility

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f values/kube-prometheus-stack.yaml \
  --wait --timeout 10m

helm upgrade --install loki grafana/loki \
  -n monitoring \
  -f values/loki.yaml \
  --wait --timeout 10m

helm upgrade --install promtail grafana/promtail \
  -n monitoring \
  -f values/promtail.yaml \
  --wait --timeout 10m

kubectl apply -f manifests/services-servicemonitor.yaml
kubectl apply -f manifests/cnpg-podmonitor.yaml
./golden-dashboards/apply-dashboards.sh
```

## Open the tools

Grafana:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Open <http://localhost:3000> and log in with `admin` / `admin`.

Prometheus:

```bash
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open <http://localhost:9090/targets>. The
`serviceMonitor/monitoring/ecommerce-services` and
`podMonitor/monitoring/ecommerce-cnpg` targets should be up after the app is
running. The six application Services expose a named `http-metrics` port used
by `manifests/services-servicemonitor.yaml`.

## Dashboards

`golden-dashboards/apply-dashboards.sh` creates one labeled ConfigMap. Grafana's
sidecar discovers it and loads:

- **Service Golden Signals**: health, traffic, 5xx ratio, p50/p95/p99 latency,
  and requests in flight
- **PostgreSQL (CloudNativePG)**: transactions, connections, blocked queries,
  cache hit ratio, size, deadlocks, rollbacks, and app-observed query latency
- **Service Logs**: log volume, errors/exceptions, and searchable logs

Run the dashboard script again after editing any JSON file:

```bash
./golden-dashboards/apply-dashboards.sh
```

### Query-time limitation

The product, order, and user services register
`database_query_duration_seconds`, so the PostgreSQL dashboard includes
p50/p95/p99 query-latency panels for it. At present, the application handlers
do not consistently call the recording helpers, so this panel can be empty
until those database calls are instrumented.

CloudNativePG's default metrics provide database-level I/O time, transactions,
locks, cache behavior, and sizes. They do **not** provide a reliable list of
individual slow SQL statements. That requires enabling PostgreSQL
`pg_stat_statements` and configuring an additional CNPG monitoring query. Do
not put full SQL text into unrestricted metric labels in a real system because
it can create high-cardinality metrics and leak sensitive values.

For the full upstream CloudNativePG dashboard, you can also install:

```bash
helm repo add cnpg-grafana https://cloudnative-pg.github.io/grafana-dashboards
helm upgrade --install cnpg-grafana-cluster cnpg-grafana/cluster \
  -n monitoring \
  --set grafanaDashboard.labels.grafana_dashboard=1
```

## Alerts

Read `alerts/README.md`, then apply:

```bash
./alerts/configure-alerts.sh
./alerts/generate-load.sh
```

Alertmanager delivers development emails to the app's Mailpit SMTP service.
Open the inbox with:

```bash
kubectl -n ecommerce port-forward svc/mailpit 8025:8025
```

Then visit <http://localhost:8025>.

## Uninstall

```bash
helm uninstall promtail -n monitoring
helm uninstall loki -n monitoring
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

This does not remove the application or its databases.

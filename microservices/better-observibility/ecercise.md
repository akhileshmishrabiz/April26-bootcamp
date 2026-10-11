# Observability exercise

In this exercise you will:

1. deploy the e-commerce application
2. install Prometheus, Grafana, Loki, and Promtail
3. inspect application and PostgreSQL metrics
4. view application logs
5. generate load
6. trigger an alert and receive an email in Mailpit

The commands expect:

- application namespace: `ecommerce`
- monitoring namespace: `monitoring`
- a running Kind cluster

## 1. Check the required tools

```bash
kubectl cluster-info
helm version
docker version
```

Make sure the correct Kubernetes context is selected:

```bash
kubectl config current-context
```

## 2. Bring the application up

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/helm-deployments-kind/helm-ms-cnpg-vault-eso
./helm-cnpg-vault-deploy.sh
```

The deployment can take several minutes.

Verify the application:

```bash
kubectl get pods -n ecommerce
kubectl get services -n ecommerce
kubectl get clusters.postgresql.cnpg.io -n ecommerce
```

Wait until the application pods and PostgreSQL clusters are ready.

```bash
kubectl wait --for=condition=available deployment \
  --all -n ecommerce --timeout=10m
```

## 3. Install the observability stack

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/better-observibility
chmod +x install.sh golden-dashboards/apply-dashboards.sh alerts/*.sh
./install.sh
```

The installation creates:

- Prometheus and Prometheus Operator
- Grafana
- Alertmanager
- Loki
- Promtail
- CloudNativePG monitoring
- Grafana dashboards
- alert rules and Mailpit email delivery

Verify the monitoring pods:

```bash
kubectl get pods -n monitoring
kubectl get podmonitor -n monitoring
kubectl get prometheusrule -n monitoring
```

All monitoring pods should be `Running` or `Completed`.

## 4. Open Grafana, Prometheus, and Mailpit

Run each port-forward in a separate terminal and leave it running.

Terminal 1 — Grafana:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Open <http://localhost:3000>.

- username: `admin`
- password: `admin`

Terminal 2 — Prometheus:

```bash
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open <http://localhost:9090>.

Terminal 3 — Mailpit:

```bash
kubectl -n ecommerce port-forward svc/mailpit 8025:8025
```

Open <http://localhost:8025>.

In Cursor or VS Code, press `Cmd + Shift + P`, select
**Simple Browser: Show**, and enter one of the URLs above.

## 5. Verify Prometheus scraping

Open <http://localhost:9090/targets>.

Confirm that these targets are `UP`:

- `serviceMonitor/monitoring/ecommerce-services`
- `podMonitor/monitoring/ecommerce-cnpg`

Try these queries in the Prometheus expression browser:

Service availability:

```promql
up{
  namespace="ecommerce",
  service=~"product-service|user-service|cart-service|order-service|payment-service|notification-service"
}
```

Requests per second:

```promql
sum by (service) (rate(service_http_requests_total[5m]))
```

P95 HTTP latency:

```promql
histogram_quantile(
  0.95,
  sum by (le, service) (
    rate(service_http_request_duration_seconds_bucket[5m])
  )
)
```

PostgreSQL availability:

```promql
cnpg_collector_up{namespace="ecommerce"}
```

PostgreSQL transactions per second:

```promql
sum by (cluster, datname) (
  rate(cnpg_pg_stat_database_xact_commit{
    namespace="ecommerce",
    datname!~"template.*|postgres"
  }[5m])
)
```

## 6. Generate normal application traffic

In another terminal, expose the API gateway:

```bash
kubectl -n ecommerce port-forward svc/api-gateway 8080:80
```

Test the product API:

```bash
curl http://localhost:8080/api/products
```

Generate a small amount of traffic:

```bash
for i in {1..50}; do
  curl -s http://localhost:8080/api/products >/dev/null
  sleep 0.2
done
```

Return to Prometheus and run the request-rate query again.

## 7. Explore the Grafana dashboards

In Grafana, open **Dashboards** and locate:

### E-commerce / Service Golden Signals

Check:

- service health
- request rate
- HTTP 5xx error rate
- p50, p95, and p99 latency
- requests in flight

### E-commerce / PostgreSQL (CloudNativePG)

Check:

- PostgreSQL health
- transactions per second
- active and blocked connections
- buffer-cache hit ratio
- database sizes
- deadlocks and rollbacks

The application defines `database_query_duration_seconds`, but not every
database operation currently records it. The query-latency panel can therefore
be empty until those calls are fully instrumented.

### E-commerce / Service Logs

Check:

- log volume by service
- errors and exceptions
- live application logs

Choose an application from the dashboard variable and search for words such
as `error`, `database`, or `request`.

You can also use Grafana **Explore**, select the Loki datasource, and run:

```logql
{namespace="ecommerce"}
```

Only errors:

```logql
{namespace="ecommerce"} |~ "(?i)(error|exception|fatal|panic)"
```

## 8. Trigger an alert with load

The supplied load test calls the product-service health endpoint with enough
traffic to trigger `EcommerceHighRequestRate`.

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/better-observibility
./alerts/generate-load.sh
```

The default test:

- runs for 150 seconds
- uses 15 workers
- triggers when traffic exceeds 10 requests/second for one minute
- does not scale down or delete the application

While it runs, open <http://localhost:9090/alerts>.

Observe the alert states:

```text
Inactive → Pending → Firing
```

Allow approximately 1–2 minutes for the alert to fire. Alertmanager adds a
10-second grouping delay before sending the email.

Open <http://localhost:8025> and confirm that Mailpit receives the firing
email. After the load stops and the request rate falls, a resolved email should
also arrive.

To run a longer load:

```bash
DURATION_SECONDS=180 WORKERS=20 ./alerts/generate-load.sh
```

## 9. Inspect alert resources

List the rules:

```bash
kubectl -n monitoring get prometheusrule ecommerce-alerts
kubectl -n monitoring describe prometheusrule ecommerce-alerts
```

Open Alertmanager:

```bash
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

Then open <http://localhost:9093>.

The local email path is:

```text
PrometheusRule
    → Prometheus evaluates the rule
    → Alertmanager groups the alert
    → Mailpit SMTP receives the email
    → Mailpit web UI displays it
```

For production, replace Mailpit with a real SMTP provider and keep SMTP
credentials in a Kubernetes Secret.

## 10. Troubleshooting

### A target is down

```bash
kubectl get pods -n ecommerce
kubectl get pods -n monitoring
kubectl logs -n monitoring \
  statefulset/prometheus-monitoring-kube-prometheus-prometheus \
  --tail=100
```

Check a service metrics endpoint directly:

```bash
kubectl -n ecommerce port-forward svc/product-service 8001:8001
curl http://localhost:8001/metrics
```

### Dashboards are missing

```bash
./golden-dashboards/apply-dashboards.sh
kubectl -n monitoring get configmap ecommerce-golden-dashboards \
  --show-labels
```

The ConfigMap must have `grafana_dashboard=1`.

### Logs are missing

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail \
  --tail=100
```

### Alert email is missing

```bash
kubectl get pods -n ecommerce -l app=mailpit
kubectl get pods -n monitoring \
  -l app.kubernetes.io/name=alertmanager
```

If Alertmanager configuration or rules were not installed, rerun:

```bash
./alerts/configure-alerts.sh
```

## 11. Important tracing note

The application has partial OpenTelemetry instrumentation in the product and
order services, but this observability stack does not yet install an
OpenTelemetry Collector or Tempo. Traces are therefore not stored or visible
in Grafana in this exercise.

A complete tracing flow would be:

```text
Application
    → OpenTelemetry Collector
    → Tempo
    → Grafana Explore
```

## 12. Cleanup

Stop port-forward commands with `Ctrl+C`, then remove the monitoring stack:

```bash
helm uninstall promtail -n monitoring
helm uninstall loki -n monitoring
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

The application remains deployed.

To remove the application namespace as well:

```bash
kubectl delete namespace ecommerce
```

## Exercise checklist

- [ ] Application pods are healthy
- [ ] Monitoring pods are healthy
- [ ] Prometheus service targets are up
- [ ] CloudNativePG targets are up
- [ ] Golden-signals dashboard contains data
- [ ] PostgreSQL dashboard contains data
- [ ] Logs are visible through Loki
- [ ] Load test makes the alert pending and firing
- [ ] Mailpit receives the firing email
- [ ] Mailpit receives the resolved email
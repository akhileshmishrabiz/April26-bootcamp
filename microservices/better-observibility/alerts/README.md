# E-commerce alerts

`ecommerce-alerts.yaml` contains alerts for:

- service scrape failures
- HTTP 5xx ratio above 5%
- p95 HTTP latency above 1 second
- request traffic above 10 requests/second
- PostgreSQL availability
- blocked queries, deadlocks, and low buffer-cache hit ratio

## Configure email and apply the rules

The app deployment already includes Mailpit. Alertmanager is configured to
deliver alert emails to that local SMTP server, so no password or external
email account is needed.

```bash
cd /Users/akhilesh/projects/April26-bootcamp/microservices/better-observibility
./alerts/configure-alerts.sh
```

Open the email inbox:

```bash
kubectl -n ecommerce port-forward svc/mailpit 8025:8025
```

Visit <http://localhost:8025>. Firing and resolved alert emails are delivered
to `dev-team@ecommerce.local`; Mailpit accepts that local address without
sending anything to the public internet.

## Generate load and fire an alert

Run:

```bash
./alerts/generate-load.sh
```

The script port-forwards `product-service` and sends traffic for 150 seconds.
`EcommerceHighRequestRate` becomes pending and then fires after the rate stays
above 10 requests/second for one minute. Allow another 10-30 seconds for
Prometheus scraping, rule evaluation, and Alertmanager grouping.

Watch the alert:

```bash
kubectl -n monitoring port-forward \
  svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Visit <http://localhost:9090/alerts>. You should receive:

1. a firing email while the load is running
2. a resolved email after traffic returns to normal

Load settings can be overridden:

```bash
DURATION_SECONDS=180 WORKERS=20 ./alerts/generate-load.sh
```

## Real external email

Mailpit is intended for local development. To send to Gmail, SES, SendGrid, or
another provider, replace the `mailpit-email` receiver under
`alertmanager.config` in `values/kube-prometheus-stack.yaml` with that
provider's SMTP host, authenticated username/password, sender, and recipient.
Keep credentials in a Kubernetes Secret rather than committing them here.

## Namespace changes

The supplied rules expect the app in `ecommerce` and monitoring in
`monitoring`. If those differ, replace both namespace values before applying.

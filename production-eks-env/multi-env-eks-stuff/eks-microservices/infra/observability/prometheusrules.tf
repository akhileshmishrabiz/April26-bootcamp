# App-level alerting + recording rules. Adapted from
# apps/monitoring/prometheus/rules/alerts.yml, refactored to use the
# `service` and `namespace` labels added by the PodMonitor relabelings,
# and scoped to the ecommerce namespace so they don't fire for unrelated
# workloads scraped by the same Prometheus.

resource "kubernetes_manifest" "prometheusrule_ecommerce" {
  count = local.deploy_observability ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "${var.env}-ecommerce-app-rules"
      namespace = local.monitoring_namespace
      labels = {
        release                     = var.release_label
        "app.kubernetes.io/part-of" = "ecommerce"
      }
    }
    spec = {
      groups = [
        {
          name     = "ecommerce.recording"
          interval = "30s"
          rules = [
            {
              record = "ecommerce:http_request_rate:5m"
              expr   = "sum by (service) (rate(http_requests_total{namespace=\"${local.ecommerce_namespace}\"}[5m]))"
            },
            {
              record = "ecommerce:http_error_rate:5m"
              expr   = "(sum by (service) (rate(http_requests_total{namespace=\"${local.ecommerce_namespace}\",status=~\"5..\"}[5m])) or sum by (service) (rate(http_requests_total{namespace=\"${local.ecommerce_namespace}\",status_code=~\"5..\"}[5m]))) / sum by (service) (rate(http_requests_total{namespace=\"${local.ecommerce_namespace}\"}[5m]))"
            },
            {
              record = "ecommerce:http_latency_p95:5m"
              expr   = "histogram_quantile(0.95, sum by (le, service) (rate(http_request_duration_seconds_bucket{namespace=\"${local.ecommerce_namespace}\"}[5m])))"
            },
          ]
        },
        {
          name     = "ecommerce.service-health"
          interval = "30s"
          rules = [
            {
              alert = "EcommerceServiceDown"
              expr  = "up{namespace=\"${local.ecommerce_namespace}\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "Service {{ $labels.service }} is down"
                description = "Pod {{ $labels.pod }} of {{ $labels.service }} has been unreachable for 2m."
              }
            },
            {
              alert = "EcommerceHighErrorRate"
              expr  = "ecommerce:http_error_rate:5m > 0.05"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "High 5xx rate on {{ $labels.service }}"
                description = "{{ $labels.service }} is returning 5xx for {{ $value | humanizePercentage }} of requests (threshold 5%)."
              }
            },
            {
              alert = "EcommerceHighLatency"
              expr  = "ecommerce:http_latency_p95:5m > 1"
              for   = "10m"
              labels = {
                severity = "warning"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "p95 latency on {{ $labels.service }} above 1s"
                description = "{{ $labels.service }} p95 request latency is {{ $value }}s for 10m."
              }
            },
            {
              alert = "EcommercePodCrashLooping"
              expr  = "increase(kube_pod_container_status_restarts_total{namespace=\"${local.ecommerce_namespace}\"}[15m]) > 3"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "Pod {{ $labels.pod }} restarting"
                description = "{{ $labels.pod }} in {{ $labels.namespace }} restarted >3 times in the last 15m."
              }
            },
          ]
        },
        {
          name     = "ecommerce.business"
          interval = "1m"
          rules = [
            {
              alert = "EcommerceHighPaymentFailureRate"
              expr  = "sum(rate(payments_processed_total{status=\"failed\",namespace=\"${local.ecommerce_namespace}\"}[5m])) / sum(rate(payments_processed_total{namespace=\"${local.ecommerce_namespace}\"}[5m])) > 0.1"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "Payment failure rate above 10%"
                description = "Current failure rate {{ $value | humanizePercentage }}."
              }
            },
            {
              alert = "EcommerceNoPaymentsProcessed"
              expr  = "sum(rate(payments_processed_total{namespace=\"${local.ecommerce_namespace}\"}[10m])) == 0"
              for   = "15m"
              labels = {
                severity = "info"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "No payments in 15m"
                description = "payment-service has processed zero payments in the last 15 minutes."
              }
            },
          ]
        },
        {
          name     = "ecommerce.dependencies"
          interval = "30s"
          rules = [
            {
              alert = "EcommerceRabbitMQDown"
              expr  = "kube_pod_status_ready{namespace=\"${local.ecommerce_namespace}\",pod=~\"rabbitmq-.*\",condition=\"true\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "RabbitMQ pod not ready"
                description = "RabbitMQ pod {{ $labels.pod }} has been NotReady for 2m."
              }
            },
            {
              alert = "EcommerceRedisDown"
              expr  = "kube_pod_status_ready{namespace=\"${local.ecommerce_namespace}\",pod=~\"redis-.*\",condition=\"true\"} == 0"
              for   = "2m"
              labels = {
                severity = "critical"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "Redis pod not ready"
                description = "Redis pod {{ $labels.pod }} has been NotReady for 2m."
              }
            },
            {
              alert = "EcommerceCNPGClusterUnhealthy"
              expr  = "cnpg_pg_replication_streaming_replicas{namespace=\"${local.ecommerce_namespace}\"} < 0"
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "ecommerce"
              }
              annotations = {
                summary     = "CNPG cluster {{ $labels.cluster }} unhealthy"
                description = "Postgres cluster reports replication issues."
              }
            },
          ]
        },
      ]
    }
  }
}

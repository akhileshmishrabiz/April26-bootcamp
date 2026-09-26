# Prometheus scrape config for every microservice.
#
# PodMonitor (not ServiceMonitor) because the chart's Services use unnamed
# ports — PodMonitor scrapes pods by container targetPort directly.
#
# The `release` label is what the Prometheus instance from kube-prometheus-stack
# matches on via `podMonitorSelector`. The instance accepts an empty selector
# in our install (see eks/k8s-services/logging-monitoring/main.tf), so this label
# is belt-and-braces for if the selector is tightened later.

resource "kubernetes_manifest" "podmonitor" {
  for_each = local.deploy_observability ? var.services : {}

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "${var.env}-${each.key}"
      namespace = local.monitoring_namespace
      labels = {
        release                      = var.release_label
        "app.kubernetes.io/part-of"  = "ecommerce"
        "app.kubernetes.io/instance" = each.key
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = [local.ecommerce_namespace]
      }
      selector = {
        matchLabels = {
          app = each.key
        }
      }
      podMetricsEndpoints = [
        {
          targetPort = each.value.port
          path       = each.value.metrics_path
          interval   = "15s"
          # Drop high-cardinality Go runtime metrics if a service emits them.
          metricRelabelings = [
            {
              sourceLabels = ["__name__"]
              regex        = "go_gc_duration_seconds.*"
              action       = "drop"
            },
          ]
          # Promote the service name into a stable label.
          relabelings = [
            {
              sourceLabels = ["__meta_kubernetes_pod_label_app"]
              targetLabel  = "service"
            },
            {
              sourceLabels = ["__meta_kubernetes_namespace"]
              targetLabel  = "namespace"
            },
          ]
        },
      ]
    }
  }
}

# api-gateway (nginx) exposes metrics via the stub_status / prometheus-nginx
# exporter pattern; scrape it the same way. If nginx isn't compiled with
# vts/stub_status, this monitor will simply produce `up{}=0` until the image
# is updated — useful as a probe in either case.
resource "kubernetes_manifest" "podmonitor_api_gateway" {
  count = local.deploy_observability ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "${var.env}-api-gateway"
      namespace = local.monitoring_namespace
      labels = {
        release                      = var.release_label
        "app.kubernetes.io/part-of"  = "ecommerce"
        "app.kubernetes.io/instance" = "api-gateway"
      }
    }
    spec = {
      namespaceSelector = {
        matchNames = [local.ecommerce_namespace]
      }
      selector = {
        matchLabels = {
          app = "api-gateway"
        }
      }
      podMetricsEndpoints = [
        {
          targetPort = 80
          path       = "/metrics"
          interval   = "30s"
          relabelings = [
            {
              sourceLabels = ["__meta_kubernetes_pod_label_app"]
              targetLabel  = "service"
            },
          ]
        },
      ]
    }
  }
}

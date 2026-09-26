#!/usr/bin/env python3
"""Generate operational Grafana dashboards for ecommerce microservices and databases."""

import json
from pathlib import Path

OUT = Path(__file__).parent
PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
NS = "ecommerce"

SERVICES = [
    "product-service",
    "user-service",
    "cart-service",
    "order-service",
    "payment-service",
    "notification-service",
    "api-gateway",
]

DB_CLUSTERS = ["products", "users", "orders", "payments"]


def base(title, uid, tags, description=""):
    return {
        "annotations": {"list": []},
        "description": description,
        "editable": True,
        "graphTooltip": 1,
        "refresh": "30s",
        "schemaVersion": 38,
        "style": "dark",
        "tags": tags,
        "templating": {"list": []},
        "time": {"from": "now-1h", "to": "now"},
        "timepicker": {},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 1,
        "panels": [],
    }


def service_var():
    return {
        "current": {"selected": False, "text": "All", "value": "$__all"},
        "datasource": PROM,
        "definition": f'label_values(up{{namespace="{NS}"}}, service)',
        "hide": 0,
        "includeAll": True,
        "label": "service",
        "multi": True,
        "name": "service",
        "options": [],
        "query": {"query": f'label_values(up{{namespace="{NS}"}}, service)', "refId": "A"},
        "refresh": 2,
        "regex": "",
        "skipUrlSync": False,
        "sort": 1,
        "type": "query",
    }


def stat(title, expr, x, y, w=6, h=4, unit="short", thresholds=None, mappings=None):
    fc = {"defaults": {"unit": unit, "decimals": 2}}
    if thresholds:
        fc["defaults"]["thresholds"] = thresholds
    if mappings:
        fc["defaults"]["mappings"] = mappings
    return {
        "type": "stat",
        "title": title,
        "datasource": PROM,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "fieldConfig": fc,
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "colorMode": "value"},
        "targets": [{"expr": expr, "legendFormat": title, "refId": "A"}],
    }


def timeseries(title, expr, x, y, w=12, h=8, unit="short", legend="{{service}}"):
    return {
        "type": "timeseries",
        "title": title,
        "datasource": PROM,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "custom": {"drawStyle": "line", "fillOpacity": 10, "lineInterpolation": "smooth"},
            }
        },
        "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max"]}},
        "targets": [{"expr": expr, "legendFormat": legend, "refId": "A"}],
    }


def table(title, expr, x, y, w=24, h=8):
    return {
        "type": "table",
        "title": title,
        "datasource": PROM,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "fieldConfig": {"defaults": {"custom": {"align": "auto"}}},
        "options": {"showHeader": True, "sortBy": [{"desc": True, "displayName": "Value"}]},
        "targets": [{"expr": expr, "legendFormat": "", "refId": "A", "format": "table", "instant": True}],
    }


def build_microservices():
    d = base(
        "Ecommerce — All Microservices",
        "ecommerce-microservices",
        ["ecommerce", "microservices", "operations"],
        "Operational view of all ecommerce microservices: health, RED metrics, and business counters.",
    )
    d["templating"]["list"] = [service_var()]

    up_mapping = {
        "mappings": [
            {
                "options": {"0": {"color": "red", "text": "DOWN"}, "1": {"color": "green", "text": "UP"}},
                "type": "value",
            }
        ],
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
    }

    panels = [
        stat(
            "Services Up",
            f'sum(up{{namespace="{NS}",service=~"$service"}})',
            0, 0,
            thresholds=up_mapping["thresholds"],
            mappings=up_mapping["mappings"],
        ),
        stat("Total req/s", f'sum(ecommerce:http_request_rate:5m{{service=~"$service"}})', 6, 0, unit="reqps"),
        stat(
            "Avg error rate",
            f'avg(ecommerce:http_error_rate:5m{{service=~"$service"}})',
            12, 0,
            unit="percentunit",
            thresholds={
                "mode": "absolute",
                "steps": [
                    {"color": "green", "value": None},
                    {"color": "yellow", "value": 0.01},
                    {"color": "red", "value": 0.05},
                ],
            },
        ),
        stat(
            "Max p95 latency",
            f'max(ecommerce:http_latency_p95:5m{{service=~"$service"}})',
            18, 0,
            unit="s",
            thresholds={
                "mode": "absolute",
                "steps": [
                    {"color": "green", "value": None},
                    {"color": "yellow", "value": 0.5},
                    {"color": "red", "value": 1},
                ],
            },
        ),
        table(
            "Service health matrix",
            f'up{{namespace="{NS}",service=~"$service"}}',
            0, 4, h=6,
        ),
        timeseries("Request rate by service", f'ecommerce:http_request_rate:5m{{service=~"$service"}}', 0, 10),
        timeseries("Error rate by service", f'ecommerce:http_error_rate:5m{{service=~"$service"}}', 12, 10, unit="percentunit"),
        timeseries("Latency p95 by service", f'ecommerce:http_latency_p95:5m{{service=~"$service"}}', 0, 18, unit="s"),
        timeseries(
            "In-flight requests",
            f'sum by (service) (http_requests_in_flight{{namespace="{NS}",service=~"$service"}})',
            12, 18,
        ),
    ]

    y = 26
    for svc in SERVICES:
        panels.extend([
            stat(f"{svc} — up", f'up{{namespace="{NS}",service="{svc}"}}', 0, y, w=4, mappings=up_mapping["mappings"], thresholds=up_mapping["thresholds"]),
            stat(f"{svc} — req/s", f'ecommerce:http_request_rate:5m{{service="{svc}"}}', 4, y, w=4, unit="reqps"),
            stat(f"{svc} — errors", f'ecommerce:http_error_rate:5m{{service="{svc}"}}', 8, y, w=4, unit="percentunit"),
            stat(f"{svc} — p95", f'ecommerce:http_latency_p95:5m{{service="{svc}"}}', 12, y, w=4, unit="s"),
            stat(
                f"{svc} — restarts",
                f'increase(kube_pod_container_status_restarts_total{{namespace="{NS}",pod=~"{svc}-.*"}}[15m])',
                16, y, w=4,
            ),
            stat(
                f"{svc} — CPU",
                f'sum(rate(container_cpu_usage_seconds_total{{namespace="{NS}",pod=~"{svc}-.*",container!="",container!="POD"}}[5m]))',
                20, y, w=4,
            ),
        ])
        y += 4

    d["panels"] = panels
    return d


def build_databases():
    d = base(
        "Ecommerce — Databases & Dependencies",
        "ecommerce-databases",
        ["ecommerce", "databases", "dependencies"],
        "Postgres (CNPG), Redis, RabbitMQ health plus app-level database metrics.",
    )

    ready_mapping = {
        "mappings": [
            {
                "options": {"0": {"color": "red", "text": "NOT READY"}, "1": {"color": "green", "text": "READY"}},
                "type": "value",
            }
        ],
        "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": None}, {"color": "green", "value": 1}]},
    }

    d["panels"] = [
        stat(
            "Redis ready",
            f'kube_pod_status_ready{{namespace="{NS}",pod=~"redis-.*",condition="true"}}',
            0, 0,
            mappings=ready_mapping["mappings"],
            thresholds=ready_mapping["thresholds"],
        ),
        stat(
            "RabbitMQ ready",
            f'kube_pod_status_ready{{namespace="{NS}",pod=~"rabbitmq-.*",condition="true"}}',
            6, 0,
            mappings=ready_mapping["mappings"],
            thresholds=ready_mapping["thresholds"],
        ),
        stat(
            "CNPG collectors up",
            f'count(cnpg_collector_up{{namespace="{NS}"}} == 1) or vector(0)',
            12, 0,
        ),
        stat(
            "Active DB connections",
            f'sum(database_connections_active{{namespace="{NS}"}}) or vector(0)',
            18, 0,
        ),
        timeseries(
            "CNPG collector status per cluster",
            f'cnpg_collector_up{{namespace="{NS}"}}',
            0, 4, w=12, legend="{{cluster}}",
        ),
        timeseries(
            "CNPG streaming replicas",
            f'cnpg_pg_replication_streaming_replicas{{namespace="{NS}"}}',
            12, 4, w=12, legend="{{cluster}}",
        ),
        timeseries(
            "Redis / RabbitMQ pod restarts (15m)",
            f'increase(kube_pod_container_status_restarts_total{{namespace="{NS}",pod=~"redis-.*|rabbitmq-.*"}}[15m])',
            0, 12, legend="{{pod}}",
        ),
        timeseries(
            "Redis / RabbitMQ CPU",
            f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="{NS}",pod=~"redis-.*|rabbitmq-.*",container!="",container!="POD"}}[5m]))',
            12, 12, legend="{{pod}}",
        ),
        timeseries(
            "DB query latency p95 by service",
            f'histogram_quantile(0.95, sum by (le, service) (rate(database_query_duration_seconds_bucket{{namespace="{NS}"}}[5m])))',
            0, 20, unit="s", legend="{{service}}",
        ),
        timeseries(
            "Active DB connections by service",
            f'database_connections_active{{namespace="{NS}"}}',
            12, 20, legend="{{service}}",
        ),
        timeseries(
            "Postgres pod CPU (CNPG)",
            f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="{NS}",pod=~"products-.*|users-.*|orders-.*|payments-.*",container!="",container!="POD"}}[5m]))',
            0, 28, legend="{{pod}}",
        ),
        timeseries(
            "Postgres pod memory MiB (CNPG)",
            f'sum by (pod) (container_memory_rss{{namespace="{NS}",pod=~"products-.*|users-.*|orders-.*|payments-.*",container!="",container!="POD"}}) / 1024 / 1024',
            12, 28, unit="decmbytes", legend="{{pod}}",
        ),
        table(
            "CNPG cluster health",
            f'cnpg_collector_up{{namespace="{NS}"}}',
            0, 36, h=6,
        ),
    ]
    return d


def build_business():
    d = base(
        "Ecommerce — Business Metrics",
        "ecommerce-business",
        ["ecommerce", "business", "operations"],
        "Orders, payments, and product query metrics across all microservices.",
    )

    d["panels"] = [
        stat("Orders / min", f'sum(rate(orders_created_total{{namespace="{NS}"}}[5m])) * 60', 0, 0),
        stat("Completed / min", f'sum(rate(orders_completed_total{{namespace="{NS}"}}[5m])) * 60', 6, 0),
        stat("Cancelled / min", f'sum(rate(orders_cancelled_total{{namespace="{NS}"}}[5m])) * 60', 12, 0),
        stat(
            "Payment success rate",
            f'''sum(rate(payments_processed_total{{namespace="{NS}",status="success"}}[5m]))
/ sum(rate(payments_processed_total{{namespace="{NS}"}}[5m]))''',
            18, 0, unit="percentunit",
        ),
        timeseries("Orders — created vs completed vs cancelled", f'sum(rate(orders_created_total{{namespace="{NS}"}}[5m]))', 0, 4, w=8, legend="created"),
        timeseries("", f'sum(rate(orders_completed_total{{namespace="{NS}"}}[5m]))', 8, 4, w=8, legend="completed"),
        timeseries("", f'sum(rate(orders_cancelled_total{{namespace="{NS}"}}[5m]))', 16, 4, w=8, legend="cancelled"),
        timeseries("Payments by status", f'sum by (status) (rate(payments_processed_total{{namespace="{NS}"}}[5m]))', 0, 12, legend="{{status}}"),
        timeseries(
            "Payment processing p95",
            f'histogram_quantile(0.95, sum by (le) (rate(payment_processing_duration_seconds_bucket{{namespace="{NS}"}}[5m])))',
            12, 12, unit="s",
        ),
        timeseries("Product queries by type", f'sum by (query_type) (rate(product_queries_total{{namespace="{NS}"}}[5m]))', 0, 20, legend="{{query_type}}"),
        timeseries("User registrations / min", f'sum(rate(users_registered_total{{namespace="{NS}"}}[5m])) * 60', 12, 20),
        timeseries("User logins by status", f'sum by (status) (rate(user_logins_total{{namespace="{NS}"}}[5m]))', 0, 28, legend="{{status}}"),
        timeseries("Order value rate", f'sum(rate(order_value_total{{namespace="{NS}"}}[5m]))', 12, 28),
    ]
    d["panels"][4]["title"] = "Orders created rate"
    d["panels"][5]["title"] = "Orders completed rate"
    d["panels"][6]["title"] = "Orders cancelled rate"
    return d


DASHBOARDS = [
    ("ecommerce-microservices.json", build_microservices),
    ("ecommerce-databases.json", build_databases),
    ("ecommerce-business.json", build_business),
]


def main():
    for filename, builder in DASHBOARDS:
        path = OUT / filename
        path.write_text(json.dumps(builder(), indent=2) + "\n")
        print(f"wrote {path.name}")


if __name__ == "__main__":
    main()

import json
import os
import sys
import time

METRIC_NAMESPACE = os.getenv(
    "CLOUDWATCH_METRIC_NAMESPACE",
    f"{os.getenv('ENVIRONMENT', 'dev')}/devopsdojo/Backend",
)


def _emit_emf(metrics, dimensions, values):
    """Emit a CloudWatch Embedded Metric Format (EMF) log line to stdout.

    ECS ships stdout to CloudWatch Logs via the awslogs driver; EMF lines are
    automatically parsed into custom metrics in the configured namespace.
    """
    dimension_keys = list(dimensions.keys())
    payload = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": METRIC_NAMESPACE,
                    "Dimensions": [dimension_keys],
                    "Metrics": metrics,
                }
            ],
        },
        **dimensions,
        **values,
    }
    print(json.dumps(payload), file=sys.stdout, flush=True)


def emit_request_metrics(method, endpoint, status, duration_ms):
    status_class = f"{status // 100}xx"
    duration = round(duration_ms, 2)

    _emit_emf(
        metrics=[
            {"Name": "RequestDuration", "Unit": "Milliseconds"},
            {"Name": "HttpRequestCount", "Unit": "Count"},
        ],
        dimensions={
            "Method": method,
            "Endpoint": endpoint,
            "StatusClass": status_class,
        },
        values={
            "RequestDuration": duration,
            "HttpRequestCount": 1,
        },
    )

    # Single-dimension aggregate used by CloudWatch latency alarms.
    _emit_emf(
        metrics=[{"Name": "RequestDurationOverall", "Unit": "Milliseconds"}],
        dimensions={"Service": "backend"},
        values={"RequestDurationOverall": duration},
    )


def emit_quiz_submission(topic, passed):
    _emit_emf(
        metrics=[{"Name": "QuizSubmissionCount", "Unit": "Count"}],
        dimensions={
            "Topic": topic,
            "Result": "pass" if passed else "fail",
        },
        values={"QuizSubmissionCount": 1},
    )


def emit_health_check_failure():
    _emit_emf(
        metrics=[{"Name": "HealthCheckFailure", "Unit": "Count"}],
        dimensions={"Check": "database"},
        values={"HealthCheckFailure": 1},
    )

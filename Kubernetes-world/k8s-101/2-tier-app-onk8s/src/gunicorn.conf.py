import os

# Sized for ~20 concurrent users on a small VM (1 worker keeps RAM low;
# gthread handles I/O-bound Flask + Postgres work).
bind = os.getenv("GUNICORN_BIND", "0.0.0.0:8000")
workers = int(os.getenv("GUNICORN_WORKERS", "1"))
threads = int(os.getenv("GUNICORN_THREADS", "8"))
worker_class = os.getenv("GUNICORN_WORKER_CLASS", "gthread")
timeout = int(os.getenv("GUNICORN_TIMEOUT", "60"))
keepalive = int(os.getenv("GUNICORN_KEEPALIVE", "5"))
backlog = int(os.getenv("GUNICORN_BACKLOG", "64"))
max_requests = int(os.getenv("GUNICORN_MAX_REQUESTS", "2000"))
max_requests_jitter = int(os.getenv("GUNICORN_MAX_REQUESTS_JITTER", "200"))
preload_app = os.getenv("GUNICORN_PRELOAD", "true").lower() in ("1", "true", "yes")

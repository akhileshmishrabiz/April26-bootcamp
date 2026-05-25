#!/usr/bin/env bash
set -euo pipefail
exec gunicorn --bind 0.0.0.0:8000 run:app

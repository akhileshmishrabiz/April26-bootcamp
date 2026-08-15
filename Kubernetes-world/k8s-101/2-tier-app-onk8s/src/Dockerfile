# Alpine-based runtime: smaller attack surface, fewer Debian perl/ncurses packages.
FROM python:3.13-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev libpq-dev

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_APP=app.py \
    FLASK_RUN_PORT=8000

RUN apk add --no-cache libpq ca-certificates && \
    apk upgrade --no-cache && \
    rm -rf /var/cache/apk/* /tmp/*

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . /app

RUN adduser -D -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

CMD ["gunicorn", "-c", "gunicorn.conf.py", "run:app"]

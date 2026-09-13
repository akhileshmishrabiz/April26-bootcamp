# First Exercise: Run the E-Commerce Microservices Stack

Practical setup guide — test locally with Docker Compose first, then deploy to a local Kind cluster.

---

## Step A: Docker Compose (local)

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose plugin)
- `docker compose version` should work (Compose V2)

### Build and run

From the `microservices/` directory:

```bash
cd microservices
docker compose up -d --build
```

First run takes several minutes while images build. Subsequent starts are faster if images are cached.

### What gets started

| Layer | Services |
|-------|----------|
| **Databases** | `postgres-products`, `postgres-users`, `postgres-orders`, `postgres-payments` |
| **Cache / queue** | `redis`, `rabbitmq` (management UI on port 15672) |
| **Microservices** | `product-service` (8001), `user-service` (8002), `cart-service` (8003), `order-service` (8004), `payment-service` (8005), `notification-service` (8006) |
| **Gateway** | `api-gateway` (nginx:alpine, port 8080) |
| **Seed job** | `seed-job` — one-shot container; waits for the API gateway, then POSTs 15 products |
| **Frontend** | `frontend` — starts **after** `seed-job` completes successfully |

Startup order (simplified):

```
postgres/redis/rabbitmq → microservices → api-gateway → seed-job → frontend
```

### Access URLs

| What | URL |
|------|-----|
| Frontend (shop) | http://localhost:3000 |
| API gateway | http://localhost:8080 |
| Ops dashboard | http://localhost:3000/dashboard |
| RabbitMQ UI | http://localhost:15672 (guest / guest) |

The frontend proxies `/api/*` to the gateway. In Compose, the gateway routes to backend containers by Docker service name.

### Verify

**1. Check containers are up**

```bash
docker compose ps
```

**2. Health checks via gateway**

```bash
curl -s http://localhost:8080/health

for svc in product-service user-service cart-service order-service payment-service notification-service; do
  echo -n "$svc: "
  curl -s "http://localhost:8080/api/health/$svc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','OK'))" 2>/dev/null || echo "UNREACHABLE"
done
```

**3. Confirm 15 seeded products**

```bash
curl -s http://localhost:8080/api/products | python3 -c "import sys,json; print('total:', json.load(sys.stdin).get('total', 0))"
```

Expected output: `total: 15`

**4. Browse the shop**

Open http://localhost:3000 — product cards should load.

### Known notes

- **Demo users are not auto-seeded.** The seed job loads products only. Either:
  - Register at http://localhost:3000/register, or
  - Run the user-service seed manually: `docker compose exec user-service npm run seed`
- **Payment / notification optional env vars** — services start without real credentials; payments and emails will fail until configured. Create a `.env` file in `microservices/` (or export vars) for:
  - `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`
  - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `SES_SENDER_EMAIL`, `SES_SENDER_NAME`
- **Manual re-seed** (if needed): `./seed-data.sh` from `microservices/` (targets `http://localhost:8080`).

### Tear down

```bash
# Stop containers, keep volumes (database data persists)
docker compose down

# Stop containers AND delete volumes (fresh databases next run)
docker compose down -v
```

---

## Step B: Kind cluster + Kubernetes

### Prerequisites

- [kind](https://kind.sigs.k8s.io/) — `kind version`
- [kubectl](https://kubernetes.io/docs/tasks/tools/) — `kubectl version --client`
- Docker (same daemon kind uses to load images)

See also: [docs/devops-guide.md](docs/devops-guide.md) for architecture, debugging, and production-oriented notes.

### 1. Create a Kind cluster

Pick a cluster name and **use it consistently** for `kind load` and `kubectl`:

```bash
# Example — name the cluster "ecommerce"
kind create cluster --name ecommerce

# Confirm kubectl points at the SAME cluster you will load images into
kubectl config current-context
# Expected: kind-ecommerce
```

> **Common pitfall:** Loading images into `kind-ecommerce` while `kubectl` context is `kind-test` (or default `kind`) causes `ImagePullBackOff`. Always match cluster name ↔ context.

To use a different name (e.g. `test`):

```bash
kind create cluster --name test
kubectl config use-context kind-test
```

### 2. Build Docker images

From `microservices/`:

```bash
docker compose build
```

Compose tags built services as `microservices-<service>:latest` (project name `microservices` + service name). Examples:

| Service | Image tag |
|---------|-----------|
| product-service | `microservices-product-service:latest` |
| user-service | `microservices-user-service:latest` |
| cart-service | `microservices-cart-service:latest` |
| order-service | `microservices-order-service:latest` |
| payment-service | `microservices-payment-service:latest` |
| notification-service | `microservices-notification-service:latest` |
| frontend | `microservices-frontend:latest` |
| seed-job | `microservices-seed-job:latest` |

**Not built locally:** `api-gateway` uses public `nginx:alpine` plus a ConfigMap for routing (including `/api/health/*` dashboard routes).

### 3. Load images into Kind

Replace `ecommerce` with your cluster name:

```bash
CLUSTER=ecommerce

for img in \
  microservices-product-service:latest \
  microservices-user-service:latest \
  microservices-cart-service:latest \
  microservices-order-service:latest \
  microservices-payment-service:latest \
  microservices-notification-service:latest \
  microservices-frontend:latest \
  microservices-seed-job:latest
do
  kind load docker-image "$img" --name "$CLUSTER"
done
```

Verify images are present inside the cluster node:

```bash
docker exec "${CLUSTER}-control-plane" crictl images | grep microservices
```

### 4. Apply Kubernetes manifests (in order)

From `microservices/`:

```bash
kubectl apply -f k8s/deploy/namespace.yaml
kubectl apply -f k8s/deploy/secrets.yaml
kubectl apply -f k8s/deploy/infrastructure.yaml   # postgres, redis, rabbitmq
kubectl apply -f k8s/deploy/services.yaml           # microservices, api-gateway ConfigMap, frontend
```

Wait for infrastructure and app pods:

```bash
kubectl get pods -n ecommerce -w
```

### 5. Seed data

If `apps/seed-job/seed-job.yaml` is present:

```bash
kubectl apply -f apps/seed-job/seed-job.yaml
kubectl wait --for=condition=complete job/seed-job -n ecommerce --timeout=300s
kubectl logs job/seed-job -n ecommerce
```

Otherwise, run the host seed script against the NodePort gateway:

```bash
API_URL=http://localhost:30080 ./seed-data.sh
```

### 6. Verify pods and data

```bash
kubectl get pods -n ecommerce
kubectl get svc -n ecommerce
```

Health checks (via NodePort gateway):

```bash
curl -s http://localhost:30080/health

for svc in product-service user-service cart-service order-service payment-service notification-service; do
  echo -n "$svc: "
  curl -s "http://localhost:30080/api/health/$svc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','OK'))" 2>/dev/null || echo "UNREACHABLE"
done

curl -s http://localhost:30080/api/products | python3 -c "import sys,json; print('total:', json.load(sys.stdin).get('total', 0))"
```

### 7. Access via NodePorts

| What | URL |
|------|-----|
| Frontend | http://localhost:30000 |
| API gateway | http://localhost:30080 |
| Dashboard | http://localhost:30000/dashboard |

Kind maps NodePort services on the control-plane container to localhost, so `30000` and `30080` work without extra port-mapping config on macOS/Linux.

### Image naming reference

- Compose-built images: `microservices-*:latest` — must match `image:` fields in `k8s/deploy/services.yaml`.
- Frontend image is **`microservices-frontend:latest`** (not `frontend:local`).
- API gateway: **`nginx:alpine`** + ConfigMap `api-gateway-config` (not a custom built image).

Manifests use `imagePullPolicy: IfNotPresent` — the kubelet uses locally loaded images when present.

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `ImagePullBackOff` | Image not loaded into the cluster node | Re-run `kind load docker-image ... --name <cluster>`; confirm `kubectl config current-context` matches |
| `ErrImageNeverPull` | Old manifest with `imagePullPolicy: Never` and missing local image | Re-apply `k8s/deploy/services.yaml` (current manifests use `IfNotPresent`) and reload images |
| Pods `CrashLoopBackOff` | DB not ready yet | Wait for postgres/redis/rabbitmq pods; check `kubectl logs deploy/<service> -n ecommerce` |
| Frontend up but no products | Seed job not run or failed | Apply/wait for seed job or run `./seed-data.sh` with `API_URL=http://localhost:30080` |
| Dashboard health checks fail | Gateway ConfigMap missing `/api/health/*` routes | Re-apply `k8s/deploy/services.yaml` (ConfigMap is at the top of the file) |
| Wrong cluster | Loaded images into `kind-test`, deploying to `kind-ecommerce` | `kind get clusters` and `kubectl config get-contexts`; align names |

Useful debug commands:

```bash
kubectl describe pod <pod-name> -n ecommerce
kubectl logs deploy/product-service -n ecommerce
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | tail -20
```

### Clean up Kind cluster

```bash
kind delete cluster --name ecommerce
```

---

## Quick reference

```bash
# Local
cd microservices && docker compose up -d --build
open http://localhost:3000

# Kubernetes
kind create cluster --name ecommerce
cd microservices && docker compose build
# load images (loop above)
kubectl apply -f k8s/deploy/namespace.yaml
kubectl apply -f k8s/deploy/secrets.yaml
kubectl apply -f k8s/deploy/infrastructure.yaml
kubectl apply -f k8s/deploy/services.yaml
open http://localhost:30000
```

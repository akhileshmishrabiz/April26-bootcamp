# Linkerd mesh policies for ecommerce

Service mesh authorization uses **Kubernetes ServiceAccounts** as Linkerd identities.
Each workload in the Helm chart runs under a dedicated SA (see `ecommerce/templates/serviceaccounts.yaml`).

## ServiceAccount → workload mapping

| ServiceAccount | Workload | Meshed | Notes |
|----------------|----------|--------|-------|
| `api-gateway` | api-gateway Deployment | yes | North-south entry; calls all HTTP microservices |
| `frontend` | frontend Deployment | yes | Static UI; calls api-gateway via NodePort |
| `product-service` | product-service Deployment | yes | HTTP :8001; CNPG `products` cluster |
| `user-service` | user-service Deployment | yes | HTTP :8002; CNPG `users` cluster |
| `cart-service` | cart-service Deployment | yes | HTTP :8003; Redis :6379 (skip ports) |
| `order-service` | order-service Deployment | yes | HTTP :8004; RabbitMQ :5672; calls cart/product |
| `payment-service` | payment-service Deployment | yes | HTTP :8005; calls order-service |
| `notification-service` | notification-service Deployment | yes | HTTP :8006; RabbitMQ + Mailpit SMTP |
| `redis` | redis Deployment | yes | Inbound :6379 skipped (plain TCP) |
| `rabbitmq` | rabbitmq StatefulSet | yes | AMQP :5672 with SA auth |
| `mailpit` | mailpit Deployment | yes | SMTP :1025; notification-service only |
| `seed-data-job` | seed Job | no | Own SA; allow-seed-job NetworkPolicy |

CNPG Postgres pods (`products`, `users`, `orders`, `payments`) use `linkerd.io/inject: disabled`.

## Policy files

| File | Purpose |
|------|---------|
| `namespace-annotation.yaml` | Enable injection on `ecommerce` namespace |
| `cnpg-skip-injection.yaml` | Disable injection on CNPG clusters |
| `redis-skip-ports.yaml` | Skip proxy on Redis TCP :6379 |
| `server-authorization/servers.yaml` | Server CRs (ports 8001-8006, 5672, 1025) |
| `server-authorization/meshed-auth.yaml` | MeshTLSAuthentication — allowed caller ServiceAccounts per Server |
| `server-authorization/authorization-policies.strict.yaml` | AuthorizationPolicy — one MTLS auth ref per Server (Linkerd limit) |
| `retry-timeout/service-profiles.yaml` | ServiceProfile — 30s timeouts, retry budget, retries on 502/503/504 |

## Retry and timeout policies

Linkerd 2.14 configures **retries on the outbound (client) proxy** via `ServiceProfile` (HTTPRoute retries are not yet available in 2.14). Each profile is named after the destination Service FQDN, e.g. `user-service.ecommerce.svc.cluster.local`.

| Destination | Callers (typical) | Timeout | Retries |
|-------------|-------------------|---------|---------|
| `product-service` | api-gateway, cart, order, user, payment, notification | 30s | 502/503/504 + budget |
| `user-service` | api-gateway, cart, order, payment, notification | 30s | 502/503/504 + budget |
| `cart-service` | api-gateway, order | 30s | 502/503/504 + budget |
| `order-service` | api-gateway, payment | 30s | 502/503/504 + budget |
| `payment-service` | api-gateway | 30s | 502/503/504 + budget |
| `notification-service` | api-gateway (health) | 30s | 502/503/504 + budget |
| `api-gateway` | frontend | 30s | 502/503/504 + budget |

Retry budget defaults: `retryRatio: 0.2`, `minRetriesPerSecond: 10`, `ttl: 10s` (max ~20% extra load from retries).

## Apply

```bash
./install-linkerd.sh
# or mesh policies only:
kubectl apply -f mesh/namespace-annotation.yaml
kubectl apply -f mesh/cnpg-skip-injection.yaml
kubectl apply -f mesh/redis-skip-ports.yaml
kubectl apply -f mesh/server-authorization/
kubectl apply -f mesh/retry-timeout/service-profiles.yaml
```

## Verify

```bash
linkerd check
linkerd viz stat deploy -n ecommerce
linkerd viz tap deploy/product-service -n ecommerce
kubectl get authorizationpolicy,meshtlsauthentication,server -n ecommerce
kubectl get serviceprofile -n ecommerce
linkerd viz routes deploy/api-gateway -n ecommerce --to svc/user-service --to svc/order-service --to svc/payment-service -o wide
```

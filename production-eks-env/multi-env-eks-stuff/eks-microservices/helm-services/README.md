# E-commerce Services Helm Chart

Helm chart deploying **microservice workloads only** to EKS. Database, cache, and message-broker infrastructure is provisioned separately by Terraform in `../infra/ms-ecom/databases.tf`.

Secrets are sourced from Kubernetes Secrets materialised by External Secrets Operator from Vault (`../infra/vault-secrets/`).

## What this chart deploys

| Resource | Purpose |
|----------|---------|
| 6× microservice `Deployment` + `Service` | product, user, cart, order, payment, notification |
| `Deployment api-gateway` | nginx fronting the 6 services |
| `Deployment frontend` | Static UI |
| `Ingress` | ALB ingress on the shared ALB group |
| `Job seed-data-job` | Post-install hook to seed product data |

## What this chart does NOT deploy

| Resource | Provisioned by |
|----------|--------------|
| 4× CNPG `Cluster` (products, users, orders, payments) | `infra/ms-ecom/databases.tf` |
| `Deployment redis` | `infra/ms-ecom/databases.tf` |
| `StatefulSet rabbitmq` | `infra/ms-ecom/databases.tf` |
| Vault / ESO / CNPG operator | Cluster-wide (`EKS/k8s-services/`) |

## Secrets consumed

Pods reference the same Kubernetes Secrets as before — no env var or secret ref changes:

| Secret | Keys used by services |
|--------|----------------------|
| `db-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| `redis-credentials` | `REDIS_PASSWORD` |
| `rabbitmq-credentials` | `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS` |
| `app-secrets` | `JWT_SECRET`, `RAZORPAY_*` |
| `aws-credentials` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

## Deploy order

See `../infra/README.md`. Summary:

1. CNPG operator (`EKS/k8s-services/cnpg.tf`)
2. **Namespace** (`infra/ms-ecom/` — `terraform apply -target=kubernetes_namespace_v1.ecommerce`)
3. Vault secrets + ExternalSecrets (`infra/vault-secrets/`)
4. **Databases** (`infra/ms-ecom/` — `terraform apply` provisions CNPG, Redis, RabbitMQ)
5. **This chart** via ArgoCD (`infra/ms-ecom/argocd-app.tf`) or `helm install`

## Install

```bash
helm template ecommerce-services . | less
helm install ecommerce-services . -n ecommerce
```

Namespace `ecommerce` is created by Terraform (`infra/ms-ecom/namespace.tf`), not this chart.

## Chart structure

```
helm-services/
├── Chart.yaml
├── values.yaml
├── README.md
└── templates/
    ├── _helpers.tpl
    ├── product-service.yaml
    ├── user-service.yaml
    ├── cart-service.yaml
    ├── order-service.yaml
    ├── payment-service.yaml
    ├── notification-service.yaml
    ├── api-gateway.yaml
    ├── frontend.yaml
    ├── ingress.yaml
    └── seed-job.yaml
```

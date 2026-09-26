# EKS cluster 

#Dev env
```bash
terraform init -backend-config=vars/dev.tfbackend
terraform apply -var-file=vars/dev.tfvars
``


#prod env
```bash
terraform init -backend-config=vars/prod.tfbackend
terraform apply -var-file=vars/prod.tfvars
``

# E-commerce Platform Infra

Terraform modules the ecommerce platform depends on. Apply them in order before deploying microservices.

```
infra/
├── vault-secrets/    # Generates random app creds, writes them to Vault, wires ESO ExternalSecrets
├── ms-ecom/          # Data stores (CNPG, Redis, RabbitMQ) + ArgoCD Application for services Helm chart
└── observability/    # PodMonitors + PrometheusRules + Grafana dashboards for the ecommerce apps
```

Vault server, ESO controller, and CNPG operator are cluster-wide — deployed from `EKS/k8s-services/`.

Microservice deployments are in `../helm-services/` and synced by ArgoCD (`ms-ecom/argocd-app.tf`).

---

## Deploy order

### 1. Cluster-wide prerequisites

- CNPG operator — `EKS/k8s-services/cnpg.tf`
- Vault + ESO controller — `EKS/k8s-services/vault-eso/`

### 2. Ecommerce namespace (ms-ecom)

```bash
cd infra/ms-ecom
terraform init
terraform apply -target=kubernetes_namespace_v1.ecommerce
```

Creates the `ecommerce` namespace used by vault-secrets, databases, ingress, and ArgoCD.

### 3. Vault secrets + ExternalSecrets

```bash
cd infra/vault-secrets
terraform init
terraform apply \
  -var vault_addr=http://localhost:8200 \
  -var vault_token=root \
  -var enable_eso_secrets=true
```

Creates ESO `ExternalSecret` resources that materialise these K8s secrets in the `ecommerce` namespace:

| Secret | Keys | Vault path |
|--------|------|------------|
| `db-credentials` | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `username`, `password` | `secret/ecommerce/database` |
| `redis-credentials` | `REDIS_PASSWORD` | `secret/ecommerce/redis` |
| `rabbitmq-credentials` | `RABBITMQ_DEFAULT_USER`, `RABBITMQ_DEFAULT_PASS` | `secret/ecommerce/rabbitmq` |
| `app-secrets` | `JWT_SECRET`, `RAZORPAY_*` | `secret/ecommerce/app` + `/razorpay` |
| `aws-credentials` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `secret/ecommerce/aws` |

### 4. Data stores + ArgoCD (ms-ecom)

```bash
cd infra/ms-ecom
terraform init
terraform apply
```

`databases.tf` provisions:

- 4× CNPG `Cluster` resources (`products`, `users`, `orders`, `payments`)
- `Deployment` + `Service` for Redis
- `StatefulSet` + `Service` for RabbitMQ

All credentials are read from the ESO-managed secrets above — no passwords in Terraform.

`argocd-app.tf` deploys the services-only Helm chart from `../helm-services/`.

### 5. Observability (optional)

```bash
cd infra/observability
terraform init
terraform apply
```

---

## Architecture split

| Layer | Tool | Location |
|-------|------|----------|
| Namespace | Terraform | `ms-ecom/namespace.tf` |
| Secrets (Vault → K8s) | Terraform + ESO | `vault-secrets/` |
| Databases / cache / broker | Terraform | `ms-ecom/databases.tf` |
| Microservices + ingress | Helm via ArgoCD | `helm-services/` |

The legacy umbrella chart at `../helm/` (DBs + services combined) is deprecated. Use `helm-services/` + `databases.tf` instead.

---

## Variables (vault-secrets)

| Variable | Default | Purpose |
|----------|---------|---------|
| `vault_addr` | `http://localhost:8200` | Vault URL terraform writes to |
| `vault_token` | `root` | Vault auth token |
| `enable_eso_secrets` | `true` | Create ClusterSecretStore + ExternalSecrets |
| `db_user` / `rabbitmq_user` | `ecommerce_user` / `rabbitmq` | Static usernames; passwords are random |

## Variables (ms-ecom databases)

| Variable | Default | Purpose |
|----------|---------|---------|
| `enable_databases` | `true` | Toggle all data store provisioning |
| `cnpg_databases` | products, users, orders, payments | CNPG cluster names |
| `storage_class` | `gp2` | PVC storage class |
| `helm_chart_path` | `eks-microservices/helm-services` | ArgoCD chart path |

---

## Rotating a password

```bash
cd infra/vault-secrets
terraform taint random_password.db
terraform apply -var enable_eso_secrets=true

kubectl annotate externalsecret db-credentials -n ecommerce \
    force-sync=$(date +%s) --overwrite

kubectl rollout restart deployment -n ecommerce
```

> Rotating a DB password also requires `ALTER USER` in PostgreSQL — CNPG only sets the password at bootstrap.

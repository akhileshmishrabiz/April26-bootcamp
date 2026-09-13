# E-Commerce Seed Data Job

Kubernetes Job that seeds users, products, and a demo cart into the e-commerce microservices via the API gateway.

## ECR Image

```
879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
```

## Prerequisites

- AWS CLI configured with appropriate credentials (for ECR)
- Docker installed
- kubectl configured to access your cluster
- API gateway and backend services running in the `ecommerce` namespace

## Run the Job Manually

```bash
# From microservices/app/seed-job/
docker build -t ms-ecom-seed:latest .
kind load docker-image ms-ecom-seed:latest --name ecommerce-vault   # Kind only

# Required when Calico NetworkPolicies are active
kubectl apply -f ../../observibility/servicemesh-networkingpolicies/network-policies/allow-seed-job.yaml

kubectl delete job seed-data-job -n ecommerce --ignore-not-found
kubectl apply -f seed-job.yaml
kubectl wait --for=condition=complete job/seed-data-job -n ecommerce --timeout=300s
kubectl logs job/seed-data-job -n ecommerce
kubectl get jobs -n ecommerce
```

For local docker-compose:

```bash
# From microservices/
./seed-data.sh
```

## Building the Image

```bash
docker build -t ms-ecom-seed:latest .
docker tag ms-ecom-seed:latest 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
docker push 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_URL` | API Gateway base URL | `http://localhost:8080` |
| `SEED_PASSWORD` | Password for all test accounts | `Password123!` |
| `PREFLIGHT_ATTEMPTS` | Health-check retries | `60` |
| `PREFLIGHT_SLEEP` | Seconds between retries | `5` |

## Seeded Data

### Users (5 test accounts)

All accounts share the same password (`Password123!` by default):

| Email | Name |
|-------|------|
| john.doe@example.com | John Doe |
| jane.smith@example.com | Jane Smith |
| bob.johnson@example.com | Bob Johnson |
| alice.williams@example.com | Alice Williams |
| charlie.brown@example.com | Charlie Brown |

### Products (25 items)

Categories: Electronics, Footwear, Clothing, Accessories, Gaming, Home & Kitchen, Books, Sports, Outdoor.

### Demo cart

Logs in as `john.doe@example.com` and adds the first two products to their cart.

## Test Credentials

```
Email:    john.doe@example.com
Password: Password123!
```

## Integration with Deploy Scripts

`helm-cnpg-vault-deploy.sh` (Step 14) builds the seed image, applies the seed-job NetworkPolicy, and runs this Job automatically after services are healthy.

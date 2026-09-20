# Vault + External Secrets Operator on kind

This is a small local demo showing how External Secrets Operator (ESO) reads a
secret from HashiCorp Vault by using Kubernetes authentication and creates a
normal Kubernetes `Secret`.

> This demo runs Vault in **development mode**. It is intentionally simple and
> is not suitable for production: Vault is unsealed, uses an in-memory store,
> has a known root token, and uses plain HTTP inside the cluster.

## What gets created

- A kind cluster named `vault-eso-demo`
- Vault in the `vault` namespace
- External Secrets Operator in the `external-secrets` namespace
- A Vault KV v2 secret at `secret/demo`
- A demo service account, `demo/eso-vault-auth`
- A namespaced `SecretStore` and `ExternalSecret`
- A Kubernetes Secret named `demo/demo-credentials`

## How the components connect

```text
ExternalSecret
      |
      v
External Secrets Operator
      |
      | 1. Requests a short-lived JWT for demo/eso-vault-auth
      | 2. Sends that JWT to Vault's Kubernetes auth endpoint
      v
Vault
      |
      | 3. Uses Kubernetes TokenReview to validate the JWT
      | 4. Checks that the service account and namespace match its role
      | 5. Returns a short-lived Vault token with the eso-demo policy
      | 6. Allows that token to read only secret/data/demo
      v
Kubernetes Secret: demo/demo-credentials
```

Important objects:

- **Vault secret engine:** stores versioned key/value data.
- **Vault policy:** permits `read` only on `secret/data/demo`.
- **Vault Kubernetes auth role:** maps the `demo/eso-vault-auth` service
  account to that policy.
- **SecretStore:** tells ESO where Vault is and how to authenticate.
- **ExternalSecret:** maps Vault values to keys in a Kubernetes Secret.

The Vault root token is used only by the setup script to configure Vault and
by `vault-secrets.sh` to manage demo values. ESO does not use the root token.

## Demo files

- `setup-demo.sh`: creates the cluster, installs Vault and ESO, and configures
  Vault Kubernetes authentication.
- `eso-config.yaml`: standalone ESO configuration containing the
  `ServiceAccount`, `SecretStore`, and `ExternalSecret`.
- `vault-secrets.sh`: separate Vault CLI commands for creating, updating,
  reading, and deleting the demo secret.

## Prerequisites

Install and start:

- Docker
- kind
- kubectl
- Helm

## Run the demo

```bash
chmod +x setup-demo.sh vault-secrets.sh
./setup-demo.sh
```

The script is intentionally linear so it can also be opened and run one
section at a time during a presentation.

## Demo commands

The setup creates an initial Vault secret. Read it:

```bash
./vault-secrets.sh get
```

Update it and create a new Vault version:

```bash
./vault-secrets.sh update updated-user new-password
```

To demonstrate creation again, permanently delete the path and recreate it:

```bash
./vault-secrets.sh delete
./vault-secrets.sh create demo-user first-password
```

The underlying Vault CLI command used to write the values is:

```bash
vault kv put secret/demo username="demo-user" password="first-password"
```

To apply the ESO configuration separately:

```bash
kubectl apply -f eso-config.yaml
```

Inspect ESO's resources and authentication status:

```bash
kubectl -n demo get secretstore
kubectl -n demo get externalsecret
kubectl -n demo describe externalsecret demo-credentials
```

Read the generated Kubernetes Secret:

```bash
kubectl -n demo get secret demo-credentials \
  -o jsonpath='{.data.username}' | base64 --decode; echo

kubectl -n demo get secret demo-credentials \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

ESO refreshes every 15 seconds. Watch the Kubernetes Secret change:

```bash
kubectl -n demo get externalsecret demo-credentials --watch
```

Then read the generated Secret again using the commands above.

## Authentication details

ESO asks Kubernetes for a short-lived, audience-bound service-account token.
Vault validates it through Kubernetes's TokenReview API. The
`vault-token-reviewer` ClusterRoleBinding gives Vault permission to make that
validation request.

Vault accepts the login only when all of these match:

- Auth mount: `kubernetes`
- Vault role: `eso-demo`
- Service account: `eso-vault-auth`
- Namespace: `demo`
- Token audience: `vault`

After authentication, the resulting Vault token receives the `eso-demo`
policy. That policy can read the demo secret but cannot read unrelated paths.

## Troubleshooting

```bash
kubectl get pods -A
kubectl -n demo describe secretstore vault
kubectl -n demo describe externalsecret demo-credentials
kubectl -n external-secrets logs \
  deployment/external-secrets --tail=100
```

Re-running `./setup-demo.sh` updates the installations and configuration.

## Clean up

```bash
kind delete cluster --name vault-eso-demo
```

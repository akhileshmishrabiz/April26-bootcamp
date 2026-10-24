# DevSecOps Part 1: Find and Fix

This deliberately imperfect lab contains:

- Terraform for an S3 bucket, SQS queue, and KMS key
- A small Flask application that uploads files to S3 and sends SQS messages
- A basic Dockerfile

The code is intentionally not production-ready. It is designed to produce useful
findings in infrastructure, dependency, secret, source, and container scans.
Use only in a training AWS account.

## 1. Deploy the infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Get the values needed by the application:

```bash
terraform output -raw bucket_name
terraform output -raw queue_url
```

## 2. Build and run the application

The container uses the AWS credentials available in your environment. Do not
put credentials in the Dockerfile or source files.

```bash
docker build -t devsecops-part1 .

docker run --rm -p 5000:5000 \
  -e AWS_REGION=us-east-1 \
  -e BUCKET_NAME="$(terraform output -raw bucket_name)" \
  -e QUEUE_URL="$(terraform output -raw queue_url)" \
  -v "$HOME/.aws:/root/.aws:ro" \
  devsecops-part1
```

Test it:

```bash
curl http://localhost:5000/health
curl -F "file=@README.md" http://localhost:5000/upload
curl http://localhost:5000/files
```

## 3. Suggested scanners

```bash
tfsec .
checkov -d .
trivy config .
trivy image devsecops-part1
bandit -r app.py
pip-audit -r requirements.txt
```

Have students review scanner results, decide which findings are real risks, fix
the code, and scan again.

## Clean up

```bash
terraform destroy
```

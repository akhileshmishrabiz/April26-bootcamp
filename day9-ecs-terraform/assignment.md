# DevOps Bootcamp — April 2026 Batch

> **Sessions covered:** May 17 · May 23 · May 24, 2026
> **Submit by:** Before the next session
> **How to submit:** Push everything to your personal GitHub repo and share the link in the squad channel

---

## How to follow this project

Every class builds directly on the previous one. Before you start any assignment, re-read the class transcript notes and make sure the previous week's infrastructure is still running — or re-apply it from your Terraform code.

**Folder structure to follow:**

```
your-repo/
├── about_me.yaml                  # Class 1 warm-up
├── infra/
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf
│   ├── sg.tf
│   ├── rds.tf
│   ├── ecs.tf
│   ├── alb.tf
│   ├── route53.tf
│   ├── cloudwatch.tf
│   └── .gitignore
├── app/
│   └── src/                       # Your two-tier app code
├── .github/
│   └── workflows/
│       └── build-and-deploy.yml   # Class 3 CI/CD pipeline
└── README.md
```

**Rules for every submission:**

- Never commit `.terraform/`, `*.tfstate`, `*.tfstate.backup`, or `.env` files — add them to `.gitignore` before your first push
- Run `terraform fmt` before committing any `.tf` file
- Run `terraform validate` before running `terraform plan`
- Always `terraform destroy` after testing to avoid unnecessary AWS charges
- Write a short commit message that describes what you did (e.g. `add nat gateway and private route table`)
- Document your learning — update the README as you go

---

## Class 1 Assignment — Terraform Fundamentals + VPC

> Session: May 17, 2026 · Topics: Terraform basics, state, remote backend, VPC networking

---

### Task 1 — YAML warm-up

Create a file called `about_me.yaml` in the root of your repo. This file should demonstrate the three core YAML concepts covered in class.

**Your file must include:**

- At least one dictionary (key-value pairs — name, city, role)
- At least one list (hobbies, tools you use, or skills)
- At least one nested structure (e.g. experience or education with sub-keys)

Validate your file with a YAML linter (`yamllint` or any online tool) before committing.

> **Why this matters:** Next week you will write GitHub Actions workflows in YAML. Being comfortable with indentation and structure now will save you a lot of debugging later.

---

### Task 2 — Install Terraform and tfenv

Install tfenv and use it to manage Terraform versions.

```bash
# Mac
brew install tfenv

# WSL / Linux
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Then install and activate the version used in class
tfenv install 1.12.1
tfenv use 1.12.1
terraform version
```

**Checklist:**
- [ ] tfenv installed and working
- [ ] Terraform 1.12.1 active
- [ ] `terraform version` shows 1.12.1

---

### Task 3 — Create versions.tf and initialise the project

Create the `infra/` folder. Inside it, create `versions.tf` with the Terraform and AWS provider version constraints.

```hcl
terraform {
  required_version = "= 1.12.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}
```

Run `terraform init` and confirm the `.terraform/` folder and lock file are created.

Add the following to `infra/.gitignore`:

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
.terraform.lock.hcl
```

> Note: whether to commit `.terraform.lock.hcl` is a team decision — in class we discussed keeping it to lock provider versions for consistency. Add your reasoning in the README.

---

### Task 4 — Build the full VPC in Terraform

Recreate the VPC architecture from class. All values (region, CIDR blocks, AZs) must come from `variables.tf` — nothing hardcoded directly in resource blocks.

**Resources to create:**

- VPC with `enable_dns_hostnames = true` and `enable_dns_support = true`
- 2 public subnets across two availability zones
- 2 private subnets across two availability zones
- 2 database subnets (separate CIDR range — keep RDS isolated)
- Internet gateway attached to the VPC
- Elastic IP + NAT gateway in a public subnet
- Public route table with route to IGW, associated to both public subnets
- Private route table with route to NAT gateway, associated to both private subnets
- Default tags in `provider.tf` — at minimum: `managed_by = "terraform"` and `project = "bootcamp"`

**Reference flow:**

```
Public subnets  → Public route table  → Internet Gateway  → Internet
Private subnets → Private route table → NAT Gateway → Internet
DB subnets      → No outbound route   → VPC-internal only
```

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

### Task 5 — Configure remote state in S3

Move state from local to S3.

- Create an S3 bucket with versioning enabled
- Add the backend block to `versions.tf`:

```hcl
backend "s3" {
  bucket       = "your-bucket-name"
  key          = "bootcamp/ecs/terraform.tfstate"
  region       = "ap-south-1"
  encrypt      = true
  use_lockfile = true
}
```

- Run `terraform init -migrate-state` and confirm the state file appears in S3
- Run `terraform state list` and paste the output in your README as a code block

> With versioning enabled on the bucket you can recover a deleted or corrupted state file. Always enable this.

---

### Task 6 — Concept questions

Answer these in your `README.md` in your own words. Two to three sentences each.

1. What is idempotency in Terraform and why does it matter for infrastructure?
2. What is a Terraform state file? What happens if two people apply from the same repo simultaneously without state locking?
3. What is the difference between a `resource` block and a `data` block? When would you use each?
4. What is implicit dependency? Give one example from your VPC code.
5. When would you choose a VPC endpoint over a NAT gateway? Consider both cost and security.
6. Why do we keep RDS subnets separate from private app subnets — what problem does it solve?

---

## Class 2 Assignment — ECS, ALB, RDS and Full Stack Deployment

> Session: May 23, 2026 · Topics: ECS task definitions, ECS service, ALB, Route 53, ACM, security groups, secrets manager

---

### Task 7 — Create security groups

Create `sg.tf` with three security groups. Lock them down — do not use `0.0.0.0/0` for everything.

| Security group | Inbound rule | Source |
|---|---|---|
| ALB SG | Port 80 and 443 | `0.0.0.0/0` (public-facing) |
| ECS SG | Port 8000 (app port) | ALB SG only |
| RDS SG | Port 5432 (Postgres) | ECS SG only |

> This reflects the real traffic flow: internet → ALB → ECS task → RDS. Each layer only accepts traffic from the layer above it.

---

### Task 8 — Create the RDS database and Secrets Manager entry

Create `rds.tf` with:

- A random password using the `random` provider (alpha-numeric only — no special characters to avoid connection string issues)
- A DB subnet group using your database subnets
- A `aws_db_instance` resource (Postgres, `db.t3.micro`, single instance, no backup retention for cost saving)
- A `aws_secretsmanager_secret` and `aws_secretsmanager_secret_version` that stores the full DB connection string including username, password, host, port, and DB name

The secret string format should match what your app expects:

```
postgresql://username:password@host:5432/dbname
```

Use `aws_db_instance` outputs to build the connection string dynamically — do not hardcode the endpoint.

---

### Task 9 — Create the ECS cluster and task definition

Create `ecs.tf` with:

- An ECS cluster (container insights disabled to avoid cost)
- A CloudWatch log group for container logs (7-day retention)
- An IAM execution role with:
  - Permission to pull from ECR
  - Permission to write logs to your specific log group only (not `*`)
  - Permission to read from your specific Secrets Manager secret only
- A task definition with:
  - Fargate launch type
  - The DB connection string passed as a `secrets` reference (not plain `environment`) pointing to the Secrets Manager ARN
  - `requires_compatibilities = ["FARGATE"]`
  - `network_mode = "awsvpc"`

> Passing secrets via the `secrets` block instead of plain environment variables means the value is never visible in the ECS console task configuration. This is the correct production approach.

---

### Task 10 — Create the ALB, target group and ECS service

Create `alb.tf` with:

- An Application Load Balancer in the public subnets with the ALB security group
- A target group with `target_type = "ip"` (required for Fargate), health check on your app's login or health endpoint
- An HTTP listener on port 80 forwarding to the target group
- An ECS service in the private subnets, attached to the target group, with `launch_type = "FARGATE"`

Verify deployment:

```bash
# After apply, get the ALB DNS name
terraform output alb_dns_name

# Hit the endpoint
curl http://<alb-dns-name>/
```

---

### Task 11 — Route 53 and ACM certificate

Create `route53.tf` with:

- A `data` block to reference your existing hosted zone (do not re-create it)
- A Route 53 A record aliased to the ALB for your subdomain (e.g. `app.yourdomain.com`)
- An ACM certificate for the same subdomain with DNS validation
- A `for_each` loop to create the DNS validation CNAME records automatically
- An HTTPS listener (port 443) on the ALB using the validated certificate

Once deployed, confirm your app is reachable at `https://app.yourdomain.com`.

---

### Task 12 — Provider config and default tags

Create `provider.tf` and ensure:

- The AWS provider is configured with your region from a variable (not hardcoded)
- Default tags are applied to all resources:

```hcl
default_tags {
  tags = {
    managed_by  = "terraform"
    project     = "bootcamp-ecs"
    environment = "dev"
  }
}
```

> In a real company these tags help you identify which repository owns which resource, especially when you have hundreds of resources across multiple teams.

---

### Terraform troubleshooting scenarios to document

Add a `TROUBLESHOOTING.md` to your repo and document what you encountered and how you resolved it. At minimum cover:

- What error appears when `requires_compatibilities` is missing from the task definition, and what the fix is
- What happens when the ECS execution role does not have Secrets Manager read permission
- What `target_type = "ip"` means and what fails if you leave it as the default `instance`

---

## Class 3 Assignment — GitHub Actions CI/CD Pipeline

> Session: May 24, 2026 · Topics: GitHub Actions events, jobs, steps, runners, secrets, Docker build, ECR push, ECS rolling deployment

---

### Task 13 — Play with GitHub Actions syntax

Before building the real pipeline, create a simple workflow to get comfortable with the syntax.

Create `.github/workflows/simple.yml`:

```yaml
name: simple workflow

on:
  workflow_dispatch:

jobs:
  linux-job:
    runs-on: ubuntu-latest
    steps:
      - name: print hello
        run: echo "Hello from Linux"

      - name: multi-line commands
        run: |
          echo "Step 1"
          echo "Step 2"

  mac-job:
    needs: linux-job
    runs-on: macos-latest
    steps:
      - name: print hello
        run: echo "Hello from Mac"
```

**Verify:**
- [ ] Run it manually from the Actions tab
- [ ] Confirm mac-job waits for linux-job to finish
- [ ] Disable the workflow after testing so it does not run accidentally

---

### Task 14 — Create the ECR repository in Terraform

Add `ecr.tf` to your `infra/` folder:

```hcl
resource "aws_ecr_repository" "app" {
  name                 = "bootcamp-app"
  image_tag_mutability = "IMMUTABLE"
}
```

Apply this before building the CI/CD pipeline. Copy the repository URI — you will need it in the workflow.

> Set `image_tag_mutability = "IMMUTABLE"` so image tags cannot be overwritten. This is a security and auditability requirement in most production environments.

---

### Task 15 — Build the CI/CD pipeline

Create `.github/workflows/build-and-deploy.yml`. This pipeline should trigger only when application code changes, build the Docker image, push it to ECR, and deploy the new version to ECS automatically.

**Pipeline structure:**

```
on: push to main (path filter: app/src/**)
  ↓
job: build
  - checkout code
  - configure AWS credentials (from GitHub secrets)
  - login to ECR
  - build Docker image tagged with git commit SHA
  - push image to ECR
  ↓
job: deploy (needs: build)
  - update ECS service to force new deployment
```

**Add these secrets to your GitHub repository** (Settings → Secrets → Actions):

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Environment variables to define at workflow level:**

```yaml
env:
  AWS_REGION: ap-south-1
  ECR_REPO: <your-ecr-repo-uri>
  ECS_CLUSTER: <your-cluster-name>
  ECS_SERVICE: <your-service-name>
```

**Image tag — use the commit SHA, not `latest`:**

```yaml
IMAGE_TAG: ${{ github.sha }}
```

**Checklist:**
- [ ] Pipeline triggers only when files under `app/src/` change
- [ ] Image is tagged with the git commit SHA
- [ ] New image appears in ECR after each push
- [ ] ECS service shows a new deployment in progress (rolling update)
- [ ] App is reachable at your domain after deployment completes with no downtime

---

### Task 16 — Observe the rolling deployment

After your pipeline runs successfully:

1. Go to your ECS cluster → service → deployments tab
2. Screenshot the rolling update in progress (old tasks draining, new tasks starting)
3. Check the ALB target group — confirm new tasks register as healthy before old ones are removed
4. Add the screenshot and a short explanation to your README: what is a rolling upgrade and why does it avoid downtime?

---

### Task 17 — SRE metrics understanding

Based on the discussion in class about measuring application health beyond just uptime, answer the following in your README:

1. What are the four Google SRE golden signals? Give one example of each for the two-tier app you deployed.
2. Why is measuring only container uptime and CPU/memory not enough to understand user experience?
3. In the ALB metrics, what does a spike in `5xx` response codes tell you that a green health check does not?
4. Where in the AWS console can you find `5xx` counts for your ALB? What time range would you check if a user reported an issue?

---

## Final checklist before submitting

- [ ] All `.tf` files formatted with `terraform fmt`
- [ ] `.gitignore` in place — no state files, no `.terraform/` in the repo
- [ ] Remote state confirmed in S3 with versioning enabled
- [ ] `terraform state list` output pasted in README
- [ ] App reachable at your domain over HTTPS
- [ ] GitHub Actions pipeline runs end-to-end on a code push
- [ ] Rolling deployment screenshot added to README
- [ ] All concept questions answered in README
- [ ] `TROUBLESHOOTING.md` updated with real issues you hit
- [ ] Infrastructure destroyed after testing to avoid charges: `terraform destroy`


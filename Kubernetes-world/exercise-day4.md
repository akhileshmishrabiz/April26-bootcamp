# EKS on AWS with Terraform — Full Class Exercise (Sequential)
**April 2026 Batch | Work in: `April26-bootcamp/k8s-world/EKS`**

This mirrors the class exactly in order. Do the phases in sequence — later phases depend on earlier ones (e.g. EKS needs the VPC's subnet IDs as output). Each step has a **Task** and **Acceptance criteria** so you know when to move on.

---

## Phase 0 — Prerequisites
- [ ] AWS CLI configured with credentials that can create VPC/EKS/IAM/RDS resources.
- [ ] `tfenv` installed. Pin the exact Terraform version used in class:
  ```
  tfenv install 1.15.1 && tfenv use 1.15.1
  ```
- [ ] An S3 bucket already exists to hold your remote state (create one if you don't have it).
- [ ] `kubectl` installed.

**Acceptance:** `terraform -v` prints 1.15.1 exactly (not `>=`).

---

## Phase 1 — Design the network on paper first
Don't write any code yet.

**Task:**
1. Pick a VPC CIDR of `10.0.0.0/16`. Using host-bit math (32 − prefix, then 2^n), work out how many total IPs that gives you, and write it down.
2. Decide: 2 AZs (`ap-south-1a`, `ap-south-1b`, or your own region's two AZs), one public + one private subnet per AZ = 4 subnets total.
3. Decide where your database goes: same VPC (our choice), different VPC (needs VPC peering), or on-prem (needs VPN or Transit Gateway). Write one sentence justifying "same VPC" for this use case.
4. Decide public vs private placement: only the load balancer sits in public subnets. EKS control plane, nodes, and RDS all sit in private subnets.
5. Decide NAT strategy: one NAT Gateway (cheaper, single point of failure for *new* image pulls only) vs one per AZ (HA, costs more). Pick one and write down the tradeoff in one sentence.

**Acceptance:** a short `docs/network-design.md` with your CIDR math, subnet layout, and the two decisions above with one-line justifications each.

---

## Phase 2 — Scaffold the Terraform project
**Task:** under `k8s-world/EKS/eks-core/`, create:
```
versions.tf
variables.tf
outputs.tf
main.tf
vpc-network.tf
iam.tf
```
In `variables.tf`, define at minimum:
- `environment` (string, default `"dev"`)
- `single_nat_gateway` (bool, default `true`)
- `region` (string, default your chosen AWS region)

In `versions.tf`, pin the Terraform version and the AWS provider version (don't leave either unpinned).

**Acceptance:** `terraform fmt -check` and `terraform validate` pass with no resources defined yet.

---

## Phase 3 — Build the VPC (public module)
**Task:**
1. Find `terraform-aws-modules/vpc/aws` on the registry. Check its GitHub: stars, forks, who maintains it, how recently it was updated.
2. Pin a module version that's **at least a month old** — don't use `latest`. Write in your PR description why (supply-chain risk — a hijacked/just-published version hasn't been vetted by the community yet).
3. Configure the module in `vpc-network.tf`:
   - `name` using `var.environment` as part of the string, not hardcoded.
   - `cidr = "10.0.0.0/16"`
   - `azs` built dynamically off `var.region` (e.g. `["${var.region}a", "${var.region}b"]`), not hardcoded AZ names.
   - `public_subnets` / `private_subnets` — two CIDR blocks each, non-overlapping.
   - `enable_nat_gateway = true`, `single_nat_gateway = var.single_nat_gateway`
   - `enable_dns_hostnames = true`
4. **Required subnet tags for EKS** (this is the part that's easy to miss and breaks the load balancer controller later):
   - Public subnets: `kubernetes.io/cluster/<cluster-name> = "shared"` and `kubernetes.io/role/elb = "1"`
   - Private subnets: `kubernetes.io/cluster/<cluster-name> = "shared"` and `kubernetes.io/role/internal-elb = "1"`

**Acceptance:** `terraform plan` shows 4 subnets, 1 (or 2) NAT gateway(s) per your Phase 1 decision, an Internet Gateway, and all subnets carrying the tags above.

---

## Phase 4 — Wire up remote state
**Task:** configure the S3 backend in `versions.tf`. Key the state path off environment, e.g.:
```
key = "dev/eks-core/terraform.tfstate"
```
Use the built-in state locking (`use_lockfile = true`) instead of a DynamoDB lock table.

**Watch out for:** if you later copy this backend block into another Terraform project (like the app/RDS one in Phase 7), **change the key**. Pointing two different codebases at the same state key is how you accidentally delete your whole cluster. Double-check this before every `apply` on a copy-pasted backend block.

**Acceptance:** `terraform init` succeeds and creates a state file at the exact key path you chose.

---

## Phase 5 — Build the EKS cluster (public module)
**Task:**
1. Find `terraform-aws-modules/eks/aws` on the registry the same way you vetted the VPC module. Pin a version — but this time check the **open issues and recently closed ones** first.
2. Look specifically for issues about managed node groups joining before the VPC CNI addon is ready — older versions (~6.20.0) have a race condition here where `apply` hangs forever because nodes come up but never register with the cluster. Pick a version where this is fixed, and note the version number and why in a comment above the module block.
3. Configure the module:
   - `cluster_name` and `cluster_version` (use one minor version behind latest, e.g. `1.34`).
   - `cluster_endpoint_public_access = true` (we're not using a VPN/bastion for this exercise).
   - `enable_cluster_creator_admin_permissions = true`.
   - `vpc_id = module.vpc.vpc_id` and `subnet_ids = module.vpc.private_subnets` — **pulled dynamically from the VPC module's outputs, never hardcoded**.
   - One managed node group: `ami_type`, `instance_type`, `min_size = 1`, `max_size = 5`, `desired_size = 2`.
4. Add `default_tags` on the AWS provider block that stamp every resource with your repo path (e.g. `repo = "April26-bootcamp/k8s-world/EKS"`), so anyone can trace a resource back to the code that created it.

**Acceptance:** `module.eks.vpc_id` and `module.eks.private_subnets` resolve with no hardcoded IDs anywhere in the EKS module block (`grep -r "vpc-0\|subnet-0" .` returns nothing).

---

## Phase 6 — Break it, then fix it (required demo)
**Task:**
1. Comment out the explicit VPC CNI addon dependency in your EKS module config (the part that makes Terraform install the CNI addon *before* the node group).
2. Run `terraform apply`. Let it hang for a few minutes — watch what happens: node group comes up, but `apply` never completes.
3. Capture the relevant `terraform apply` output or a screenshot.
4. In `docs/network-design.md`, add 3–4 sentences explaining *why* it hangs (nodes exist as EC2 instances, but without the CNI addon they never register as Kubernetes nodes, so anything depending on the node group waits forever).
5. Uncomment the fix, re-apply, confirm it completes cleanly this time.

**Acceptance:** doc includes the broken-run evidence, the explanation, and confirmation the fixed version applies cleanly end to end.

---

## Phase 7 — Verify the cluster
**Task:**
```
aws eks update-kubeconfig --name <your-cluster-name> --region <region>
kubectl config rename-context <long-arn-context> my-cluster
kubectl get nodes -o wide
kubectl get pods -A
```
Check: node internal IPs fall inside your `10.0.0.0/16` range, and nodes have **no** external IP (they're private).

**Acceptance:** `kubectl get nodes` shows 2 `Ready` nodes; IPs verified against your CIDR from Phase 1.

---

## Phase 8 — App infra: RDS for the 3-tier app
Work in `app/infra/` (separate from `k8s-world/EKS` — this is the app team's repo, not the platform team's).

**Task:**
1. Look up your VPC dynamically instead of hardcoding the VPC ID — use a `data "aws_vpc"` block filtered by the `Name` tag you set in Phase 3. This is the same pattern as pulling module outputs, just for infra that lives in a *different* Terraform project than the VPC itself.
2. Create a DB subnet group using two new private subnets (pick CIDR ranges that **do not overlap** with the EKS subnets from Phase 3 — double check this).
3. Create a security group allowing port `5432` inbound only from within the VPC CIDR — never open to `0.0.0.0/0`.
4. Create a KMS key (7-day deletion window, an alias) dedicated to this environment's database encryption — don't reuse a random default key.
5. Generate the master password with the `random_password` provider — never hardcode a password in `.tf` files.
6. Create the RDS instance: Postgres engine, `db.t3.medium`, 30GB storage, encrypted with your KMS key, in the subnet group from step 2.
7. Store the **full connection string** (not just the bare password) in Secrets Manager.
8. Point this project's backend at its **own** state key (e.g. `dev/app-infra/terraform.tfstate`) — verify it's different from the `eks-core` key from Phase 4.

**Acceptance:** `terraform apply` succeeds; `aws secretsmanager get-secret-value` returns a full Postgres connection URL; security group has exactly one ingress rule scoped to the VPC CIDR.

---

## Phase 9 — Identify app config: ConfigMap vs Secret
**Task:** using the `docker-compose.yml` in `app/src/` as your reference for what env vars the app needs, sort every variable into one of two buckets and write the list in `docs/app-config.md`:
- **ConfigMap** (non-sensitive): e.g. `DB_HOST`, `DB_PORT`, `DB_NAME`, `ALLOWED_ORIGINS`
- **Secret** (sensitive): e.g. `DB_PASSWORD`, `SECRET_KEY`, `DATABASE_URL`

**Acceptance:** every env var referenced in the backend/frontend Dockerfiles or compose file is accounted for in one of the two lists.

---

## Phase 10 — CI/CD: build and push both images
**Task:** in `.github/workflows/`, build a workflow that:
1. Triggers on `workflow_dispatch` (manual) for now.
2. Uses a **single `matrix` strategy** to build both `frontend` and `backend` — no duplicated job/step code per service. Matrix entries carry the relative path and the ECR repo name per service.
3. Uses `docker/setup-buildx-action` (pinned version) and tags each image with the commit SHA.
4. Authenticates to AWS with static credentials for now (flagged: this gets replaced with OIDC next class — don't build this part twice).

**Acceptance:** triggering the workflow manually builds and pushes both images to their respective ECR repos, tagged with the commit SHA; adding a third matrix entry (e.g. a `worker` service) requires no new job code, only a new matrix line.

---

## Phase 11 — Docker image optimization (self-study assignment from class)
**Task:** for both images:
1. **Faster builds** — multi-stage Dockerfile + build cache (`actions/cache` or BuildKit `cache-from`/`cache-to`) so a no-op re-run doesn't reinstall everything.
2. **Smaller images** — get both under 200MB using a slim/distroless runtime stage.
3. **Better security** — run as non-root; add a Trivy scan step that fails the build on HIGH/CRITICAL CVEs.

**Acceptance:** PR shows before/after image size and before/after build time for a no-op re-run, plus a passing Trivy step in the workflow.

---

## Before next class
Read the OIDC + GitHub Actions blog post shared in the WhatsApp group. Next class replaces the static AWS credentials in Phase 10 with OIDC — come having read it or the pace will lose you.

## Submission
One PR per phase (Phases 1, 3, 5, 6, 7 doc, 8, 9, 10, 11 — nine PRs total), each titled `[Phase N] <short description>` and referencing this exercise.

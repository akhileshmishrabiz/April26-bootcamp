# Day 9 ECS Student Portal — Complete DevSecOps CI Pipeline

This document details the security scanning, quality gates, and automated smoke testing implemented for the Day 9 ECS 2-tier application, strictly based on the **October 24 and October 25, 2026** DevOps Bootcamp sessions.

---

## 1. Architecture: The "Shift-Left" Pipeline

The pipeline balances **speed for developers** with **enterprise security controls**. Heavy or advisory scans are allowed to run in parallel without blocking feature branches, while mandatory quality gates enforce critical correctness before any pull request is merged to `main`.

```
                        ┌────────────────────────────────────────────────────────┐
                        │             PULL REQUEST TO MAIN / DISPATCH            │
                        └────────────────────────────────────────────────────────┘
                                                    │
                 ┌──────────────────────────────────┴──────────────────────────────────┐
                 │                                                                     │
                 ▼                                                                     ▼
      [ APPLICATION LAYER ]                                                 [ INFRASTRUCTURE LAYER ]
   • Code Quality & Unit Tests (Ruff, Pytest)                           • Terraform Format & Validate
   • CodeQL Python SAST Scan                                            • TFLint Static Analysis
   • Dependency SCA (pip-audit)                                         • Checkov IaC Benchmark (quiet)
   • Trivy Filesystem Scan                                              • Gitleaks Infra Secret Scan
   • Gitleaks App Secret Scan
   • Hadolint Dockerfile Lint
                 │
                 ▼ (after code-quality passes)
     [ CONTAINER BUILD & SMOKE TEST ]
   • Docker Build (Non-root user 10001:10001)
   • Smoke Test (Healthcheck, /metrics, /login)
   • Trivy Image Vulnerability Scan (CVEs)
                 │
                 └──────────────────────────────────┬──────────────────────────────────┘
                                                    │
                                                    ▼
                                    [ REQUIRED CI QUALITY GATE ]
                                Enforces success on critical gates:
                              - code-quality (Ruff + Pytest)
                              - terraform-validate
                              - tflint
                              - container (Docker build + Smoke test)
```

---

## 2. Pipeline Jobs Breakdown

| Job Name | Tool | Scope / Rules Covered | Gate Type |
| :--- | :--- | :--- | :--- |
| **`code-quality`** | **Ruff** + **Pytest** | Replaces Black/Flake8/isort. Enforces 70% unit test coverage across 21 test suites. | **Required (Blocking)** |
| **`terraform-validate`** | **Terraform CLI** | `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`. | **Required (Blocking)** |
| **`tflint`** | **TFLint v0.54.0** | Static analysis of AWS provider resources and syntax conventions. | **Required (Blocking)** |
| **`container`** | **Docker** + **Bash** | Builds image, runs `scripts/smoke-test.sh` hitting `/health`, `/metrics`, and `/login`. | **Required (Blocking)** |
| **`codeql`** | **GitHub CodeQL** | Advanced Python-scoped SAST scan (avoids multi-language costs). | Advisory |
| **`dependency-scan`** | **pip-audit** | Software Composition Analysis (SCA) checking `requirements.txt` for known CVEs. | Advisory |
| **`filesystem-scan`** | **Trivy (fs)** | Scans repository root for high/critical security flaws and vulnerable dependencies. | Advisory |
| **`app-secret-scan`** | **Gitleaks** | Secret detection with `.gitleaks.toml` allowlists for seed dummy credentials. | Advisory |
| **`dockerfile-checks`** | **Hadolint** + **Trivy** | Lints Dockerfile instructions (non-root `USER 10001`, `pip --no-cache-dir`). | Advisory |
| **`checkov`** | **Checkov** | Scans Terraform against CIS/AWS policies (`quiet: true`, soft fail). | Advisory |
| **`infra-secret-scan`** | **Gitleaks** | Scans Terraform files for unencrypted secrets or embedded tokens. | Advisory |
| **`required-gate`** | **GitHub Actions** | Consolidates outcomes and blocks merge if any mandatory check fails. | **Required (Blocking)** |

---

## 3. Container Smoke Testing (`scripts/smoke-test.sh`)

In class, Akhilesh noted that AI-assisted edits often introduce regressions resulting in `500` server errors. The smoke test solves this by running immediately after container creation on the runner:

1. Launches container on isolated port (`127.0.0.1:8080:8000`).
2. Polls `/health` up to 30s and asserts JSON response:
   ```json
   {"database": "connected", "status": "healthy"}
   ```
3. Queries `/metrics` and verifies Prometheus metric registration (`http_requests_total`).
4. Queries `/login` route to verify template rendering and route handling.
5. Employs a bash `EXIT` trap to automatically clean up the container and output logs on failure.

---

## 4. Branch Ruleset Setup (GitHub UI)

To protect the `main` branch with this quality gate:

1. In the GitHub repository, navigate to **Settings** → **Rules** → **Rulesets**.
2. Click **New ruleset** → **New branch ruleset**.
3. Name: `Protect Main Branch`.
4. Enforcement status: **Active**.
5. Target branches: Add target → **Default branch** (`main`).
6. Under **Rules**:
   * Check **Require a pull request before merging**.
   * Check **Require status checks to pass**.
   * Add required status check:
     * Search and select: `Required CI Quality Gate` (or `required-gate`).
7. Save changes.

---

## 5. Local Verification Commands

Developers can run checks locally before pushing:

```bash
# 1. Python Linting with Ruff
cd day9-ecs-terraform/src
ruff check .

# 2. Pytest with Coverage
pytest --cov=app --cov-report=term-missing tests/

# 3. Terraform Format & Validation
cd ../infra
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

# 4. Container Smoke Test (requires Docker)
docker build -t ecs-day9:local day9-ecs-terraform/src
./day9-ecs-terraform/scripts/smoke-test.sh ecs-day9:local
```

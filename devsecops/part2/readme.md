# DevOps Quest

A gamified Flask learning platform where players solve DevOps incidents, earn
XP, build streaks, unlock badges, and compete on a leaderboard. It includes a
browser UI, REST API, Prometheus metrics, pytest tests, a Docker image, and
Terraform for AWS ECS Fargate.

> This project is intentionally insecure and imperfect. It is designed to
> produce findings in dependency, secret, container, Dockerfile, and IaC
> scans. Do not deploy it unchanged to a real environment.

## Project layout

```text
.
├── app.py
├── devops_quest/
│   ├── challenges.py
│   ├── game.py
│   ├── models.py
│   ├── routes.py
│   └── schemas.py
├── static/
├── templates/
├── tests/
├── scripts/
│   └── smoke-test.sh
├── Dockerfile
├── requirements.txt
├── requirements-dev.txt
└── infra/
```

## Run locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
flask --app app run
```

Open `http://localhost:5000` to play. The app seeds a `demo` player
automatically.

Try the API directly:

```bash
curl http://localhost:5000/health
curl 'http://localhost:5000/api/challenges?player_id=1'
curl -X POST http://localhost:5000/api/challenges/docker-detective/submit \
  -H 'Content-Type: application/json' \
  -d '{"player_id":1,"answer":"USER"}'
curl http://localhost:5000/api/leaderboard
curl http://localhost:5000/metrics
```

## Game features

- Eight missions across containers, CI/CD, security, Terraform, Kubernetes,
  observability, cloud IAM, and reliability
- XP, levels, ranks, energy, win streaks, achievements, and daily reward spins
- Persistent players and completions with SQLAlchemy and SQLite
- Pydantic request validation, JWT token generation, API rate limiting, CORS,
  structured logs, Prometheus metrics, and a short-lived leaderboard cache
- Extra cloud, Redis, Celery, HTTP, and security libraries provide a realistic
  dependency surface for software-composition analysis

## Tests and application checks

```bash
pytest -v
pytest --cov=devops_quest --cov-report=term-missing --cov-fail-under=80
ruff check .
pip-audit -r requirements.txt
```

Ruff and pytest are required quality gates. Dependency and secret scanners are
expected to surface training findings without hiding the correctness result.

## Container checks

```bash
docker build -t devsecops-training:local .
docker run --rm -p 5000:5000 devsecops-training:local
./scripts/smoke-test.sh devsecops-training:local

hadolint Dockerfile
trivy config Dockerfile
trivy image devsecops-training:local
```

The Dockerfile deliberately uses a floating base tag, copies too broadly,
installs as root, has overly broad permissions, and uses a shell-form command.

## Terraform checks

```bash
cd infra
terraform init
terraform fmt -check
terraform validate
tfsec .
checkov -d .
```

The ECS example deliberately includes public networking, broad security-group
rules, HTTP-only load balancing, weak container hardening, and limited logging
protection.

To inspect a deployment plan:

```bash
terraform plan \
  -var='container_image=123456789012.dkr.ecr.ap-south-1.amazonaws.com/devsecops-training:latest'
```

AWS credentials and a real image URI are required to plan or deploy. Running
`terraform apply` creates billable AWS resources.

## Pull request pipeline

`.github/workflows/devsecops-part2.yaml` runs for Part 2 pull requests to
`main`. Independent code, dependency, filesystem, secret, Dockerfile, and
Terraform checks run in parallel. After required code checks complete, the
pipeline builds the image once, then scans it, generates a CycloneDX SBOM, and
runs the container smoke test in parallel.

Ruff, the 80% pytest coverage threshold, Terraform format/validate, TFLint,
image build, SBOM generation, and the smoke test are required. Finding-oriented
pip-audit, Trivy, Gitleaks, Hadolint, and Checkov steps upload reports but do not
fail solely because the intentionally insecure training examples were found.
The final gate summarizes the required outcomes. No cloud deployment occurs.

###
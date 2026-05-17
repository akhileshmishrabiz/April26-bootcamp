# Exercise: Docker Compose Real-World App + ECS Basics

This exercise has two parts:

- **Part A**: Run a multi-service Docker Compose app (web app + DB + monitor + load generator + alerting via AWS SES) and observe how monitoring and alerting work in a near-real scenario.
- **Part B**: Run your first container on AWS ECS using Fargate. Task definitions, clusters, tasks. No service yet — that comes next class.

Do them in order. Don't skip ahead.

---

## Prerequisites

Before you start, make sure you have:

- Docker Desktop installed and running
- An AWS account with CLI configured (`aws configure` done)
- Access to AWS SES in `ap-south-1` (or change region in `.env`)
- Two email addresses you can check (one for sender, one for recipient — or use the same one for both)
- The project code from `day7/project1/` cloned/copied locally

---

# Part A: Docker Compose — Monitored App with Alerting

## Goal

Run a 5-service stack:

1. `db` — PostgreSQL database
2. `webapp` — Flask app with stress endpoints
3. `stress-generator` — generates load against the webapp
4. `monitor` — collects CPU/memory/response time, runs dashboard on port 8001
5. `alert-service` — reads alert logs, sends emails via AWS SES

You'll watch CPU/memory climb, see the app go unhealthy, and receive alert emails.

---

## Step 1: Verify your sender and recipient emails in AWS SES

SES in sandbox mode only sends to verified addresses. You must verify both your sender and your recipient addresses before any email will go out.

1. Open AWS Console → **Simple Email Service (SES)** → Region `ap-south-1` (or your region)
2. Go to **Identities** → **Create identity**
3. Choose **Email address**, enter your sender email (e.g., `youremail@gmail.com`), click Create
4. Check your inbox (and spam folder) for the verification email from AWS, click the link
5. Repeat for your recipient email if it's different
6. Confirm both identities show **Verification status: Verified** in the SES console

Do not move to Step 2 until both are verified.

---

## Step 2: Get a temporary AWS access key

You have two options. Pick one.

**Option 1 — `aws sso login` (preferred if you use SSO):**

```bash
aws sso login
```

This opens your browser. Authenticate. Credentials get written to `~/.aws/credentials` for ~12 hours.

**Option 2 — Long-lived access key:**

1. Console → IAM → Users → your user → Security credentials → Create access key
2. Pick "Command Line Interface (CLI)"
3. Copy the **Access Key ID** and **Secret Access Key** (you'll see the secret only once)

Then check what's in your credentials file:

```bash
cat ~/.aws/credentials
```

You should see `aws_access_key_id` and `aws_secret_access_key`. Copy these values — you'll paste them into `.env` next.

---

## Step 3: Create the `.env` file

In `day7/project1/`, copy the sample:

```bash
cp .env-sample .env
```

Open `.env` and fill it in:

```
AWS_ACCESS_KEY_ID=<paste from credentials file>
AWS_SECRET_ACCESS_KEY=<paste from credentials file>
AWS_REGION=ap-south-1

SENDER_EMAIL=<your verified sender>
RECIPIENT_EMAILS=<your verified recipient>
```

You can leave `CHECK_INTERVAL`, `ALERT_COOLDOWN`, `BUFFER_TIMEOUT` commented out for now — defaults are fine.

---

## Step 4: Make sure `.env` does not go to Git

Open `.gitignore` in the project root. Confirm `.env` is listed (NOT commented out):

```
.env
```

If it's not there, add it. Save. This prevents your real credentials from being pushed to GitHub.

The `.env-sample` file is fine to commit — it has no real values.

---

## Step 5: Read the compose file before you run it

Open `docker-compose.yaml` and walk through it. Identify:

- The 5 services
- Which service exposes which port to your host (`db` 5432, `webapp` 8080, `monitor` 8001)
- The `depends_on` relationships (webapp depends on db being healthy)
- The `healthcheck` on the webapp
- The CPU/memory `limits` on the webapp (1 CPU, 1024MB) — this is what makes it easy to push the app into unhealthy state
- The shared volumes for `./logs` so monitor writes alerts and alert-service reads them
- Where `.env` values get injected into the `alert-service` environment

This 5-minute read will save you 30 minutes of debugging later.

---

## Step 6: Start the stack

From the `day7/project1/` directory:

```bash
docker compose up -d --build
```

The `--build` is needed the first time because three of the services build from local Dockerfiles.

Check everything is up:

```bash
docker compose ps
```

You should see `db`, `flask-app`, `app-monitor`, `alert-service`, and the stress generator. Wait until `db` and `flask-app` show **healthy** in the status column.

If anything is not healthy after 30 seconds, check its logs:

```bash
docker compose logs <service-name>
```

---

## Step 7: Open the dashboard

In your browser:

```
http://localhost:8001
```

You'll see:
- Container status (running/stopped)
- Live CPU and memory gauges
- Response time
- Charts for latency, uptime, resource usage
- Recent alerts panel

Keep this tab open.

---

## Step 8: Open the web app

In a second browser tab:

```
http://localhost:8080
```

You'll see the Flask app with buttons:
- Run CPU Test
- Run Memory Test
- Run Database Test
- Run Combined Test

Don't click anything yet. Just confirm the page loads.

---

## Step 9: Watch the stress generator do its thing

The `stress-generator` service is already hammering the webapp with `STRESS_LEVEL=high` (50 threads). Switch to the dashboard tab and watch for 1–2 minutes. You should see:

- CPU climbing toward 100%
- Memory climbing toward 100%
- Response time spiking
- Status flipping to **unhealthy** when limits are hit

This is the system being pushed past its 1-CPU / 1GB ceiling.

---

## Step 10: Trigger a heavier load manually

In the webapp tab (`localhost:8080`), click **Run DB Test**. This makes 1000 DB operations in a single request and pushes the app harder.

Back on the dashboard, watch:
- CPU spike
- Memory spike
- Container health flip to unhealthy
- New alerts appear in the Recent Alerts panel

---

## Step 11: Check your email

Open your recipient inbox. Check spam folder too. You should see emails with subjects like:

- `⚠️ WARNING: monitored-app Alert` (for high CPU / slow response)
- `🚨 CRITICAL: monitored-app Alert` (when health check fails)

Open one. Notice:
- Each alert type is grouped
- Frequency counters at the bottom
- The body shows timestamps and threshold violations

You won't get an email for every single alert — the alert-service buffers them (60 seconds default) and rate-limits per alert type (5 minutes cooldown). This is intentional. You don't want 100 emails when one outage happens.

---

## Step 12: Inspect the alert log directly

```bash
cat day7/project1/logs/container_alerts.log
```

Compare what's in the log vs what you got in email. The log has more entries — the alert-service is filtering on purpose.

Also look at the metrics CSV:

```bash
head -20 day7/project1/logs/container_metrics.csv
tail -20 day7/project1/logs/container_metrics.csv
```

This is the raw time-series data the dashboard is reading.

---

## Step 13: Restart a single service (not the whole stack)

In real ops, you rarely bounce the entire stack. Try restarting only the stress generator:

```bash
docker compose restart stress-generator
```

Or change its load level and recreate just that one:

1. Edit `docker-compose.yaml`, change `STRESS_LEVEL=high` to `STRESS_LEVEL=low`
2. Run:

```bash
docker compose up -d stress-generator
```

Compose detects the config change and recreates only that container. The others keep running. Verify on the dashboard — CPU should drop.

---

## Step 14: Tweak alert thresholds

Edit `docker-compose.yaml` under the `monitor` service:

```yaml
- CPU_THRESHOLD="40"
- MEMORY_THRESHOLD="50"
- RESPONSE_TIME_THRESHOLD=1000
```

Try lowering `CPU_THRESHOLD` to `20` and `RESPONSE_TIME_THRESHOLD` to `200`. Restart only the monitor:

```bash
docker compose up -d monitor
```

Now you'll get alerts on much lighter load. Useful for understanding how threshold tuning works in real systems.

---

## Step 15: Tear it down

```bash
docker compose down
```

If you want to also wipe the postgres volume:

```bash
docker compose down -v
```

---

## Part A Reflection Questions

Before moving on, make sure you can answer these without looking:

1. Why do we put credentials in `.env` instead of `docker-compose.yaml` directly?
2. Why does the alert-service buffer and cool down alerts instead of sending one per event?
3. Why do warning emails and critical emails have different subject lines?
4. If you wanted to send Slack alerts instead of email, which file would you change?
5. Why is Docker Compose not used in production for this kind of app?

---

# Part B: First Container on AWS ECS (Fargate)

## Goal

Run a single `nginx` container on ECS using Fargate. No service yet — just a one-shot task to understand the building blocks: cluster, task definition, task.

---

## Step 1: Create a CloudWatch log group

Before creating the task, create the log group manually. This avoids the timing issue we saw in class where the task fails on first run because the log group doesn't exist yet.

1. Console → CloudWatch → Log groups → **Create log group**
2. Name: `/ecs/nginx-demo`
3. Retention: 1 day (this is a demo — don't keep logs forever)
4. Create

---

## Step 2: Create the ECS cluster

1. Console → ECS → Clusters → **Create cluster**
2. Cluster name: `nginx-demo`
3. Infrastructure: leave **AWS Fargate** checked (the default)
4. Uncheck Container Insights for now
5. Create

Cluster creation is logical — no compute is provisioned, no cost yet.

---

## Step 3: Create the task definition

1. ECS → Task definitions → **Create new task definition**
2. Family name: `nginx-demo`
3. Launch type: **AWS Fargate**
4. Operating system: Linux/X86_64
5. CPU: `0.25 vCPU`
6. Memory: `1 GB`
7. Task role: leave empty (the container isn't calling AWS services)
8. Task execution role: choose **Create new role** (or use existing `ecsTaskExecutionRole` if you have one). This gives the task permission to pull from ECR and write to CloudWatch.

### Container definition

9. Container name: `nginx`
10. Image URI: `nginx` (public Docker Hub image, no auth needed)
11. Port mapping: container port `80`, protocol TCP
12. Skip environment variables, mount points, health check for now
13. Logging: **Use log collection**, driver `awslogs`, log group `/ecs/nginx-demo`, region `ap-south-1` (your region)
14. Create

---

## Step 4: Find or create a security group that allows port 80

1. Console → VPC → Security groups
2. Either pick an existing group with port 80 open from `0.0.0.0/0`, or create a new one:
   - Name: `ecs-nginx-demo-sg`
   - VPC: default VPC
   - Inbound rule: HTTP (port 80) from `0.0.0.0/0`
   - Create

Note the security group ID.

---

## Step 5: Run the task

1. ECS → Clusters → `nginx-demo` → **Tasks** tab → **Run new task**
2. Compute: Launch type → **Fargate**, platform version Latest
3. Application type: **Task** (not Service — we'll do Service tomorrow)
4. Task definition family: `nginx-demo`, revision: latest
5. Desired tasks: `1`
6. Networking:
   - VPC: default
   - Subnets: pick the public subnets
   - Security group: select the one from Step 4
   - **Public IP: ENABLED**
7. Create

---

## Step 6: Wait for the task to start

Refresh the Tasks tab. Watch the status:

- `PROVISIONING` → Fargate is allocating compute
- `PENDING` → image being pulled
- `RUNNING` → container is up

This usually takes 30–90 seconds.

---

## Step 7: Hit the nginx container

1. Click the task → find **Public IP** in the configuration section
2. In your browser: `http://<public-ip>`
3. You should see the nginx welcome page

If it doesn't load, check:
- Security group actually allows port 80 from `0.0.0.0/0`
- Task status is RUNNING and health is HEALTHY
- You're using HTTP, not HTTPS

---

## Step 8: Check the logs

1. Task → Logs tab (or open CloudWatch → Log groups → `/ecs/nginx-demo`)
2. You should see nginx access logs for the request you just made

Logs are mandatory in real systems. If you skip the log group config, you can't debug anything when something fails.

---

## Step 9: Test self-healing (manual stop, observe)

This is a single task, not a service. Stop it and confirm it does NOT come back:

1. Task → Stop
2. Wait. Refresh.
3. The task goes to STOPPED. No new task appears.

This is why services exist. A standalone task is for one-shot jobs. For long-running web apps, you wrap a task in a service so ECS keeps it alive. We'll do that tomorrow.

---

## Step 10: Clean up

You don't want a forgotten task running and costing you money.

1. Stop any running tasks in the cluster
2. (Optional) Delete the cluster
3. (Optional) Delete the task definition (you have to deregister all revisions first)
4. (Optional) Delete the CloudWatch log group
5. (Optional) Delete the security group

Fargate billing is per-second while a task runs. Even one forgotten `nginx` task costs a few dollars a month.

---

## Part B Reflection Questions

1. Why did we create the log group BEFORE the task instead of letting ECS create it?
2. What's the difference between **task role** and **task execution role**?
3. Why doesn't a stopped task auto-restart? What would change that behavior?
4. If you needed to run the same nginx container on your own EC2 instances instead of Fargate, what would change in the task definition?
5. The container port is 80. There's no host port mapping like in Docker Compose. Why?

---

# Bonus Reading

Before tomorrow's class, read this blog post end to end:

https://akhileshmishra.substack.com/p/let-me-teach-you-running-containers


Also watch one short YouTube video on ECS Fargate basics. Pick any — the goal is repetition of the same concepts in someone else's words.

Tomorrow we go deeper:
- ECS **services** (not just tasks): self-healing, scaling, rolling updates
- Load balancer in front (ALB) — proper HTTPS, no exposed task IPs
- Public vs private subnets for tasks
- Real 2-tier app with RDS instead of standalone containers

Come ready.

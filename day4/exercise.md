# Week 2 Day 4 Assignment: RDS + Auto Scaling Group + ALB + Route 53 + HTTPS

**Bootcamp:** Advanced DevOps + MLOps + AIOps — April 2026 Batch
**Module:** AWS Compute, Database & Edge Networking
**Estimated time:** 6–8 hours
**Region:** `ap-south-1` (Mumbai)
**Prerequisite:** Completed Day 3 assignment — your `bootcamp-vpc` from yesterday must be alive.

---

## Learning objectives

This is the assignment where everything from Week 1 and Week 2 comes together. By the end, you will have rebuilt your Day 2 single-EC2 app (app + DB on one box) into a real production-shaped architecture:

- A **PostgreSQL RDS** instance restored from your Day 2 S3 backup
- An **Auto Scaling Group** running the same Flask app behind a launch template
- An **Application Load Balancer** distributing traffic across two AZs
- A **Route 53** record pointing your subdomain to the ALB
- An **ACM-issued TLS certificate** terminating HTTPS at the ALB
- **Scaling policies** so your ASG actually scales

You will also feel the pain of `user_data` scripts not working the way you expect. That pain is the lesson.

---

## Architecture you are building

```
                                Users (HTTPS)
                                      │
                                      ▼
                            app.<yourdomain>.com
                                      │
                                  Route 53
                                  (A record alias)
                                      │
                                      ▼
                  ┌──────────────────────────────────────────┐
                  │   Application Load Balancer (internet)    │
                  │   Listeners: 80 → redirect, 443 → TG      │
                  │   Cert from ACM, security group: 80/443   │
                  └──────────────────┬───────────────────────┘
                                      │
                              Target Group (port 8000)
                                      │
                ┌─────────────────────┴─────────────────────┐
                │                                           │
                ▼                                           ▼
        ┌──────────────┐                            ┌──────────────┐
        │  EC2 (priv-1)│                            │  EC2 (priv-2)│
        │  app:8000    │                            │  app:8000    │
        │  ASG-managed │                            │  ASG-managed │
        └──────┬───────┘                            └──────┬───────┘
               │                                           │
               └──────────────────┬────────────────────────┘
                                  │
                                  ▼
                           NAT Gateway (for git clone, yum install)
                                  │
                          ┌───────┴───────┐
                          │               │
                          ▼               ▼
                   ┌──────────────┐  ┌──────────────┐
                   │  PostgreSQL  │  │  S3 Bucket   │
                   │  RDS (priv)  │  │  (Day 2      │
                   │  port 5432   │  │   backup)    │
                   └──────────────┘  └──────────────┘
```

---

## Pre-flight checks

Before you start, confirm from Day 3:

1. `bootcamp-vpc` (10.0.0.0/16) exists with all 6 subnets
2. `bootcamp-igw` is attached to the VPC
3. `bootcamp-public-rt` has a 0.0.0.0/0 → IGW route, associated with public-1 and public-2
4. `bootcamp-private-rt` has a 0.0.0.0/0 → NAT Gateway route, associated with private-1 and private-2
5. NAT Gateway is alive in public-2 with an Elastic IP attached (re-create if you cleaned up after Day 3)
6. Your S3 bucket from Day 2 with `mydb_backup.dump` is still accessible
7. You own a domain (or a subdomain) hosted in Route 53 — if not, set this up first or skip Parts 6 and 7

If any of these are missing, fix them before continuing. Don't try to debug ASG health checks against a broken VPC — you will lose hours.

---

## Part 1 — Pick the right RDS architecture (no clicking yet)

Before you create anything, write down in `answers.md` which of these you would pick for these scenarios. One sentence each — why.

| Scenario | Single-AZ | Multi-AZ standby | Multi-AZ cluster (1 writer + 2 readers) | Aurora Serverless |
|---|---|---|---|---|
| Personal blog, 200 visits/day | | | | |
| Hospital OT scheduling app, low traffic but zero downtime tolerated | | | | |
| E-commerce site, read-heavy, traffic spikes on Fridays | | | | |
| Internal report tool, used 30 min/day, idle the rest | | | | |
| Discord-like product needing millions of small DBs | | | | |

The Discord row is a trap — RDS is the wrong answer. Say so.

**Also explain:** Why is a database fundamentally a *single-writer* system by default? What does "sharding" solve and why is it usually done at the application layer, not the infra layer?

---

## Part 2 — Create the RDS instance

### Task 2.1 — Subnet group

RDS needs subnets in at least two AZs even if you're running Single-AZ. We pre-built `rds-1` and `rds-2` exactly for this.

1. **RDS Console → Subnet groups → Create**
2. Name: `bootcamp-rds-subnets`
3. VPC: `bootcamp-vpc`
4. Availability Zones: `ap-south-1a`, `ap-south-1b`
5. Subnets: `rds-1` (10.0.5.0/24), `rds-2` (10.0.6.0/24)

### Task 2.2 — RDS security group

1. **EC2 → Security Groups → Create**
2. Name: `bootcamp-rds-sg`, VPC: `bootcamp-vpc`
3. Inbound: PostgreSQL (5432) from **source = sg of `bootcamp-asg-sg`** (you'll create that SG in Part 3 — leave this blank now and come back, or pre-create the empty SG)
4. Outbound: leave default (all traffic)

**Why this matters:** The transcript shows Akhilesh temporarily opening 5432 to `0.0.0.0/0` to debug. Don't leave it that way. SG-to-SG references are how you keep RDS truly private.

### Task 2.3 — Create the database

1. **RDS → Create database → Standard create**
2. Engine: **PostgreSQL**, version 15.x (do not pick the absolute latest; enterprises lag a version or two on purpose)
3. Templates: **Production** (so you see all the options) — but we'll downgrade settings to keep cost low
4. Availability: **Single DB instance** (not Multi-AZ — keeping cost down)
5. DB instance identifier: `bootcamp-db`
6. Master username: `postgres`
7. Master password: set one and **save it in your notes** — you'll need it
8. Instance class: `db.t3.micro` or `db.t4g.micro` (free-tier eligible)
9. Storage:
   - Type: **gp3**
   - Allocated: 20 GB
   - **Disable** storage autoscaling
10. Connectivity:
    - VPC: `bootcamp-vpc`
    - Subnet group: `bootcamp-rds-subnets`
    - Public access: **No**
    - Security group: `bootcamp-rds-sg`
    - AZ: `ap-south-1a`
    - Port: 5432
11. Database authentication: Password authentication
12. Additional configuration:
    - Initial database name: `mydb`
    - Backups: disable for this exercise (in real prod: enable with 7-day retention)
    - Performance Insights: disable (it costs money)
    - Encryption: keep enabled, default KMS key
13. Create database

This takes 5–10 minutes. While you wait, do Part 3.

### Task 2.4 — Concept check (write in `answers.md`)

1. Look at the storage type options (gp2, gp3, io1, io2, magnetic). Explain in your own words: for a 100 GB database getting hammered with writes, why does the **disk** matter more than CPU/RAM? What does IOPS mean and why does it scale with disk size?
2. What is **connection pooling**? If your app makes 1,000 concurrent DB connections at ~10 MB each, what's the rough memory cost on the DB server? How does a 50-connection pool change that math?
3. Look at the **encryption at rest** option. AWS-managed KMS key vs customer-managed KMS key vs CloudHSM-imported key — when would you choose each?

---

## Part 3 — Security groups for the app tier

You need three security groups. Create them all up front so you can reference them by ID:

| Name | Inbound rules |
|---|---|
| `bootcamp-alb-sg` | 80 from 0.0.0.0/0, 443 from 0.0.0.0/0 |
| `bootcamp-asg-sg` | 8000 from `bootcamp-alb-sg`, 22 from `bootcamp-bastion-sg` (Day 3) |
| `bootcamp-rds-sg` | 5432 from `bootcamp-asg-sg` (update the SG you created in Part 2) |

**Critical:** the ASG SG inbound for port 8000 must reference the **ALB SG ID**, not `0.0.0.0/0`. This is the whole point of layered security. Don't take the lazy shortcut.

Now go back to `bootcamp-rds-sg` and update its inbound rule to reference `bootcamp-asg-sg` as the source.

---

## Part 4 — Restore the Day 2 backup into RDS

The trick here: RDS is private. You can't reach it from your laptop. You'll do the restore from your Day 3 bastion host, which is in the same VPC.

### Task 4.1 — Install psql client on the bastion

```bash
ssh -i ~/.ssh/bootcamp-key.pem ec2-user@<BASTION_PUBLIC_IP>

# On the bastion:
sudo dnf install -y postgresql15
psql --version
```

Pick a client version equal to or higher than the server version. Lower client versions break `pg_restore` in subtle ways.

### Task 4.2 — Confirm connectivity to RDS

Get the RDS endpoint from the console (something like `bootcamp-db.xxxxx.ap-south-1.rds.amazonaws.com`).

```bash
# On the bastion:
export DB_HOST=<your-rds-endpoint>
export DB_USER=postgres
export DB_NAME=mydb

psql -h $DB_HOST -U $DB_USER -d $DB_NAME
# Enter the master password when prompted

# Once connected:
\dt          # list tables (should be empty)
\du          # list users (only postgres exists)
\q           # quit
```

If this hangs or times out, your security groups are wrong. Check that `bootcamp-rds-sg` allows 5432 from the bastion's SG (you may need to add a rule for the bastion SG too, since the bastion isn't in the ASG SG).

### Task 4.3 — Pull the backup from S3

The bastion already has the IAM role `bootcamp-ec2-s3-role` from Day 3 with S3 read access.

```bash
aws s3 ls s3://<your-day2-bucket>/
aws s3 cp s3://<your-day2-bucket>/mydb_backup.dump /tmp/mydb_backup.dump
ls -lh /tmp/mydb_backup.dump
```

### Task 4.4 — Restore

```bash
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME -v /tmp/mydb_backup.dump
```

Some warnings about role ownership are normal — if your Day 2 dump was owned by a user that doesn't exist in RDS, you'll see notices. As long as the tables come through, you're fine.

### Task 4.5 — Verify

```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Once in:
\dt
SELECT * FROM "user";
SELECT * FROM student;
SELECT * FROM attendance;
\q
```

Take a screenshot of the `\dt` output and one `SELECT` showing rows from your Day 2 data. This proves the restore worked.

**Common gotcha:** If `pg_restore` fails with `relation does not exist` errors, you probably created the dump with `pg_dump --format=plain` instead of `--format=custom`. Plain-text dumps need `psql -f`, not `pg_restore`. The transcript glosses over this — write down which format your Day 2 backup is in.

---

## Part 5 — Launch Template + Auto Scaling Group

### Task 5.1 — Create the launch template

1. **EC2 → Launch Templates → Create**
2. Name: `bootcamp-app-lt`
3. AMI: Amazon Linux 2023
4. Instance type: `t3.micro`
5. Key pair: `bootcamp-key`
6. **Network settings: leave all of this BLANK.** Do not pick a VPC, subnet, or auto-assign IP setting here. The ASG will set network parameters at launch time. The transcript hits exactly this issue — Akhilesh tries to find the public-IP toggle in the launch template UI and can't, because letting the ASG control the network is the correct design.
7. Security group: `bootcamp-asg-sg`
8. IAM instance profile: `bootcamp-ec2-s3-role` (so the instance can pull from S3 if needed)
9. **Advanced details → User data:** paste the script below

### Task 5.2 — User data script

This is where most students lose 1–2 hours. Read it carefully before pasting.

```bash
#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

# Install dependencies
dnf install -y git python3-pip

# Clone app
cd /home/ec2-user
git clone https://github.com/<your-fork>/<repo>.git
cd <repo>/day2/app

# Install python dependencies
pip3 install -r requirements.txt

# Build the DB connection string from instance metadata or hardcode for now
# Format: postgresql://USER:PASSWORD@HOST:5432/DBNAME
export DB_LINK="postgresql://postgres:<YOUR_DB_PASSWORD>@<YOUR_RDS_ENDPOINT>:5432/mydb"

# Start the app on port 8000 in the background
# Note: the run.sh approach from class did not reliably work in user_data.
# We invoke gunicorn directly to avoid the issue.
nohup gunicorn -b 0.0.0.0:8000 app:app > /var/log/app.log 2>&1 &
```

**Three things will go wrong here. Document each in `gotchas.md` when they hit you:**

1. **`pip3 install` fails** because Python 3.11 doesn't always have all the wheels you expect on AL2023. Fix: `pip3 install --break-system-packages -r requirements.txt`, or use a venv.
2. **`run.sh` works manually but not from user_data.** Several students hit this in the transcript. The fix is to run `gunicorn` directly instead of going through `run.sh`. The reason is non-obvious — it's about how user_data shells handle backgrounded processes and PATH.
3. **The app starts but crashes connecting to the DB.** Almost always one of: wrong RDS endpoint, wrong password, RDS SG not allowing 5432 from ASG SG, or the env var not exported in the right scope.

To debug, SSH into the launched instance via the bastion and check `/var/log/user-data.log` and `/var/log/app.log`. Also try `journalctl -u cloud-final` if user_data didn't run at all.

### Task 5.3 — Test the launch template before creating the ASG

This is the step the transcript skips at first and pays for later. **Do this:**

1. Launch a single EC2 from the template, manually placing it in `private-1`
2. SSH in via the bastion
3. Check `tail -100 /var/log/user-data.log`
4. Confirm `curl http://localhost:8000/login` returns HTML
5. Once it works, terminate the test instance

If you skip this step you will spend an hour debugging an ASG that's spinning up unhealthy instances in a loop, and ASG instance-replacement makes debugging much harder than a single static EC2.

### Task 5.4 — Create the Auto Scaling Group

1. **EC2 → Auto Scaling Groups → Create**
2. Name: `bootcamp-asg`
3. Launch template: `bootcamp-app-lt`, version: Latest
4. **Network:**
   - VPC: `bootcamp-vpc`
   - Availability Zones and subnets: `private-1`, `private-2`
   - Distribution: Balanced best effort
5. **Load balancing:** No load balancer (we'll attach in Part 6)
6. **Health checks:** EC2 only for now (we'll add ALB health checks after attaching the LB)
7. **Group size:**
   - Desired: 1
   - Minimum: 1
   - Maximum: 3
8. **Scaling:** No scaling policies yet (Part 8)
9. Skip notifications, tags
10. Create

### Task 5.5 — Wait and verify

The ASG will launch one instance. Wait until its status is `InService`. SSH into it via the bastion and confirm the app is up on port 8000.

---

## Part 6 — Application Load Balancer

### Task 6.1 — Target group first

The transcript explains the ALB → Listener → Target Group → instances chain clearly. Build it in that order.

1. **EC2 → Target Groups → Create**
2. Type: Instances
3. Name: `bootcamp-app-tg`
4. Protocol: HTTP, Port: 8000
5. VPC: `bootcamp-vpc`
6. Health check:
   - Protocol: HTTP
   - Path: `/login` (the app redirects `/` to `/login`, and `/login` reliably returns 200 — the transcript settles on this)
   - In real apps you would build a dedicated `/health` endpoint that doesn't hit the DB. Note this in `answers.md`.
   - Healthy threshold: 2, unhealthy: 2, timeout: 5s, interval: 30s
7. **Skip the "Register targets" step** — the ASG will register them automatically once you attach it.
8. Create

### Task 6.2 — Create the ALB

1. **EC2 → Load Balancers → Create → Application Load Balancer**
2. Name: `bootcamp-alb`
3. Scheme: Internet-facing
4. IP type: IPv4
5. VPC: `bootcamp-vpc`
6. Mappings: `ap-south-1a` → `public-1`, `ap-south-1b` → `public-2`
7. Security group: `bootcamp-alb-sg`
8. Listeners: HTTP:80 → forward to `bootcamp-app-tg`
9. Create

### Task 6.3 — Attach the ASG to the target group

1. **EC2 → Auto Scaling Groups → bootcamp-asg → Edit**
2. Load balancing: Attach to existing load balancer → choose `bootcamp-app-tg`
3. Health check type: change to **ELB** (so the ASG replaces instances that fail the ALB health check, not just the EC2-level check)
4. Health check grace period: 300 seconds (gives user_data time to finish)
5. Save

### Task 6.4 — Verify

1. Wait until the target group shows the instance as `healthy` (this can take 1–3 minutes)
2. Copy the ALB DNS name (something like `bootcamp-alb-xxxxx.ap-south-1.elb.amazonaws.com`)
3. Open it in a browser. You should see the login page served through the ALB.

If the target shows as `unhealthy`, the usual culprits are:
- ASG SG isn't allowing 8000 from ALB SG
- Health check path returns 302 (redirect) instead of 200 — set the matcher to `200,302` if needed
- The app didn't start (check `/var/log/app.log` on the instance)

---

## Part 7 — Route 53 + ACM (HTTPS)

### Task 7.1 — Request the certificate

1. **AWS Certificate Manager → Request a public certificate**
2. Domain: `app.<yourdomain>.com` (use a subdomain you own)
3. Validation: DNS validation
4. Key algorithm: RSA 2048
5. **Disable export** (it costs money)
6. Request
7. On the certificate page, click **Create records in Route 53** — ACM will auto-create the CNAME validation record if your domain is in Route 53. Wait until status becomes `Issued` (1–5 minutes).

### Task 7.2 — Route 53 alias record

1. **Route 53 → Hosted zones → your domain → Create record**
2. Record name: `app`
3. Record type: A
4. **Alias: ON**
5. Route traffic to: Alias to Application and Classic Load Balancer → `ap-south-1` → `bootcamp-alb`
6. Routing policy: Simple routing
7. Create

**Concept check (write in `answers.md`):** Look at the routing policy options — Simple, Weighted, Latency, Failover, Geolocation, Geoproximity, Multivalue, IP-based. For each, give a one-sentence real use case. The transcript explicitly assigns this as homework.

### Task 7.3 — Add the HTTPS listener to the ALB

1. **EC2 → Load Balancers → bootcamp-alb → Listeners → Add listener**
2. Protocol: HTTPS, Port: 443
3. Default action: Forward to `bootcamp-app-tg`
4. Security policy: ELBSecurityPolicy-TLS13-1-2-2021-06 (the current AWS default)
5. SSL certificate: From ACM → select the certificate you just issued
6. Add

### Task 7.4 — Redirect HTTP to HTTPS (optional but standard)

1. Edit the existing port 80 listener
2. Change the default action from "Forward" to "Redirect" → HTTPS, port 443, status code 301
3. Save

### Task 7.5 — Test

```bash
nslookup app.<yourdomain>.com
curl -I https://app.<yourdomain>.com/login
curl -I http://app.<yourdomain>.com/login   # should return 301
```

Open `https://app.<yourdomain>.com` in a browser. You should see your app served over HTTPS with a valid cert. Take a screenshot showing the padlock.

---

## Part 8 — Scaling policies

### Task 8.1 — Pick a metric

1. **EC2 → Auto Scaling Groups → bootcamp-asg → Automatic scaling → Create dynamic scaling policy**
2. Policy type: **Target tracking scaling**
3. Metric: **Average CPU utilization**
4. Target value: 50%
5. Instance warmup: 100 seconds

### Task 8.2 — Validate it works

The transcript covers this conceptually but doesn't actually run a load test. You will. Install a simple load tool on your laptop:

```bash
# Mac
brew install hey

# Run a 5-minute load test
hey -z 5m -c 50 https://app.<yourdomain>.com/login
```

Watch the ASG console — within a few minutes, you should see CPU climb past 50% and the desired capacity scale up to 2, then 3. Stop the load test and watch it scale back down (this takes ~5 min by default).

Take a screenshot of the **Activity** tab on your ASG showing the scale-out and scale-in events.

### Task 8.3 — Concept check

Write in `answers.md`:

1. Why is **CPU-based scaling alone often the wrong policy** for production? Give two scenarios from the transcript (Uber-pattern, Medium-pattern, Black Friday) where you'd want a different approach.
2. What is a **scheduled scaling policy** and when does it beat dynamic scaling?
3. Explain the **cooldown period** and why a 100-second warmup matters (hint: think about what an instance is doing during user_data).

---

## Part 9 — Bonus: Load testing with k6

The transcript mentions k6 from Grafana as the tool Akhilesh wants to use going forward. Set it up now so you're ready.

1. Install k6: `brew install k6`
2. Write a simple test script `loadtest.js`:

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '2m', target: 50 },
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  const res = http.get('https://app.<yourdomain>.com/login');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

3. Run: `k6 run loadtest.js`
4. Capture the output showing p95 latency, RPS, and error rate.

Compare what you see against the ASG scaling activity. Was scaling fast enough? What's the gap between traffic spike and capacity arriving?

---

## Cleanup (do this when done — billing pile-up is real)

Delete in this order:

1. Route 53 record (`app.<yourdomain>.com` A record)
2. ACM certificate
3. ALB → wait until fully deleted
4. Target group
5. Auto Scaling Group → wait until instances terminate
6. Launch template
7. RDS instance (uncheck "create final snapshot" to skip the snapshot — for real prod, never skip this)
8. RDS subnet group
9. NAT Gateway → release Elastic IP
10. Security groups (`asg-sg`, `alb-sg`, `rds-sg`)
11. Bastion EC2 if not needed for Day 5

Keep the VPC, IGW, subnets, and route tables for Week 3. Containers next week will reuse them.

---

## Submission

Folder `week2-day4-submission/` with:

1. **`screenshots/`** at minimum:
   - RDS instance details page showing Single-AZ, gp3, port 5432, private
   - `\dt` output and a `SELECT` from the restored DB
   - Launch template version 1 details
   - ASG with one healthy instance in `private-1`
   - Target group showing healthy targets after ALB attach
   - ALB DNS name returning the login page in a browser
   - Route 53 record pointing to the ALB
   - ACM certificate in `Issued` state
   - Browser address bar showing `https://app.<yourdomain>.com` with padlock
   - ASG Activity tab showing scale-out and scale-in during load test

2. **`answers.md`** — every concept-check question, answered in your own words

3. **`gotchas.md`** — every issue that hit you and how you fixed it. Be specific. "User data didn't work, fixed it" is not useful. "User data ran but `pip install` failed because of PEP 668; fixed by adding `--break-system-packages`" is.

4. **`reflection.md`** answering:
   - Why does the bootcamp deliberately do this with the console before Terraform? What would change if you did it with Terraform from day one?
   - In your own words, what is the difference between the EC2 health check and the ELB health check on an ASG? Which one would have replaced an instance with a hung gunicorn process?
   - The ALB security group allows 0.0.0.0/0 on 443, but the ASG security group only allows 8000 from the ALB security group. Walk through what this restriction actually protects against.
   - A teammate proposes putting the database in a private subnet of the same route table as the app tier (skipping the dedicated `rds-1`/`rds-2` subnets). What's lost? Reference NACLs in your answer.

5. **Diagram** — re-draw the architecture from memory in draw.io or excalidraw. Don't copy mine. Yours should show every SG-to-SG reference and the routing path for HTTPS traffic from a user's laptop to your gunicorn process.

Submit by **end of Sunday**. Anyone who lags by more than one week will have a hard time catching up — Week 3 is containers and assumes everything in Weeks 1–2 is already in your hands.

---

## Common gotchas (read these now, save yourself two hours)

- **The launch template's network settings field is a trap.** Leave it empty. The ASG manages networking. The transcript's Akhilesh-can't-find-the-public-IP-toggle moment is 5 minutes of class time you should learn from.
- **`run.sh` works on a manually-launched VM but not in user_data.** Run `gunicorn` directly. Don't fight it.
- **`DB_LINK` environment variable is empty after `su` or after a sub-shell.** Export inside the same shell where you start gunicorn, or write it into a systemd unit file (better solution for Week 3).
- **Health check path returns a 302.** Either set the matcher to `200,302` or build a real `/health` endpoint that returns 200 on a DB ping.
- **RDS endpoint not resolving from the bastion.** RDS endpoints only resolve from inside the VPC (you'll get a private IP from `nslookup`). If you're trying to connect from your laptop, that's the bug.
- **`pg_restore` quietly fails on role ownership.** Add `--no-owner --no-acl` flags if your Day 2 dump was created as a different user.
- **ACM certificate stuck in "Pending validation".** The CNAME record didn't propagate. Wait 5 minutes, refresh. If it's been 30 minutes, your hosted zone isn't actually authoritative — check the NS records at your registrar.
- **HTTPS listener fails to attach the cert.** The cert must be in the same region as the ALB. ACM is regional. There is no cross-region cert sharing.
- **Scale-in never happens.** Default target tracking is conservative. It takes 15 minutes of low CPU to scale in. Don't wait around — verify with the Activity tab.
- **NAT Gateway data costs.** If your ASG is pulling large container images or `pip install`-ing huge wheels through NAT, that's per-GB charges. In Week 3 we'll switch to ECR with a VPC endpoint.

---

## What's coming next week

Week 3: **Containers — Docker, ECR, ECS on Fargate.** We'll take the same Flask app, containerize it, push to ECR, and run it on ECS Fargate behind an ALB. The VPC, ALB pattern, target groups, Route 53 record, and ACM cert all carry over directly. The only piece that goes away is the EC2 launch template — Fargate doesn't need it.

Make sure you finish this assignment **before next Saturday's class**. The container module assumes you understand target groups, listener rules, and security group chains cold.

— Akhilesh
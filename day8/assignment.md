# Assignment: Deploy a 2-Tier App to ECS Fargate (Production-Style)

This is the proper way to deploy ECS. Yesterday you ran a single task and saw the basics. Today you build the full thing — custom VPC, NAT gateway, ECR, RDS, ALB with HTTPS, Secrets Manager, autoscaling.

I hit several bugs live in class. This assignment removes that pain. Follow the order. Don't skip.

The app is the 2-tier student portal from `day8/2-tier-app/`. Flask + Postgres. Same one in the repo.

---

## What you're building

A diagram you should be able to draw from memory by the end:

```
Internet
   |
   v
Route53 (yourdomain.com) -> ACM cert
   |
   v
ALB (public subnets, 2 AZs, HTTPS:443)
   |
   v
Target Group (IP type, port 8000, /login health check)
   |
   v
ECS Service (Fargate, 2 tasks, private subnets, 2 AZs)
   |               |
   v               v
RDS Postgres    NAT Gateway (public subnet) -> Internet -> ECR
(db subnets)
```

Security groups stack:
- ALB SG: inbound 443 from `0.0.0.0/0`
- ECS SG: inbound 8000 from ALB SG only
- RDS SG: inbound 5432 from ECS SG only

---
<img width="2302" height="1286" alt="image" src="https://github.com/user-attachments/assets/35acc0ce-1ec6-4441-a531-aa71a68dd663" />

## Prerequisites

- Custom VPC already built from the VPC class (public subnets, private app subnets, private DB subnets, IGW, route tables)
- A domain in Route53 you own
- An ACM certificate already issued for a subdomain (e.g. `*.yourdomain.com` or `app.yourdomain.com`)
- AWS CLI v2.32+ installed (for `aws sso login`)
- Docker installed on your laptop
- The `day8/2-tier-app` code

If you don't have a domain and ACM cert, get them done first. Without them you can only test on the raw ALB DNS name with HTTP.

---

# Part 1: Prep AWS Account

## Step 1: Log in to AWS CLI the right way

Don't paste long-lived access keys into your terminal. Use short-lived ones.

```bash
aws --version
```

Must be `2.32` or higher. If not, upgrade first (`brew install awscli` for Mac, or download from the official AWS installer page).

Then:

```bash
aws sso login
```

Browser opens. Authenticate. Credentials get written to `~/.aws/credentials` and expire in 12 hours.

Verify:

```bash
aws sts get-caller-identity
```

You should see your account number and user/role ARN.

If you don't have SSO set up and you must use long-lived keys, fine — but rotate them every 1–2 days. Never commit them.

---

## Step 2: Verify VPC setup

Open VPC console. Confirm you have:

- VPC CIDR `10.0.0.0/16` (or whatever you used)
- 2 public subnets in 2 different AZs (e.g. `1a`, `1b`)
- 2 private app subnets in 2 different AZs
- 2 private DB subnets in 2 different AZs
- 1 Internet Gateway attached to the VPC
- Public route table with `0.0.0.0/0` -> IGW, attached to both public subnets
- Default route table (or private route table) attached to private subnets — currently no internet route

If anything is missing, fix it before going further.

---

## Step 3: Create the NAT Gateway BEFORE the ECS service

This is the single biggest pain point. If you create ECS first, the task will fail to pull from ECR because the private subnet has no internet route. Do it now.

1. VPC console → NAT Gateways → **Create NAT gateway**
2. Name: `ecs-nat-gw`
3. Subnet: pick **one** of your **public** subnets
4. Connectivity: Public
5. Elastic IP: click **Allocate Elastic IP**
6. Create

Wait until status is **Available** (1–2 minutes).

For real production you'd create 2 NAT gateways (one per AZ) for HA. For this assignment, one is fine — saves cost. The route table fix below handles both private subnets through this one NAT.

---

## Step 4: Add NAT route to the private route table

1. VPC → Route tables → pick the route table attached to your **private app subnets** (not the DB ones — DB stays fully isolated)
2. Routes tab → **Edit routes** → **Add route**
3. Destination: `0.0.0.0/0`
4. Target: NAT Gateway → select `ecs-nat-gw`
5. Save

Now confirm under **Subnet associations** that both private app subnets are associated with this route table.

Do NOT touch the DB subnet route tables. They stay private — no NAT, no IGW.

---

## Step 5: Create the CloudWatch log group BEFORE the task definition

I hit this bug live. If the log group doesn't exist when the ECS task first starts, the task fails with `ResourceInitializationError`. Create it now.

1. CloudWatch console → Log groups → **Create log group**
2. Log group name: `/ecs/student-portal`
3. Retention: 7 days (don't keep demo logs forever)
4. Create

---

## Step 6: Verify (or create) the ECS task execution role

1. IAM console → Roles → search `ecsTaskExecutionRole`
2. If it exists, confirm it has the policy `AmazonECSTaskExecutionRolePolicy` attached
3. If it doesn't exist, create it:
   - Trusted entity: AWS service → Elastic Container Service → Elastic Container Service Task
   - Attach policy: `AmazonECSTaskExecutionRolePolicy`
   - Role name: `ecsTaskExecutionRole`
4. Since you'll use Secrets Manager later, **also attach** `SecretsManagerReadWrite` (or a tighter custom policy that allows `secretsmanager:GetSecretValue` on your specific secret ARN — better practice)

This role is what the task uses to:
- Pull from ECR
- Write to CloudWatch
- Read secrets from Secrets Manager

---

# Part 2: Build and Push the Image to ECR

## Step 7: Create the ECR repository

1. ECR console → **Create repository**
2. Visibility: Private
3. Repository name: `student-portal`
4. Image tag mutability: Mutable (fine for learning; immutable for production)
5. Encryption: AES-256 (default)
6. Create

Copy the repository URI. It looks like:

```
<account_id>.dkr.ecr.ap-south-1.amazonaws.com/student-portal
```

---

## Step 8: Build the image with the right platform

You're probably on Mac (ARM). ECS Fargate runs Linux/x86_64. If you skip the platform flag, your image won't run.

From `day8/2-tier-app/`:

```bash
docker build --platform linux/amd64 \
  -t <account_id>.dkr.ecr.ap-south-1.amazonaws.com/student-portal:1.0 .
```

---

## Step 9: Log in to ECR and push

```bash
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin <account_id>.dkr.ecr.ap-south-1.amazonaws.com
```

You should see `Login Succeeded`.

Then push:

```bash
docker push <account_id>.dkr.ecr.ap-south-1.amazonaws.com/student-portal:1.0
```

Wait until it finishes. Go to ECR console and confirm the image is there with tag `1.0`. Note the image size — should be around 200 MB or less.

---

# Part 3: Database (RDS)

## Step 10: Create a DB subnet group

1. RDS console → Subnet groups → **Create DB subnet group**
2. Name: `student-portal-db-subnet-group`
3. VPC: your custom VPC
4. Add the **2 private DB subnets only** (not the app subnets)
5. Create

This pins the database to the DB subnets, isolated from everything else.

---

## Step 11: Create a security group for RDS

1. EC2 → Security groups → **Create security group**
2. Name: `rds-student-portal-sg`
3. VPC: your custom VPC
4. Inbound rules: **leave empty for now** — you'll add a rule after the ECS SG exists
5. Outbound: allow all
6. Create

---

## Step 12: Create the RDS Postgres instance

1. RDS console → Databases → **Create database**
2. Engine: Postgres, version 17 (or latest)
3. Templates: Free tier
4. Settings:
   - DB instance identifier: `student-portal-db`
   - Master username: `postgres`
   - Master password: pick a strong one, save it somewhere — you'll put it in Secrets Manager
5. Instance config: db.t3.micro (or db.t4g.micro)
6. Storage: 20 GB, no autoscaling
7. Connectivity:
   - VPC: your custom VPC
   - DB subnet group: `student-portal-db-subnet-group`
   - Public access: **No**
   - Security group: `rds-student-portal-sg`
   - AZ: pick your primary
   - Port: 5432
8. Additional config:
   - Initial database name: `april`
   - Backup: disable (demo)
   - Performance Insights: disable (saves cost)
   - Encryption: default
9. Create

Wait until status is **Available** (5–10 minutes). Copy the **endpoint** — that's your DB host.

---

## Step 13: Build the DB connection string and store it in Secrets Manager

Your DB link format:

```
postgresql://postgres:<your_password>@<rds_endpoint>:5432/april
```

Now put it in Secrets Manager (don't pass it as a plain env var):

1. Secrets Manager → **Store a new secret**
2. Secret type: **Other type of secret**
3. Key/value pairs:
   - Key: `DB_LINK`
   - Value: the full connection string above
4. Encryption: default AWS KMS key (fine for this; customer-managed in real prod)
5. Secret name: `april/student-portal/db`
6. Disable rotation (for now)
7. Store

Copy the **Secret ARN** — you'll reference it in the task definition.

---

# Part 4: Application Load Balancer

I'm having you build the ALB **before** the ECS service. This way you avoid the UI bug I hit live where the ECS service creation step doesn't let you pick which subnets the ALB lives in.

## Step 14: Create a security group for the ALB

1. EC2 → Security groups → **Create security group**
2. Name: `alb-student-portal-sg`
3. VPC: your custom VPC
4. Inbound rules:
   - HTTPS (443) from `0.0.0.0/0`
   - HTTP (80) from `0.0.0.0/0` (we'll redirect to HTTPS later)
5. Outbound: allow all
6. Create

---

## Step 15: Create a security group for ECS tasks

1. Create another security group
2. Name: `ecs-student-portal-sg`
3. VPC: your custom VPC
4. Inbound rule:
   - Custom TCP, port `8000`, source: `alb-student-portal-sg` (security group reference, NOT `0.0.0.0/0`)
5. Outbound: allow all
6. Create

Now go back to your **RDS security group** (`rds-student-portal-sg`):
- Add inbound rule: PostgreSQL (5432), source: `ecs-student-portal-sg`

Now you have the proper layered security: only ALB can talk to ECS, only ECS can talk to RDS.

---

## Step 16: Create the target group (IP type — important)

1. EC2 → Target groups → **Create target group**
2. Target type: **IP addresses** (NOT instances — Fargate doesn't use EC2)
3. Target group name: `tg-student-portal`
4. Protocol: HTTP
5. Port: `8000`
6. VPC: your custom VPC
7. Protocol version: HTTP1
8. Health checks:
   - Protocol: HTTP
   - Path: `/login`
   - Advanced: success codes `200`
   - Healthy threshold: 2
   - Unhealthy threshold: 2
   - Timeout: 5s
   - Interval: 10s
9. Don't register any targets (ECS will register them automatically when the service is created)
10. Create

Why `/login`? The app redirects `/` to `/login` (302 status code). Health checks expect 200, not 302. Hitting `/login` directly returns 200.

---

## Step 17: Create the Application Load Balancer

1. EC2 → Load balancers → **Create load balancer** → Application Load Balancer
2. Name: `alb-student-portal`
3. Scheme: Internet-facing
4. IP type: IPv4
5. VPC: your custom VPC
6. Mappings: select both **public subnets** (one in each AZ)
7. Security group: `alb-student-portal-sg` (remove the default)
8. Listeners:
   - HTTPS:443 → forward to `tg-student-portal`
   - Pick your ACM certificate from the dropdown
   - Security policy: leave default
9. Create

Wait until state is **Active**. Copy the ALB DNS name.

---

## Step 18: Add HTTP → HTTPS redirect

1. Open the ALB → Listeners tab → **Add listener**
2. Protocol: HTTP, port 80
3. Default action: **Redirect to** HTTPS, port 443, status code 301
4. Add

This way anyone hitting `http://yourdomain.com` gets bounced to `https://`.

---

## Step 19: Point Route53 at the ALB

1. Route53 → Hosted zones → your domain → **Create record**
2. Record name: `app` (or whatever subdomain you want — must match your ACM cert)
3. Record type: A
4. Alias: **Yes**
5. Route traffic to: Alias to Application and Classic Load Balancer → region → `alb-student-portal`
6. Routing policy: Simple
7. Create

DNS may take 1–2 minutes to propagate.

---

# Part 5: ECS Cluster, Task Definition, Service

## Step 20: Create the ECS cluster

1. ECS console → Clusters → **Create cluster**
2. Cluster name: `student-portal-cluster`
3. Infrastructure: **AWS Fargate** only (uncheck others)
4. Uncheck Container Insights (saves cost for now)
5. Create

---

## Step 21: Create the task definition

1. ECS → Task definitions → **Create new task definition**
2. Family name: `student-portal`
3. Launch type: AWS Fargate
4. OS/Architecture: Linux/X86_64
5. CPU: 0.5 vCPU
6. Memory: 1 GB
7. Task role: **leave empty** (the app doesn't call AWS services directly)
8. Task execution role: `ecsTaskExecutionRole` (from Step 6)

### Container

9. Name: `app`
10. Image URI: `<account_id>.dkr.ecr.ap-south-1.amazonaws.com/student-portal:1.0`
11. Port mappings:
    - Container port: `8000`
    - Protocol: TCP
    - App protocol: HTTP
12. **Environment variables — use Secrets Manager, not plain text:**
    - Click **Add environment variable**
    - Key: `DB_LINK`
    - Value type: **ValueFrom**
    - Value: paste the **Secret ARN** from Step 13, append `:DB_LINK::` at the end so it pulls that specific key
    - Example: `arn:aws:secretsmanager:ap-south-1:<account>:secret:april/student-portal/db-aBcDeF:DB_LINK::`
13. Logging: **Use log collection**, awslogs driver
    - Log group: `/ecs/student-portal` (the one you created in Step 5)
    - Region: `ap-south-1`
    - Stream prefix: `app`
    - **Uncheck** "Auto-create log group" — we already created it
14. Create

---

## Step 22: Create the ECS service

1. Cluster `student-portal-cluster` → Services → **Create**
2. Compute: Launch type → Fargate, platform Latest
3. Application type: **Service**
4. Task definition: family `student-portal`, revision latest
5. Service name: `student-portal-svc`
6. Desired tasks: `2`
7. Networking:
   - VPC: your custom VPC
   - Subnets: select **only the 2 private app subnets**
   - Security group: `ecs-student-portal-sg`
   - **Public IP: OFF** (tasks are private, ALB is the entry point)
8. Load balancing:
   - Type: Application Load Balancer
   - Choose **Use an existing load balancer**
   - Load balancer: `alb-student-portal`
   - Listener: use existing → 443:HTTPS
   - Target group: **Use existing** → `tg-student-portal`
9. Service auto scaling: skip for now (you'll add it in the next step)
10. Create

---

## Step 23: Watch it come up

1. Go to the service → Tasks tab
2. Tasks should go PROVISIONING → PENDING → RUNNING
3. If a task fails, click it → Logs tab and read carefully

Common failures and what they actually mean:

- `CannotPullContainerError: ... no such host` → NAT gateway route is wrong (Step 4)
- `ResourceInitializationError: failed to download` → log group missing or wrong name (Step 5)
- `AccessDeniedException` on Secrets Manager → task execution role missing Secrets Manager permission (Step 6)
- Task starts, target group shows unhealthy → security group between ALB and ECS is wrong, or health check path is wrong (Step 15, Step 16)

Once both tasks are RUNNING, go to target group → Targets tab. Both targets should show **healthy** within 30–60 seconds.

---

## Step 24: Hit the app

1. Open `https://app.yourdomain.com` (or whatever subdomain you set)
2. You should see the login page
3. Click Register, create a user, log in
4. Click around — add a student, add an assignment, post an announcement
5. The data should persist (it's in RDS)

If you get a 502 from the ALB, the targets aren't healthy yet. If you get a TLS error, your ACM cert doesn't cover the subdomain you're using.

---

# Part 6: Autoscaling

## Step 25: Configure autoscaling on the service

1. Service `student-portal-svc` → **Update service**
2. Scroll to Service auto scaling → check **Use service auto scaling**
3. Minimum tasks: 1
4. Maximum tasks: 5
5. Add a scaling policy:
   - Policy type: **Target tracking**
   - Policy name: `cpu-target-50`
   - Metric: ECSServiceAverageCPUUtilization
   - Target value: 50
   - Scale-out cooldown: 60 seconds
   - Scale-in cooldown: 300 seconds (longer scale-in is good — don't shrink too fast)
6. Update

Why scale-in cooldown is longer: you don't want to thrash. A brief CPU dip shouldn't kill a task. Wait 5 minutes of low load before scaling down.

---

# Part 7: Validation

You're done when **all** of these are true:

1. `https://app.yourdomain.com` loads the app over HTTPS with a valid certificate
2. `http://app.yourdomain.com` redirects to HTTPS automatically
3. You can register a user, log in, and the data survives a task restart
4. Target group shows 2 healthy targets
5. CloudWatch log group `/ecs/student-portal` has fresh logs streaming in
6. RDS is in private DB subnets with no public access
7. ECS tasks are in private app subnets with no public IP
8. NAT gateway has outbound traffic (check VPC → NAT Gateways → Monitoring tab)
9. RDS security group only allows port 5432 from the ECS security group
10. ECS security group only allows port 8000 from the ALB security group
11. Autoscaling policy is configured

Take a screenshot of:
- The ECS service Tasks tab showing 2 RUNNING tasks
- The target group Targets tab showing 2 healthy
- Your app loaded in the browser with HTTPS lock icon
- The Secrets Manager secret being referenced in the task definition

---

# Part 8: Cleanup (do this — Fargate, NAT, ALB, RDS all cost money)

Do these in **order** to avoid dependency errors:

1. ECS service → Update → desired count `0` → wait until 0 tasks → delete service
2. Delete ECS cluster
3. Deregister task definition revisions (Actions → Deregister)
4. Delete ALB
5. Delete target group
6. Delete RDS instance (skip final snapshot for demo)
7. Delete DB subnet group
8. Delete NAT gateway → release the Elastic IP
9. Delete security groups (alb, ecs, rds)
10. Delete the secret from Secrets Manager (it has a 7-day recovery window — schedule deletion)
11. Delete the CloudWatch log group
12. Delete the ECR repository (or keep the image for next class)
13. Delete the Route53 record (optional)

NAT gateway, ALB, and RDS are the expensive ones. If you skip cleanup, you'll see ~$40–60 in your bill next month.

---

# Bonus Tasks

These are optional but very interview-worthy. Do at least one.

### Bonus 1: Run Postgres in a container instead of RDS

I gave this as an assignment in class. Run Postgres as an ECS service in the same cluster:
- Create a task definition for `postgres:15`
- Use an EFS volume mounted at `/var/lib/postgresql/data` so data survives task restart
- Put it in a separate service in the same cluster
- Point the app at it via internal service discovery (CloudMap)

This is how real companies that don't want to pay for RDS run stateful workloads on ECS.

### Bonus 2: Restrict the Secrets Manager policy

In Step 6 you attached `SecretsManagerReadWrite` which is way too broad. Replace it with a custom policy that only allows `secretsmanager:GetSecretValue` on the **specific ARN** of your secret. This is the least-privilege principle in action — common interview question.

### Bonus 3: Set up VPC endpoints instead of NAT gateway

Replace the NAT gateway with VPC endpoints for ECR, S3, and CloudWatch Logs. Compare the costs in your AWS bill the next day. Write up which approach is better for your use case and why.

### Bonus 4: Add load testing with k6

Install k6 locally. Write a small script that hits `https://app.yourdomain.com/login` with 50 concurrent virtual users for 5 minutes. Watch the autoscaler kick in. Take screenshots of:
- Task count going from 2 → 5
- CloudWatch CPU utilization graph
- Latency from the load test report

This is the real way to validate autoscaling. Don't just trust the config.

---

# Reflection Questions

Answer these in your notes before next class:

1. Why did we create the NAT gateway **before** the ECS service? What error do you see if you flip the order?
2. Why does the target group use **IP** target type instead of **Instance**?
3. Why is the health check path `/login` and not `/`? What HTTP status code does `/` return for this app?
4. Why are ALB security group, ECS security group, and RDS security group **three separate** groups that reference each other, instead of one big security group with all the rules?
5. The task definition uses `valueFrom` instead of `value` for `DB_LINK`. What's the security benefit? What permission does the execution role need to make this work?
6. Why does scale-in cooldown (300s) need to be longer than scale-out cooldown (60s)?
7. If your NAT gateway crashes, do running ECS tasks keep serving traffic? Why or why not? What about new tasks trying to start?

If you can answer all 7 from memory, you understand ECS in production. If you struggle with any of them, re-read that section.

---

Next week: same setup, but in Terraform. Then GitHub Actions to automate the image build and push. Same architecture, three different ways of building it.

Spend this week getting comfortable with Terraform basics — variables, resources, providers, state. Watch one good intro video and read the official tutorial. Don't skip this prep or next class will fly over your head.

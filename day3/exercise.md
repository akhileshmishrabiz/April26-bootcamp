# Week 2 Assignment: Custom VPC, Bastion, IAM Roles & VPC Endpoints

**Bootcamp:** Advanced DevOps + MLOps + AIOps — April 2026 Batch
**Module:** AWS Networking & IAM Fundamentals
**Estimated time:** 4–6 hours
**Region for this exercise:** `ap-south-1` (Mumbai)

---

## Learning objectives

By the end of this assignment you will have built — by hand, from the AWS Console — a production-style VPC layout that mirrors what real companies run. You will:

- Design a VPC with public and private subnets across two Availability Zones
- Configure Internet Gateway, NAT Gateway, and route tables correctly
- Stand up a bastion host pattern to reach private EC2 instances
- Understand IAM users vs roles vs trust policies vs inline/managed/custom policies
- Replace expensive NAT-based S3 access with a free VPC Gateway Endpoint
- Verify everything end-to-end with `ssh`, `scp`, and `aws s3` commands

You are not allowed to use Terraform or any IaC tool for this assignment. The whole point is to feel the pain of clicking through the console — you'll appreciate Terraform much more next week.

---

## Prerequisites

- An AWS account with admin access (your own — do not use your employer's account)
- AWS CLI v2 installed locally and configured with credentials
- A terminal (Mac/Linux) or WSL on Windows
- Basic familiarity with `ssh`, `scp`, `chmod`
- Last week's S3 bucket from the encrypted DB backup exercise — you'll reuse it

If you are shaky on IP addressing and CIDR blocks, watch the networking fundamentals videos linked in the resources doc before starting. The rest of this assignment assumes you understand what `/16` and `/24` mean.

---

## Architecture you are building

```
                                 ┌───────────────────────────┐
                                 │   Internet Gateway (IGW)  │
                                 └─────────────┬─────────────┘
                                               │
                ┌──────────────────────────────┼──────────────────────────────┐
                │                  VPC: 10.0.0.0/16                           │
                │                                                             │
                │   ┌──── ap-south-1a ────┐         ┌──── ap-south-1b ────┐   │
                │   │                     │         │                     │   │
                │   │  public-1           │         │  public-2           │   │
                │   │  10.0.1.0/24        │         │  10.0.2.0/24        │   │
                │   │  ┌──────────────┐   │         │                     │   │
                │   │  │  Bastion EC2 │   │         │   NAT Gateway       │   │
                │   │  │  + Public IP │   │         │   + Elastic IP      │   │
                │   │  └──────┬───────┘   │         │                     │   │
                │   │         │           │         │                     │   │
                │   │  private-1          │         │  private-2          │   │
                │   │  10.0.3.0/24        │         │  10.0.4.0/24        │   │
                │   │  ┌──────────────┐   │         │                     │   │
                │   │  │  Private EC2 │◄──┼─────────┼── (future EC2s)     │   │
                │   │  │  No public IP│   │         │                     │   │
                │   │  └──────────────┘   │         │                     │   │
                │   │                     │         │                     │   │
                │   │  rds-1              │         │  rds-2              │   │
                │   │  10.0.5.0/24        │         │  10.0.6.0/24        │   │
                │   └─────────────────────┘         └─────────────────────┘   │
                │                                                             │
                │           ┌─────────────────────────────────┐               │
                │           │  S3 Gateway VPC Endpoint        │               │
                │           │  (attached to private route tbl)│               │
                │           └─────────────────────────────────┘               │
                └─────────────────────────────────────────────────────────────┘
                                               │
                                               ▼
                                       ┌───────────────┐
                                       │  S3 Bucket    │
                                       │  (last week)  │
                                       └───────────────┘
```

---

## Part 1 — Build the VPC

### Task 1.1 — Create the VPC

1. Go to **VPC console → Your VPCs → Create VPC**
2. Choose **VPC only** (we want to do every piece manually)
3. Name: `bootcamp-vpc`
4. IPv4 CIDR block: `10.0.0.0/16`
5. Leave everything else default and create

**Verification:** Go to `https://www.calculator.net/ip-subnet-calculator.html`, enter `10.0.0.0/16`, and confirm you get **65,534 usable hosts**. Note this number — write a one-liner in your submission explaining why it's 65,534 and not 65,536.

### Task 1.2 — Create six subnets

Create these subnets one by one. **Pay attention to the AZ — half go in `ap-south-1a`, half in `ap-south-1b`.**

| Name        | AZ            | CIDR          | Purpose                  |
|-------------|---------------|---------------|--------------------------|
| `public-1`  | ap-south-1a   | `10.0.1.0/24` | Bastion + public-facing  |
| `public-2`  | ap-south-1b   | `10.0.2.0/24` | Future ALB / NAT GW      |
| `private-1` | ap-south-1a   | `10.0.3.0/24` | App EC2s                 |
| `private-2` | ap-south-1b   | `10.0.4.0/24` | App EC2s                 |
| `rds-1`     | ap-south-1a   | `10.0.5.0/24` | RDS subnet group         |
| `rds-2`     | ap-south-1b   | `10.0.6.0/24` | RDS subnet group         |

**Common mistake to avoid:** Don't forget the third octet. If you type `10.0.0/24` instead of `10.0.1.0/24` you'll see an error or end up with overlapping subnets. Akhilesh did exactly this in class — learn from his slip.

### Task 1.3 — Internet Gateway

1. **VPC → Internet Gateways → Create**
2. Name: `bootcamp-igw`
3. After creation, **Actions → Attach to VPC → bootcamp-vpc**

**Concept check (write the answer in your submission):** What is the relationship cardinality between an IGW and a VPC? Why?

### Task 1.4 — Public route table

1. **VPC → Route Tables → Create**
2. Name: `bootcamp-public-rt`, VPC: `bootcamp-vpc`
3. After creation, go to **Subnet associations** → associate `public-1` and `public-2`
4. Go to **Routes → Edit routes → Add route**:
   - Destination: `0.0.0.0/0`
   - Target: Internet Gateway → `bootcamp-igw`
5. Save

**Concept check:** The route table already had one route before you added `0.0.0.0/0`. What was it, what was its target, and why does it exist by default?

---

## Part 2 — Bastion host

### Task 2.1 — Launch the bastion EC2

1. **EC2 → Launch instance**
2. Name: `bastion`
3. AMI: Amazon Linux 2023 (default)
4. Instance type: `t3.micro` (free tier)
5. **Key pair → Create new key pair**: name it `bootcamp-key`, type RSA, format `.pem`. Download it.
6. **Network settings → Edit:**
   - VPC: `bootcamp-vpc`
   - Subnet: `public-1`
   - Auto-assign public IP: **Enable**
   - Security group: create new, name `bastion-sg`, allow SSH (port 22) from `0.0.0.0/0` *for now* (we'll tighten this in the reflection)
7. Launch

### Task 2.2 — Connect to the bastion

```bash
# From your local machine
mv ~/Downloads/bootcamp-key.pem ~/.ssh/
chmod 400 ~/.ssh/bootcamp-key.pem

ssh -i ~/.ssh/bootcamp-key.pem ec2-user@<BASTION_PUBLIC_IP>
```

**Verification:** Once inside, run `cat ~/.ssh/authorized_keys`. You'll see your public key sitting there — that's how passwordless SSH works. AWS copied the public half of your keypair into this file when the instance launched. Take a screenshot.

### Task 2.3 — Patching test (this should fail)

Inside the bastion, run:

```bash
sudo yum update -y
```

Wait — the bastion has internet because it's in a public subnet, so this will work. Move on.

---

## Part 3 — Private EC2 + NAT Gateway

### Task 3.1 — Launch the private EC2

1. **EC2 → Launch instance**
2. Name: `private-app`
3. Same AMI, same instance type, **same keypair (`bootcamp-key`)**
4. **Network settings:**
   - VPC: `bootcamp-vpc`
   - Subnet: `private-1`
   - Auto-assign public IP: **Disable**
   - Security group: create new, `private-app-sg`, allow SSH from `bastion-sg` (not `0.0.0.0/0` — only from the bastion SG)
5. Launch

### Task 3.2 — Reach the private EC2 through the bastion

From your local machine, copy the key onto the bastion (this is insecure — it's a teaching step, we'll fix it in the reflection):

```bash
scp -i ~/.ssh/bootcamp-key.pem ~/.ssh/bootcamp-key.pem ec2-user@<BASTION_PUBLIC_IP>:/home/ec2-user/
```

Then SSH to the bastion, fix permissions, and hop:

```bash
ssh -i ~/.ssh/bootcamp-key.pem ec2-user@<BASTION_PUBLIC_IP>
chmod 400 bootcamp-key.pem
ssh -i bootcamp-key.pem ec2-user@<PRIVATE_EC2_PRIVATE_IP>
```

**Verification:** You should be inside `private-app`. Run `hostname -I` and confirm you only see a `10.0.3.x` address — no public IP.

### Task 3.3 — Confirm no internet from private EC2

Inside `private-app`:

```bash
sudo yum update -y
```

This will hang and time out. Good. That proves the private subnet has no path to the internet yet.

### Task 3.4 — Create the NAT Gateway

1. **VPC → NAT Gateways → Create NAT gateway**
2. Name: `bootcamp-natgw`
3. Subnet: `public-2` (the NAT GW must live in a public subnet)
4. Connectivity: **Public**
5. Click **Allocate Elastic IP**
6. Create — wait until status is `Available` (takes ~2 min)

### Task 3.5 — Private route table

1. **VPC → Route Tables → Create**
2. Name: `bootcamp-private-rt`, VPC: `bootcamp-vpc`
3. Subnet associations: `private-1` and `private-2`
4. Routes → Edit routes → Add:
   - Destination: `0.0.0.0/0`
   - Target: NAT Gateway → `bootcamp-natgw`
5. Save

### Task 3.6 — Re-test from the private EC2

```bash
sudo yum update -y
```

This should now work. Take a screenshot of the package list.

---

## Part 4 — IAM roles for S3 access

### Task 4.1 — Create the role

1. **IAM → Roles → Create role**
2. Trusted entity: **AWS service**
3. Use case: **EC2**
4. Permissions: attach AWS managed policy `AmazonS3ReadOnlyAccess` *(we'll switch to a custom policy in Task 4.4)*
5. Name: `bootcamp-ec2-s3-role`
6. Create

**Concept check (write 2–3 sentences):** Open the role and look at the **Trust relationships** tab. What does the JSON say? Explain in your own words what "trust policy" means and how it differs from "permissions policy."

### Task 4.2 — Attach the role to both EC2 instances

For both `bastion` and `private-app`:
- **EC2 → Instances → select instance → Actions → Security → Modify IAM role**
- Choose `bootcamp-ec2-s3-role` → Update

### Task 4.3 — Test S3 access from the private EC2

SSH into `private-app` (via the bastion as before):

```bash
aws s3 ls
aws s3 ls s3://<your-bucket-from-last-week>
```

Both should work — traffic is currently going **out through the NAT Gateway, across the public internet, to S3**. That's expensive at scale.

### Task 4.4 — Replace the managed policy with a custom policy

The managed `AmazonS3ReadOnlyAccess` policy lets your EC2 read **every** bucket in your account. That's too broad. Create a custom policy that only allows read access to your one bucket.

1. **IAM → Policies → Create policy → JSON tab**
2. Paste this, replacing `<your-bucket-name>`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::<your-bucket-name>",
        "arn:aws:s3:::<your-bucket-name>/*"
      ]
    }
  ]
}
```

3. Name: `bootcamp-s3-readonly-onebucket`
4. Detach `AmazonS3ReadOnlyAccess` from `bootcamp-ec2-s3-role` and attach your new custom policy instead
5. Re-test: `aws s3 ls s3://<your-bucket-name>` should still work, but `aws s3 ls` (listing all buckets) should now fail with `AccessDenied`

**Concept check:** What is the difference between an **AWS managed policy**, a **customer managed policy**, and an **inline policy**? When would you use each?

---

## Part 5 — VPC Gateway Endpoint for S3

The whole reason for this part: NAT Gateway charges for data processing. If you're moving terabytes between EC2 and S3, that bill gets ugly. A **Gateway Endpoint** for S3 is **free** and keeps traffic on the AWS private network.

### Task 5.1 — Delete the NAT Gateway (to prove the endpoint actually works)

1. **VPC → NAT Gateways → select `bootcamp-natgw` → Delete**
2. **EC2 → Elastic IPs → release** the EIP that was attached (otherwise it costs money sitting around)
3. Wait until the NAT GW is fully deleted

Re-test from `private-app`:

```bash
aws s3 ls s3://<your-bucket-name>
```

This will fail or hang — the route to S3 went through the NAT, and the NAT is gone.

### Task 5.2 — Create the Gateway Endpoint

1. **VPC → Endpoints → Create endpoint**
2. Name: `bootcamp-s3-endpoint`
3. Service category: **AWS services**
4. Service name: search `s3`, pick `com.amazonaws.ap-south-1.s3` with **Type: Gateway**
5. VPC: `bootcamp-vpc`
6. Route tables: tick `bootcamp-private-rt`
7. Policy: **Full access** (you can lock this down later)
8. Create

### Task 5.3 — Re-test

From `private-app`:

```bash
aws s3 ls s3://<your-bucket-name>
aws s3 cp s3://<your-bucket-name>/<some-file> /tmp/
```

Both should work now. Traffic is going through the gateway endpoint, on the AWS backbone, free of charge.

**Concept check:** What's the difference between a **Gateway Endpoint** and an **Interface Endpoint**? Which AWS services support Gateway Endpoints? Why might you still pay for an Interface Endpoint despite the cost?

---

## Part 6 — Bonus: SSM Session Manager (no SSH, no bastion key copying)

The bastion + SSH key pattern works, but copying private keys onto a bastion host is a security smell. The modern way is **SSM Session Manager** — log into private EC2s without any SSH port open and without copying keys around.

### Task 6.1 — Add SSM permissions to the role

1. **IAM → Roles → `bootcamp-ec2-s3-role` → Add permissions → Attach policy**
2. Attach `AmazonSSMManagedInstanceCore`

### Task 6.2 — Add the three SSM Interface Endpoints

Without these, the private EC2 can't reach SSM (you deleted the NAT). Create three Interface Endpoints:

- `com.amazonaws.ap-south-1.ssm`
- `com.amazonaws.ap-south-1.ssmmessages`
- `com.amazonaws.ap-south-1.ec2messages`

For each:
- VPC: `bootcamp-vpc`
- Subnets: `private-1`, `private-2`
- Security group: create one called `vpce-sg` allowing inbound HTTPS (443) from `private-app-sg`
- Enable DNS name: **yes**

### Task 6.3 — Install Session Manager Plugin locally

```bash
# Mac
brew install --cask session-manager-plugin
```

### Task 6.4 — Connect

```bash
aws ssm start-session --target <PRIVATE_EC2_INSTANCE_ID> --region ap-south-1
```

You should land inside `private-app` — no SSH, no bastion, no key files.

**Concept check:** List the three things that have to be true for SSM Session Manager to work on a private EC2. (Hint: instance role, network path to SSM endpoints, SSM agent running.)

---

## Cleanup (do this when done — or you'll burn through credits)

Delete in this order to avoid dependency errors:

1. Terminate both EC2 instances
2. Delete VPC Endpoints (S3 gateway + 3 SSM interfaces)
3. Delete NAT Gateway if still alive, release its Elastic IP
4. Delete custom route tables (public + private)
5. Detach and delete the Internet Gateway
6. Delete subnets
7. Delete security groups (default SG can't be deleted)
8. Delete the VPC
9. Delete the IAM role and custom policy
10. Delete the keypair

Run this to confirm nothing's left:

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=bootcamp-vpc" --region ap-south-1
aws ec2 describe-instances --filters "Name=tag:Name,Values=bastion,private-app" --region ap-south-1 --query 'Reservations[].Instances[?State.Name!=`terminated`]'
```

---

## Submission

Create a folder `week2-submission/` with:

1. **`screenshots/`** — at minimum:
   - VPC resource map showing all 6 subnets
   - Both route tables with their routes and subnet associations
   - Bastion successfully SSHed from your laptop
   - Private EC2 successfully SSHed from the bastion
   - `sudo yum update` failing on private EC2 *before* NAT Gateway
   - `sudo yum update` working *after* NAT Gateway
   - `aws s3 ls` working through the Gateway Endpoint *after* NAT was deleted
   - SSM Session Manager session active on the private EC2

2. **`answers.md`** — answer all the **Concept check** questions inline. Be specific. Don't paste from ChatGPT — I can tell.

3. **`reflection.md`** — answer these in your own words (3–5 sentences each):
   - In Task 2.1 you opened SSH from `0.0.0.0/0`. In a real company, what would you restrict it to instead, and how?
   - You copied a private key onto the bastion in Task 3.2. Name two reasons this is a bad practice and one alternative.
   - When would you choose a Gateway Endpoint vs an Interface Endpoint vs just using the NAT Gateway?
   - VPC Peering vs Transit Gateway — when does Transit Gateway start to make sense?

4. **`gotchas.md`** — list every single thing that went wrong while you did this assignment and how you fixed it. Even small stuff. This file is for **you**, not for grading — when you set this up at work in 6 months, you'll thank yourself.

Submit the folder as a zip in the cohort Google Drive by **end of Sunday**.

---

## Common gotchas (read before you start)

- **Forgetting the third octet** in subnet CIDRs. `10.0.1.0/24` ≠ `10.0.0.1/24`.
- **NAT Gateway in a private subnet.** It must be in a public subnet.
- **One IGW per VPC.** You can't attach two. You can't share one across VPCs.
- **Security group changes are not retroactive** for *connections* but they are for *new* connections. If something works after you tighten an SG, that's because the existing TCP session was still open.
- **Endpoint policy default is "Full access"** — this is fine for learning but in real life you scope it down.
- **The `ec2-user` username** is for Amazon Linux. Ubuntu uses `ubuntu`. RHEL uses `ec2-user` or `root`. Don't memorize — check the AMI description.
- **Elastic IPs cost money when not attached** to a running resource. Always release them after deleting a NAT GW.
- **Route table associations are per-subnet, not per-AZ.** Two subnets in the same AZ can have different route tables.

---

## Stretch goals (optional — for the keen)

- **VPC Peering:** Create a second VPC (`bootcamp-vpc-2`) with one EC2 in it. Set up VPC peering with `bootcamp-vpc` and verify the EC2s can ping each other on private IPs.
- **VPC Flow Logs:** Enable flow logs on `bootcamp-vpc`, send to CloudWatch, and find the log entry for your SSH connection from the bastion to the private EC2.
- **Replace bastion with EC2 Instance Connect Endpoint:** AWS now has a managed alternative to bastion hosts. Set it up and document the trade-offs vs SSM Session Manager.
- **Tighten the bastion SG to your real public IP only:** Use `curl ifconfig.me` to find your IP, then update the SG rule from `0.0.0.0/0` to `<your-ip>/32`. Verify it still works.

---

## What we're covering next

Tomorrow: **Application Load Balancer + Auto Scaling Group + RDS migration.** We'll take last week's monolithic EC2 (app + DB on one box) and split it into:
- App tier in an ASG across `private-1` and `private-2`
- ALB in `public-1` and `public-2`
- DB on RDS, restored from your S3-encrypted backup

Make sure your VPC from this assignment is **still standing** by tomorrow morning — we'll build directly on top of it. If you cleaned up, you'll have to rebuild it before class.

Good luck. Ask questions in the WhatsApp group as you hit issues — that's what it's there for.

— Akhilesh
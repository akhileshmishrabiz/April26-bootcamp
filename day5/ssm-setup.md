# SSM Session Manager Setup for EC2 (No Public IP, No Port 22)

Connect to EC2 instances via AWS Systems Manager Session Manager — no public IP, no inbound ports, no SSH keys.

**Region:** `ap-south-1`

## Prerequisites

- An EC2 instance (private or public subnet)
- AWS CLI configured locally
- IAM permissions to manage EC2, IAM, and VPC resources

## Step 1 — Verify SSM Agent is Installed and Running

SSH into the instance (or use EC2 Instance Connect for the initial check) and run:

```bash
sudo systemctl status amazon-ssm-agent
```

It should show `active (running)`. SSM Agent ships pre-installed on Amazon Linux 2/2023, Ubuntu 16.04+, and Windows Server 2016+.

## Step 2 — Create IAM Role and Attach to EC2

Create an IAM role for EC2 with the AWS-managed policy `AmazonSSMManagedInstanceCore`.

```bash
# Trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name EC2-SSM-Role \
  --assume-role-policy-document file://trust-policy.json

# Attach managed policy
aws iam attach-role-policy \
  --role-name EC2-SSM-Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Create instance profile
aws iam create-instance-profile --instance-profile-name EC2-SSM-Profile
aws iam add-role-to-instance-profile \
  --instance-profile-name EC2-SSM-Profile \
  --role-name EC2-SSM-Role
```

Attach the instance profile to your EC2 instance:

```bash
aws ec2 associate-iam-instance-profile \
  --instance-id <INSTANCE_ID> \
  --iam-instance-profile Name=EC2-SSM-Profile \
  --region ap-south-1
```

## Step 3 — Create the Three VPC Endpoints

Three interface endpoints are required for SSM to work without internet access:

| Endpoint | Purpose |
|---|---|
| `ssm` | Agent registers the instance and fetches commands/documents |
| `ssmmessages` | Carries interactive Session Manager shell traffic |
| `ec2messages` | Channel for Run Command and command acknowledgments |

The endpoint security group must allow **inbound TCP 443** from the EC2 instance's security group.

### 3a. `ssm` endpoint — via AWS Console

1. Open **VPC Console → Endpoints → Create endpoint**
2. **Name tag:** `ssm-endpoint`
3. **Service category:** AWS services
4. **Services:** search `ssm`, select `com.amazonaws.ap-south-1.ssm` (Type: Interface)
5. **VPC:** select your VPC
6. **Subnets:** select your private subnet(s)
7. **Enable DNS name:** ✅ check (Private DNS enabled)
8. **Security groups:** select an SG allowing inbound TCP 443 from instance SG
9. **Policy:** Full access (default)
10. Click **Create endpoint**

### 3b. `ssmmessages` endpoint — via AWS CLI

```bash
aws ec2 create-vpc-endpoint \
  --region ap-south-1 \
  --vpc-id vpc-01d0ddafe8bcf422b \
  --service-name com.amazonaws.ap-south-1.ssmmessages \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-0c33a08d636870520 \
  --security-group-ids sg-0f76ab02e7bf7bade \
  --private-dns-enabled \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=ssmmessages-endpoint}]'
```

### 3c. `ec2messages` endpoint — via AWS CLI

```bash
aws ec2 create-vpc-endpoint \
  --region ap-south-1 \
  --vpc-id vpc-01d0ddafe8bcf422b \
  --service-name com.amazonaws.ap-south-1.ec2messages \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-0c33a08d636870520 \
  --security-group-ids sg-0f76ab02e7bf7bade \
  --private-dns-enabled \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=ec2messages-endpoint}]'
```

## Step 4 — Install Session Manager Plugin Locally (macOS Apple Silicon)

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install \
  -i /usr/local/sessionmanagerplugin \
  -b /usr/local/bin/session-manager-plugin
session-manager-plugin --version
```

## Step 5 — Verify and Connect

Confirm the instance is registered (may take 1–10 minutes after attaching the IAM role):

```bash
aws ssm describe-instance-information --region ap-south-1 \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' \
  --output table
```

`PingStatus` should be `Online`. Then connect:

```bash
aws ssm start-session --target <INSTANCE_ID> --region ap-south-1
```

## Setup Checklist

- [ ] SSM Agent installed and running on EC2
- [ ] IAM role with `AmazonSSMManagedInstanceCore` attached to EC2
- [ ] `com.amazonaws.ap-south-1.ssm` endpoint created with Private DNS
- [ ] `com.amazonaws.ap-south-1.ssmmessages` endpoint created with Private DNS
- [ ] `com.amazonaws.ap-south-1.ec2messages` endpoint created with Private DNS
- [ ] Endpoint SG allows inbound 443 from instance SG
- [ ] Session Manager plugin installed locally
- [ ] `aws ssm start-session` connects successfully
Looking at today's session, here's a focused lab exercise:

---

# Lab 01: Deploy a Flask App on EC2 with Nginx Reverse Proxy

## Prerequisites
- AWS account with free tier access
- A key pair created in EC2
- VS Code + GitHub Copilot (or any AI tool)
- Basic Git knowledge

---

## Part 1 — Launch EC2 Instance

1. Go to EC2 → **Launch Instance**
2. Name it `day1-app`
3. AMI: **Amazon Linux 2023** (free tier)
4. Instance type: `t2.micro`
5. Select your existing key pair
6. Security Group — allow inbound:
   - Port `22` (SSH)
   - Port `80` (HTTP)
7. Launch the instance

---

## Part 2 — Set Up the App on EC2

SSH into your instance, then run:

```bash
# Install Git
sudo yum install git -y

# Clone your app repo
git clone <your-repo-url>
cd <your-app-folder>

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

**Verify the app runs:**
```bash
python app.py
# Should start on port 5000 or 8000
```

---

## Part 3 — Run App with Gunicorn

Add `gunicorn==25.1.0` to your `requirements.txt`, then:

```bash
pip install -r requirements.txt

# Run gunicorn in background
gunicorn --bind 0.0.0.0:8000 app:app &
```

**Verify:**
```bash
lsof -i :8000
curl localhost:8000
```

---

## Part 4 — Install and Configure Nginx

```bash
sudo yum install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

Edit the Nginx config:
```bash
sudo vi /etc/nginx/nginx.conf
```

Inside the `server {}` block, add:
```nginx
location / {
    proxy_pass http://127.0.0.1:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

Restart Nginx:
```bash
sudo systemctl restart nginx
```

**Verify:** Hit your EC2 public IP in browser on port 80 — your app should load.

---

## Part 5 — Assign Elastic IP

1. Go to **VPC → Elastic IPs → Allocate**
2. Tag it: `static-demo`
3. Associate it with your EC2 instance
4. Note the Elastic IP — this is now your **permanent public IP**

---

## Part 6 — Map Domain via Route 53

1. Go to **Route 53 → Hosted Zones**
2. Select your hosted zone (or create one for your domain)
3. Click **Create Record**
   - Record name: `demo` (creates `demo.yourdomain.com`)
   - Type: `A`
   - Value: your Elastic IP
4. Save and wait ~30 seconds
5. Visit `demo.yourdomain.com` in browser

---

## Verification Checklist

| Step | What to check |
|---|---|
| App runs | `curl localhost:8000` returns HTML |
| Gunicorn running | `lsof -i :8000` shows process |
| Nginx routing | Browser hits EC2 public IP on port 80 |
| Elastic IP attached | IP doesn't change after stop/start |
| DNS resolves | `nslookup demo.yourdomain.com` returns your Elastic IP |

---

## What's Next (Tomorrow)
- Configure HTTPS using Let's Encrypt + Certbot
- Add PostgreSQL database to the app
- Move to Auto Scaling Group + ALB setup

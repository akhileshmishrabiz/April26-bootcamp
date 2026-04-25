# Lab 02: HTTPS, PostgreSQL & S3 Backup on EC2

**Prerequisite:** Lab 01 completed — EC2 running, Nginx configured, domain mapped via Route 53

---

## Part 1 — Enable HTTPS with Certbot (Let's Encrypt)

### Open HTTPS port
Go to your EC2 **Security Group → Inbound Rules → Add Rule:**
- Type: `HTTPS`
- Port: `443`
- Source: `0.0.0.0/0`

> Port 80 must remain open — Let's Encrypt uses an HTTP challenge to verify domain ownership before issuing the certificate.

### Install Certbot
```bash
sudo yum install certbot python3-certbot-nginx -y
```

### Request a certificate
```bash
sudo certbot --nginx -d demo.yourdomain.com -d www.demo.yourdomain.com
```

Certbot will:
1. Place a temporary validation file at a known path on your server
2. Let's Encrypt will make an HTTP request to `http://demo.yourdomain.com/.well-known/acme-challenge/<token>`
3. If reachable, the certificate is issued and your Nginx config is updated automatically

### Verify HTTPS
```bash
sudo systemctl reload nginx
```

Visit `https://demo.yourdomain.com` — you should see the padlock icon.

### Verify certificate files
```bash
sudo ls /etc/letsencrypt/live/demo.yourdomain.com/
# You should see: cert.pem  chain.pem  fullchain.pem  privkey.pem
```

### Set up auto-renewal (cron job)
```bash
# Test renewal without actually renewing
sudo certbot renew --dry-run

# View existing cron jobs
crontab -l

# Add a daily renewal check (runs at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * sudo certbot renew --quiet") | crontab -
```

> **Production tip:** Don't wait for the 90-day expiry. Renew at 80 days or earlier to give yourself time to fix failures. One expired certificate can take down your entire app.

---

## Part 2 — Install and Configure PostgreSQL

### Install PostgreSQL 15
```bash
sudo dnf install postgresql15 postgresql15-server -y

# Initialize the database
sudo postgresql-setup --initdb

# Enable and start the service
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Verify it's running
sudo systemctl status postgresql
```

### Configure the database
```bash
# Log in as the postgres system user
sudo -u postgres psql

# Inside the psql shell — set a password and create your database
ALTER USER postgres WITH PASSWORD 'yourpassword';
CREATE DATABASE mydb OWNER postgres;
\l    -- list all databases
\q    -- exit
```

### Allow password-based login
```bash
# Edit the pg_hba.conf file
sudo vi /var/lib/pgsql/data/pg_hba.conf
```

Find these two lines and change `ident` to `md5`:
```
# Before
host    all    all    127.0.0.1/32    ident
host    all    all    ::1/128         ident

# After
host    all    all    127.0.0.1/32    md5
host    all    all    ::1/128         md5
```

```bash
sudo systemctl restart postgresql
```

### Test the connection
```bash
# Export your DB connection string
export DB_LINK="postgresql://postgres:yourpassword@localhost:5432/mydb"

# Verify connection using psql
psql $DB_LINK -c "\dt"
```

> If you see an empty list of relations (no error), your database is reachable and ready.

---

## Part 3 — Connect App to PostgreSQL

### Replace the Day 1 app with the database-backed app
```bash
# Stop the running gunicorn process
lsof -i :8000
kill -9 <PID>

# Pull the Day 2 app code
cd ~/your-repo
git pull

# Activate virtual environment
source .venv/bin/activate

# Install updated dependencies
pip install -r requirements.txt
```

### Set the DB connection and start the app
```bash
export DB_LINK="postgresql://postgres:yourpassword@localhost:5432/mydb"

# Start the app — it will auto-create tables on first run
gunicorn --bind 0.0.0.0:8000 run:app &
```

### Verify
```bash
lsof -i :8000
curl localhost:8000
```

Visit `https://demo.yourdomain.com` — your app should load with login/signup working.

> **What to watch for:**
> - First error you'll see without `DB_LINK` set → app crashes with a missing env var message
> - Second error (with `DB_LINK` but no database) → connection refused on port 5432
> - Both are normal troubleshooting steps — learn to read these error messages

---

## Part 4 — Backup Database to S3

### Create an IAM Role for EC2 (no hardcoded credentials)

1. Go to **IAM → Roles → Create Role**
2. Trusted entity: **AWS Service → EC2**
3. Attach policy: `AmazonS3FullAccess`
4. Name it: `ec2-s3-backup-role`
5. Go to **EC2 → Your Instance → Actions → Security → Modify IAM Role**
6. Attach `ec2-s3-backup-role`

> **Why a role and not access keys?** Hardcoded credentials in `~/.aws/credentials` are a security risk — anyone with shell access can read them. IAM roles are automatically rotated by AWS and leave no secrets on disk.

### Verify S3 access from EC2
```bash
aws s3 ls
# Should list your buckets — no credentials needed
```

### Take a database backup
```bash
export DB_LINK="postgresql://postgres:yourpassword@localhost:5432/mydb"

# Create a timestamped dump file
pg_dump $DB_LINK -F c -f /tmp/mydb_$(date +%Y%m%d_%H%M%S).dump

# Verify the file was created
ls -lh /tmp/mydb_*.dump
```

### Upload backup to S3
```bash
# List files in your bucket first
aws s3 ls s3://your-bucket-name/

# Upload the dump file
aws s3 cp /tmp/mydb_*.dump s3://your-bucket-name/backups/

# Confirm it uploaded
aws s3 ls s3://your-bucket-name/backups/
```

### Back up your Nginx config too
```bash
sudo cp /etc/nginx/nginx.conf /tmp/nginx.conf.bak
aws s3 cp /tmp/nginx.conf.bak s3://your-bucket-name/configs/nginx.conf
```

> You'll use these backed-up files in Lab 03 to restore your setup on a new EC2 instance — simulating what happens when a server is replaced.

---

## Verification Checklist

| Step | Command / Check |
|---|---|
| HTTPS working | Browser shows padlock on your domain |
| Certificate files exist | `sudo ls /etc/letsencrypt/live/yourdomain/` |
| Auto-renewal configured | `crontab -l` shows certbot entry |
| PostgreSQL running | `sudo systemctl status postgresql` |
| App connects to DB | Login/signup works on your domain |
| IAM role attached | `aws s3 ls` works without `aws configure` |
| DB dump uploaded | `aws s3 ls s3://your-bucket/backups/` shows file |
| Nginx config backed up | `aws s3 ls s3://your-bucket/configs/` shows file |

---

## Concepts Covered Today

| Concept | What it means in practice |
|---|---|
| ACME / HTTP-01 challenge | Let's Encrypt verifies domain ownership by fetching a file from your server over port 80 |
| Certificate vs. deployment | Getting the cert (certbot) and updating Nginx config are two separate steps |
| Virtual environment | Isolates app dependencies — no conflicts between multiple apps on the same server |
| `DB_LINK` env var | Apps read config from environment, not hardcoded values — this is the correct pattern |
| IAM Role vs. Access Keys | Roles are the right way to grant EC2 permission to AWS services — no secrets on disk |
| `pg_dump` / `pg_restore` | Standard PostgreSQL tools for backup and restore |
| `lsof -i :PORT` | Your go-to command to check what process is listening on a port |

---

## What's Next (Lab 03)

- Migrate local PostgreSQL data to **Amazon RDS**
- Restore your EC2 setup from S3 backups on a fresh instance
- Introduction to **Auto Scaling Group + Application Load Balancer**
- Attach **ACM certificate** to ALB (no Certbot needed at load balancer level)

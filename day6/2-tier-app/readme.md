# app needs

<!-- # DB_LINK = "postgresql://{user}:{password}@{host}:5432/{database_name}"

# host = "localhost"
# port = 5432
# database_name = "mydb"
# user = "postgres"
# password = "postgres"

# Run Postgre on ec2 -->

**Install PostgreSQL on Amazon Linux 2023:**

```bash
sudo dnf install postgresql15-server postgresql15 -y

# Initialise the database cluster
sudo postgresql-setup --initdb

# Enable and start the service
sudo systemctl enable postgresql --now

# Verify it's running
sudo systemctl status postgresql
```

---

**Create the database matching your DB_LINK:**

```bash
# Switch to the postgres system user
sudo -i -u postgres

# Set the password for the postgres role (must match your DB_LINK)
psql -c "ALTER USER postgres WITH PASSWORD 'password';"

# Create the database
psql -c "CREATE DATABASE mydb;"

# Verify
psql -c "\l"

# Exit back to ec2-user
exit
```

---

**Allow password-based login (md5 auth):**

By default AL2023 uses `ident` auth which blocks password logins. Fix it:

```bash
sudo vi /var/lib/pgsql/data/pg_hba.conf
```

Change these lines:

```
# FROM
host    all    all    127.0.0.1/32    ident
host    all    all    ::1/128         ident

# TO
host    all    all    127.0.0.1:5432    md5
host    all    all    ::1/128           md5
```

Then restart:

```bash
sudo systemctl restart postgresql
```

---

**Test your connection with the exact DB_LINK:**

```bash
export DB_LINK="postgresql://postgres:password@localhost:5432/mydb"
psql $DB_LINK
```


# Export database connection string
export DB_LINK="postgresql://postgres:password@localhost:5432/mydb"




# cd to src

cd src

# Virtual env

python3 -m venv venv

source venv/bin/activate

pip install -r requirements.txt





## backup and restore
**Step 1 — Dump the database to a local file:**

```bash
export DB_LINK="postgresql://postgres:password@localhost:5432/mydb"

# Custom format (-Fc) — compressed, best for pg_restore
pg_dump -Fc $DB_LINK -f /tmp/mydb_$(date +%Y%m%d_%H%M%S).dump

# Verify the file was created
ls -lh /tmp/mydb_*.dump
```

> Save the exact filename, you'll need it in the next steps.

```bash
# Set it as a variable for convenience
DUMP_FILE=$(ls -t /tmp/mydb_*.dump | head -1)
echo $DUMP_FILE
```

---

**Step 2 — Upload the dump to S3:**

```bash
# Make sure your EC2 has an IAM role with s3:PutObject permission
aws s3 cp $DUMP_FILE s3://your-bucket-name/backups/

# Verify it's there
aws s3 ls s3://your-bucket-name/backups/
```

---

**Step 3 — Restore from S3:**

```bash
# Download the dump from S3
aws s3 cp s3://your-bucket-name/backups/mydb_20240419_120000.dump /tmp/restore.dump

# Drop and recreate the target database (clean restore)
sudo -i -u postgres psql -c "DROP DATABASE IF EXISTS mydb;"
sudo -i -u postgres psql -c "CREATE DATABASE mydb;"

# Restore
pg_restore -Fc -d $DB_LINK /tmp/restore.dump

# Verify tables are back
psql $DB_LINK -c "\dt"
```

---

**Quick reference — all 3 flags explained:**

| flag | meaning |
|------|---------|
| `-Fc` | custom compressed format, required for `pg_restore` |
| `-f` | output file path |
| `-d` | target database connection string |

> If you want plain SQL instead (readable but larger), swap `-Fc` for `-Fp` on dump and use `psql $DB_LINK -f restore.dump` instead of `pg_restore` to restore.
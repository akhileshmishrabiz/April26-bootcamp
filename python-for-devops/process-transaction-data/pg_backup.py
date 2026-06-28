import os
import tarfile
from datetime import datetime

import boto3
import psycopg2


def create_backup():
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    backup_dir = f"/tmp/db_backup_{timestamp}"
    os.makedirs(backup_dir)

    print("connecting to database...")
    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )
    cur = conn.cursor()

    print("fetching tables...")
    cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
    tables = [row[0] for row in cur.fetchall()]
    print(f"found {len(tables)} tables")

    for table in tables:
        file_path = f"{backup_dir}/{table}.csv"
        print(f"backing up {table}...")
        with open(file_path, "w") as f:
            cur.copy_expert(f"COPY {table} TO STDOUT WITH CSV HEADER", f)

    cur.close()
    conn.close()

    backup_file = f"{backup_dir}.tar.gz"
    print(f"creating {backup_file}...")
    with tarfile.open(backup_file, "w:gz") as tar:
        tar.add(backup_dir, arcname=os.path.basename(backup_dir))

    print(f"backup ready at {backup_file}")
    return backup_file


def upload_backup(backup_file):
    bucket = os.environ["DB_BACKUP"]
    key = os.path.basename(backup_file)

    print(f"uploading to s3://{bucket}/{key}")
    s3 = boto3.client("s3")
    s3.upload_file(backup_file, bucket, key)
    print("upload finished")

    return f"s3://{bucket}/{key}"


def lambda_handler(event, context):
    print("backup lambda started")
    backup_file = create_backup()
    s3_path = upload_backup(backup_file)
    print(f"done — backup at {s3_path}")
    return {"status": "ok", "backup": s3_path}

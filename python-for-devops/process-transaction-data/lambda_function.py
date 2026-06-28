import json
import os
import traceback
from typing import Any
from urllib.parse import unquote_plus

import boto3

from db import ensure_table_exists, get_connection, insert_transactions
from parser import parse_transactions_csv

s3_client = boto3.client("s3")


def download_s3_object(bucket: str, key: str) -> bytes:
    print(f"[main] Downloading s3://{bucket}/{key}")
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response["Body"].read()
        print(f"[main] Download complete — {len(content)} bytes received")
        return content
    except Exception:
        print(f"[main] ERROR: Failed to download s3://{bucket}/{key}")
        traceback.print_exc()
        raise


def process_transaction_file(content: bytes, source_file: str) -> dict[str, Any]:
    print(f"[main] Processing file: {source_file}")
    print(f"[main] File size: {len(content)} bytes")

    try:
        print("[main] Step 1/3 — Parsing CSV...")
        transactions = parse_transactions_csv(content)
        print(f"[main] Step 1/3 done — {len(transactions)} rows parsed")
    except Exception:
        print(f"[main] ERROR: CSV parsing failed for {source_file}")
        traceback.print_exc()
        raise

    try:
        print("[main] Step 2/3 — Connecting to PostgreSQL...")
        with get_connection() as conn:
            print("[main] Step 2/3 — Connected. Ensuring table exists...")
            ensure_table_exists(conn)
            print("[main] Step 3/3 — Writing rows to vendor_transactions...")
            inserted = insert_transactions(conn, transactions, source_file)
            print(f"[main] Step 3/3 done — {inserted} rows written")
    except Exception:
        print(f"[main] ERROR: Database write failed for {source_file}")
        traceback.print_exc()
        raise

    result = {
        "source_file": source_file,
        "rows_parsed": len(transactions),
        "rows_written": inserted,
    }
    print(f"[main] Finished processing {source_file}: {result}")
    return result


def process_s3_file(bucket: str, key: str) -> dict[str, Any]:
    print(f"[main] Starting S3 file pipeline for bucket={bucket}, key={key}")
    content = download_s3_object(bucket, key)
    source_file = f"s3://{bucket}/{key}"
    return process_transaction_file(content, source_file)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    print("[main] Lambda invoked")
    print(f"[main] Event: {json.dumps(event)}")

    records = event.get("Records", [])
    print(f"[main] Found {len(records)} S3 record(s) to process")

    results = []
    errors = []

    for index, record in enumerate(records, start=1):
        try:
            bucket = record["s3"]["bucket"]["name"]
            key = unquote_plus(record["s3"]["object"]["key"])
            print(f"[main] Record {index}/{len(records)} — bucket={bucket}, key={key}")
            result = process_s3_file(bucket, key)
            results.append(result)
        except Exception as exc:
            print(f"[main] ERROR: Record {index}/{len(records)} failed — {exc}")
            traceback.print_exc()
            errors.append({"record_index": index, "error": str(exc)})

    if errors:
        print(f"[main] Lambda finished with errors — {len(errors)} failed, {len(results)} succeeded")
        return {
            "statusCode": 500,
            "body": json.dumps({"processed_files": results, "errors": errors}),
        }

    print(f"[main] Lambda finished successfully — {len(results)} file(s) processed")
    return {
        "statusCode": 200,
        "body": json.dumps({"processed_files": results}),
    }


def main() -> None:
    print("[main] Running in local mode")
    csv_path = os.environ.get("LOCAL_CSV_PATH", "data/sample_transactions.csv")
    source_file = os.path.abspath(csv_path)
    print(f"[main] CSV path: {csv_path}")
    print(f"[main] DB_HOST={os.environ.get('DB_HOST', '(not set)')}")
    print(f"[main] DB_NAME={os.environ.get('DB_NAME', '(not set)')}")

    try:
        print(f"[main] Reading local file: {csv_path}")
        with open(csv_path, "rb") as csv_file:
            content = csv_file.read()
        print(f"[main] Read {len(content)} bytes from disk")
    except Exception:
        print(f"[main] ERROR: Could not read local file {csv_path}")
        traceback.print_exc()
        raise

    try:
        result = process_transaction_file(content, source_file)
        print("[main] Local run completed successfully")
        print(json.dumps(result, indent=2))
    except Exception:
        print("[main] Local run failed")
        traceback.print_exc()
        raise


if __name__ == "__main__":
    main()

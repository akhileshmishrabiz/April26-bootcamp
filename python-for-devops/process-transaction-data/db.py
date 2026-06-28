import os
import traceback
from contextlib import contextmanager
from decimal import Decimal
from typing import Any, Iterator

import psycopg2
from psycopg2.extras import execute_values

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS vendor_transactions (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(64) UNIQUE NOT NULL,
    transaction_date DATE NOT NULL,
    vendor_name VARCHAR(255) NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    category VARCHAR(100),
    description TEXT,
    status VARCHAR(50) NOT NULL,
    source_file VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
"""

INSERT_SQL = """
INSERT INTO vendor_transactions (
    transaction_id,
    transaction_date,
    vendor_name,
    amount,
    currency,
    category,
    description,
    status,
    source_file
) VALUES %s
ON CONFLICT (transaction_id) DO UPDATE SET
    transaction_date = EXCLUDED.transaction_date,
    vendor_name = EXCLUDED.vendor_name,
    amount = EXCLUDED.amount,
    currency = EXCLUDED.currency,
    category = EXCLUDED.category,
    description = EXCLUDED.description,
    status = EXCLUDED.status,
    source_file = EXCLUDED.source_file;
"""


def get_db_config() -> dict[str, Any]:
    print("[db] Loading database config from environment variables")
    required = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        print(f"[db] ERROR: Missing required env vars: {', '.join(missing)}")
        raise EnvironmentError(f"Missing required env vars: {', '.join(missing)}")

    config = {
        "host": os.environ["DB_HOST"],
        "port": int(os.environ.get("DB_PORT", "5432")),
        "dbname": os.environ["DB_NAME"],
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
    }
    print(
        f"[db] Config loaded — host={config['host']}, "
        f"port={config['port']}, dbname={config['dbname']}, user={config['user']}"
    )
    return config


@contextmanager
def get_connection() -> Iterator[Any]:
    print("[db] Opening PostgreSQL connection...")
    try:
        conn = psycopg2.connect(**get_db_config())
        print("[db] Connection opened successfully")
    except Exception:
        print("[db] ERROR: Could not connect to PostgreSQL")
        traceback.print_exc()
        raise

    try:
        yield conn
        print("[db] Committing transaction...")
        conn.commit()
        print("[db] Commit successful")
    except Exception:
        print("[db] ERROR: Rolling back transaction due to failure")
        conn.rollback()
        traceback.print_exc()
        raise
    finally:
        conn.close()
        print("[db] Connection closed")


def ensure_table_exists(conn: Any) -> None:
    print("[db] Running CREATE TABLE IF NOT EXISTS vendor_transactions...")
    try:
        with conn.cursor() as cur:
            cur.execute(CREATE_TABLE_SQL)
        print("[db] Table vendor_transactions is ready")
    except Exception:
        print("[db] ERROR: Failed to create or verify vendor_transactions table")
        traceback.print_exc()
        raise


def insert_transactions(
    conn: Any,
    rows: list[dict[str, Any]],
    source_file: str,
) -> int:
    if not rows:
        print("[db] No rows to insert — skipping")
        return 0

    print(f"[db] Preparing {len(rows)} row(s) for insert/upsert from {source_file}")

    values = [
        (
            row["transaction_id"],
            row["transaction_date"],
            row["vendor_name"],
            Decimal(str(row["amount"])),
            row.get("currency", "USD"),
            row.get("category"),
            row.get("description"),
            row["status"],
            source_file,
        )
        for row in rows
    ]

    try:
        with conn.cursor() as cur:
            execute_values(cur, INSERT_SQL, values)
        print(f"[db] Insert/upsert complete — {len(values)} row(s) affected")
    except Exception:
        print("[db] ERROR: Failed to insert rows into vendor_transactions")
        traceback.print_exc()
        raise

    return len(values)

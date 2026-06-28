import csv
import io
import traceback
from datetime import datetime
from typing import Any


REQUIRED_COLUMNS = {
    "transaction_id",
    "transaction_date",
    "vendor_name",
    "amount",
    "status",
}


def parse_transactions_csv(content: bytes | str) -> list[dict[str, Any]]:
    print("[parser] Starting CSV parse")
    text = content.decode("utf-8") if isinstance(content, bytes) else content
    print(f"[parser] Decoded content — {len(text)} characters")

    try:
        reader = csv.DictReader(io.StringIO(text))
    except Exception:
        print("[parser] ERROR: Could not initialize CSV reader")
        traceback.print_exc()
        raise

    if not reader.fieldnames:
        print("[parser] ERROR: CSV file is missing a header row")
        raise ValueError("CSV file is missing a header row")

    print(f"[parser] Found columns: {', '.join(reader.fieldnames)}")

    missing = REQUIRED_COLUMNS - set(reader.fieldnames)
    if missing:
        print(f"[parser] ERROR: Missing required columns: {', '.join(sorted(missing))}")
        raise ValueError(f"CSV is missing required columns: {', '.join(sorted(missing))}")

    transactions: list[dict[str, Any]] = []
    for line_number, row in enumerate(reader, start=2):
        try:
            transaction_id = (row.get("transaction_id") or "").strip()
            if not transaction_id:
                raise ValueError(f"Row {line_number}: transaction_id is required")

            raw_date = (row.get("transaction_date") or "").strip()
            try:
                transaction_date = datetime.strptime(raw_date, "%Y-%m-%d").date()
            except ValueError as exc:
                raise ValueError(
                    f"Row {line_number}: invalid transaction_date '{raw_date}', expected YYYY-MM-DD"
                ) from exc

            vendor_name = (row.get("vendor_name") or "").strip()
            if not vendor_name:
                raise ValueError(f"Row {line_number}: vendor_name is required")

            raw_amount = (row.get("amount") or "").strip()
            try:
                amount = float(raw_amount)
            except ValueError as exc:
                raise ValueError(f"Row {line_number}: invalid amount '{raw_amount}'") from exc

            status = (row.get("status") or "").strip()
            if not status:
                raise ValueError(f"Row {line_number}: status is required")

            transactions.append(
                {
                    "transaction_id": transaction_id,
                    "transaction_date": transaction_date,
                    "vendor_name": vendor_name,
                    "amount": amount,
                    "currency": (row.get("currency") or "USD").strip().upper(),
                    "category": (row.get("category") or "").strip() or None,
                    "description": (row.get("description") or "").strip() or None,
                    "status": status,
                }
            )
            print(
                f"[parser] Row {line_number} OK — "
                f"id={transaction_id}, vendor={vendor_name}, amount={amount}, status={status}"
            )
        except Exception:
            print(f"[parser] ERROR: Failed to parse row {line_number}")
            traceback.print_exc()
            raise

    print(f"[parser] CSV parse complete — {len(transactions)} valid row(s)")
    return transactions

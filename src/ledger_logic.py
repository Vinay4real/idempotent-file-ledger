"""Pure hash-check decision logic, kept free of boto3 so it's testable without AWS."""
import hashlib


def compute_sha256(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def decide_action(existing_item: dict | None, now: str) -> dict:
    """Given the current ledger item for a hash (or None), decide the item to write.

    - No existing item -> brand new file, status 'new'.
    - Existing item with status 'new' or 'duplicate' -> another copy, status 'duplicate'.
    - Existing item with status 'failed' -> reprocess, status resets to 'new'.
    """
    if existing_item is None:
        return {"status": "new", "attempt_count": 1, "first_seen_at": now}

    status = existing_item["status"]
    attempt_count = int(existing_item.get("attempt_count", 0))
    first_seen_at = existing_item.get("first_seen_at", now)

    if status == "failed":
        return {"status": "new", "attempt_count": attempt_count + 1, "first_seen_at": first_seen_at}

    if status in ("new", "duplicate"):
        return {"status": "duplicate", "attempt_count": attempt_count + 1, "first_seen_at": first_seen_at}

    raise ValueError(f"unknown ledger status: {status!r}")

from ledger_logic import compute_sha256, decide_action

NOW = "2026-08-08T00:00:00Z"


def test_new_file_has_no_existing_item():
    result = decide_action(None, NOW)
    assert result == {"status": "new", "attempt_count": 1, "first_seen_at": NOW}


def test_exact_duplicate_of_a_new_file_increments_attempt_count():
    existing = {"status": "new", "attempt_count": 1, "first_seen_at": "2026-08-07T00:00:00Z"}
    result = decide_action(existing, NOW)
    assert result == {"status": "duplicate", "attempt_count": 2, "first_seen_at": "2026-08-07T00:00:00Z"}


def test_duplicate_of_a_duplicate_keeps_incrementing():
    existing = {"status": "duplicate", "attempt_count": 3, "first_seen_at": "2026-08-07T00:00:00Z"}
    result = decide_action(existing, NOW)
    assert result == {"status": "duplicate", "attempt_count": 4, "first_seen_at": "2026-08-07T00:00:00Z"}


def test_previously_failed_file_is_reset_for_retry():
    existing = {"status": "failed", "attempt_count": 1, "first_seen_at": "2026-08-07T00:00:00Z"}
    result = decide_action(existing, NOW)
    assert result == {"status": "new", "attempt_count": 2, "first_seen_at": "2026-08-07T00:00:00Z"}


def test_hash_is_stable_for_identical_content():
    assert compute_sha256(b"hello world") == compute_sha256(b"hello world")


def test_hash_differs_for_different_content():
    assert compute_sha256(b"hello world") != compute_sha256(b"hello there")

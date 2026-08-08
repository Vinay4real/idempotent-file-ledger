# Day 2 — Ingestion Lambda + ledger table

Builds on [Day 1](./README.md) (S3 bucket + base IAM). Today: the DynamoDB
ledger, the hash-check Lambda, the S3 trigger wiring it together, and
end-to-end verification against MiniStack.

## What was built

- `dynamodb.tf` — `file-ledger` table, `file_hash` (string) as the sole hash
  key. Status/file_name/first_seen_at/last_seen_at/attempt_count are
  item-level attributes, not part of the table schema — DynamoDB only
  declares key attributes; everything else is written per-item.
- `iam.tf` — narrowed the DynamoDB policy statement from `resources = ["*"]`
  (Day 1 placeholder) to `aws_dynamodb_table.ledger.arn` now that the table
  exists.
- `src/ledger_logic.py` — pure decision function (`decide_action`) plus
  `compute_sha256`. No boto3 import, so it's unit-testable without AWS.
- `src/handler.py` — the actual Lambda entry point: for each S3 record, reads
  the object, hashes it, calls `decide_action`, writes the result back to
  DynamoDB.
- `lambda.tf` — zips `src/` via the `archive_file` data source, deploys it as
  `file-ledger-ingest` (Python 3.12), grants S3 permission to invoke it, and
  wires an `aws_s3_bucket_notification` so any `ObjectCreated` event on
  `file-ledger-landing` triggers it.
- `tests/test_ledger_logic.py` — 6 pytest cases against `ledger_logic`
  directly (see below).

## DynamoDB schema

| Attribute       | Type | Role                                      |
|-----------------|------|--------------------------------------------|
| `file_hash`     | S    | partition key — SHA-256 hex digest of content |
| `status`        | S    | `new` \| `duplicate` \| `failed`          |
| `file_name`     | S    | S3 key of the most recent upload with this hash |
| `first_seen_at` | S    | ISO8601 UTC, set once, never overwritten  |
| `last_seen_at`  | S    | ISO8601 UTC, refreshed every hit          |
| `attempt_count` | N    | incremented on every hit after the first  |

## How the hash-check logic works

`decide_action(existing_item, now)` in `src/ledger_logic.py` is a pure
function — no I/O — that takes the current ledger item for a hash (or
`None`) and returns what the new item should look like:

- **No existing item** → genuinely new file → `status=new`, `attempt_count=1`.
- **Existing item, `status` is `new` or `duplicate`** → same content seen
  again → `status=duplicate`, `attempt_count` incremented, `first_seen_at`
  carried forward.
- **Existing item, `status` is `failed`** → treated as a retry → `status`
  resets to `new`, `attempt_count` incremented, `first_seen_at` carried
  forward.

`src/handler.py` is the only place that touches boto3: it does
`get_item` → `decide_action` → `put_item` per S3 record. Keeping the decision
pure meant the tests below don't need MiniStack, Docker, or any AWS mocking
library running.

## pytest results

```
$ python3 -m pytest tests/ -v
tests/test_ledger_logic.py::test_new_file_has_no_existing_item PASSED
tests/test_ledger_logic.py::test_exact_duplicate_of_a_new_file_increments_attempt_count PASSED
tests/test_ledger_logic.py::test_duplicate_of_a_duplicate_keeps_incrementing PASSED
tests/test_ledger_logic.py::test_previously_failed_file_is_reset_for_retry PASSED
tests/test_ledger_logic.py::test_hash_is_stable_for_identical_content PASSED
tests/test_ledger_logic.py::test_hash_differs_for_different_content PASSED
6 passed in 0.02s
```

## Manual end-to-end verification (real output)

```bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
echo "hello file ledger, day 2" > /tmp/day2-test-file.txt
shasum -a 256 /tmp/day2-test-file.txt
# 43b197964f7c2740d27565d6282f4ac542fc53484d1e0148be47894ca481d71b
```

**1. Upload the file (first time):**

```bash
$ aws --endpoint-url=http://localhost:4566 s3api put-object \
    --bucket file-ledger-landing --key day2-test-file.txt \
    --body /tmp/day2-test-file.txt --checksum-algorithm SHA256
{
    "ETag": "\"51db9f3ac99aeb2aecfca40b00b1ffbd\""
}
```

**2. Check the ledger entry (Lambda fired automatically off the S3 trigger):**

```bash
$ aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name file-ledger
{
    "Items": [
        {
            "file_hash": {"S": "43b197964f7c2740d27565d6282f4ac542fc53484d1e0148be47894ca481d71b"},
            "file_name": {"S": "day2-test-file.txt"},
            "status": {"S": "new"},
            "first_seen_at": {"S": "2026-08-07T22:03:58Z"},
            "last_seen_at": {"S": "2026-08-07T22:03:58Z"},
            "attempt_count": {"N": "1"}
        }
    ],
    "Count": 1,
    "ScannedCount": 1
}
```

**3. Upload the identical content again, under a new key:**

```bash
$ aws --endpoint-url=http://localhost:4566 s3api put-object \
    --bucket file-ledger-landing --key day2-test-file-copy.txt \
    --body /tmp/day2-test-file.txt --checksum-algorithm SHA256
{
    "ETag": "\"51db9f3ac99aeb2aecfca40b00b1ffbd\""
}
```

**4. Confirm it's now marked duplicate, with `attempt_count` incremented:**

```bash
$ aws --endpoint-url=http://localhost:4566 dynamodb get-item \
    --table-name file-ledger \
    --key '{"file_hash": {"S": "43b197964f7c2740d27565d6282f4ac542fc53484d1e0148be47894ca481d71b"}}'
{
    "Item": {
        "file_hash": {"S": "43b197964f7c2740d27565d6282f4ac542fc53484d1e0148be47894ca481d71b"},
        "file_name": {"S": "day2-test-file-copy.txt"},
        "status": {"S": "duplicate"},
        "first_seen_at": {"S": "2026-08-07T22:03:58Z"},
        "last_seen_at": {"S": "2026-08-07T22:04:14Z"},
        "attempt_count": {"N": "2"}
    }
}
```

`status` flipped to `duplicate`, `attempt_count` went 1 → 2, `first_seen_at`
stayed pinned to the original upload, `last_seen_at` and `file_name` updated
to the second upload. The S3 trigger → Lambda → DynamoDB path works
end-to-end with no manual invocation.

## Issues hit along the way

1. **Lambda silently went to real AWS, not MiniStack.** `terraform apply`
   failed with `UnrecognizedClientException: The security token included in
   the request is invalid` on `aws_lambda_function.ledger`. Turning on
   `TF_LOG=DEBUG` showed the actual request target:
   `http.url=https://lambda.us-east-1.amazonaws.com/...` — real AWS,
   correctly rejecting the dummy `test`/`test` credentials. Root cause:
   Day 1's `provider.tf` `endpoints {}` block only listed `s3`, `iam`,
   `dynamodb`, and `sts` — no `lambda`. Fix was one line:
   `lambda = "http://localhost:4566"`. Lesson: the AWS provider only routes
   a service to MiniStack if that service has an explicit entry in
   `endpoints {}`; a missing entry fails open to real AWS rather than
   erroring immediately, so it's worth listing every service you provision
   up front.

2. **`aws s3 cp` failed with an unsupported checksum algorithm.** Current
   awscli defaults `s3 cp`/`s3 sync` uploads to a `CRC64NVME` checksum, which
   this MiniStack build doesn't implement (`Checksum algorithm not supported
   ... Supported: SHA256, SHA1, CRC32`). Worked around by using
   `aws s3api put-object --checksum-algorithm SHA256` instead of `s3 cp` for
   the verification steps above.

3. **MiniStack doesn't run Lambda in Docker — it runs a local subprocess.**
   The ask was "real Docker execution, not a mock." Looking at
   `ministack/core/lambda_runtime.py`, MiniStack executes Lambda code by
   spawning a persistent host subprocess running the matching runtime binary
   (e.g. the local `python3.12`) and talking to it over stdin/stdout — not by
   launching a Docker container per invocation. It genuinely executes your
   `handler.py` (not stubbed/mocked — confirmed by the real hash and ledger
   writes above), just not inside a container. If container-level isolation
   is a hard requirement, that's a gap this MiniStack version doesn't cover;
   flagging rather than papering over it.

4. **`status=failed` is handled but never produced.** `decide_action`
   correctly resets a `failed` entry to `new` on retry (unit tested), but
   nothing in the current pipeline ever sets `status=failed` — there's no
   downstream consumer yet that processes `new` entries and can fail. This
   is intentional scope (today was ingestion + dedup only) but worth calling
   out so it isn't mistaken for a bug: the retry path is ready, just unused
   until a processing stage exists.

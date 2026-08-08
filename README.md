# idempotent-file-ledger

Idempotent file-ingestion pipeline: files land in S3, a Lambda hashes their
content and checks a DynamoDB ledger before treating them as new, so retries
and duplicate uploads don't get double-processed. Runs against
[MiniStack](https://github.com/ministackorg/ministack) (local AWS emulator,
`http://localhost:4566`) instead of real AWS.

## Architecture

```
S3 (file-ledger-landing) --ObjectCreated--> Lambda (file-ledger-ingest) --get/put--> DynamoDB (file-ledger)
```

The Lambda assumes `file-ledger-lambda-role`, scoped to read the landing
bucket and read/write the ledger table only.

## Components

- **Terraform** (repo root) — infra, targeting MiniStack
  - `provider.tf`, `versions.tf` — AWS provider pointed at MiniStack (dummy creds, endpoint overrides per-service)
  - `s3.tf` — `file-ledger-landing` bucket
  - `dynamodb.tf` — `file-ledger` table
  - `iam.tf` — Lambda execution role + policy
  - `lambda.tf` — Lambda function, S3 event trigger, packaging (`archive_file` zip of `src/`)
- **`src/`** — Lambda source
  - `ledger_logic.py` — pure hash-check decision logic, no AWS SDK dependency
  - `handler.py` — S3/DynamoDB I/O wrapper around `ledger_logic`
- **`tests/`** — pytest unit tests for `ledger_logic` (no AWS/MiniStack required)

## Ledger semantics

`file_hash` (SHA-256 of the object's content) is the DynamoDB partition key.
On every S3 upload, the Lambda looks up the hash and decides:

| Existing item             | Result                                    |
|----------------------------|--------------------------------------------|
| none                        | `status=new`, `attempt_count=1`            |
| `status=new` or `duplicate` | `status=duplicate`, `attempt_count += 1`   |
| `status=failed`             | `status=new` (retry), `attempt_count += 1` |

`first_seen_at` is preserved across updates; `last_seen_at` is refreshed on
every hit. Note: nothing in this pipeline currently *writes* `status=failed`
— that's expected to come from a downstream processor that consumes `new`
entries; see [day2-README.md](./day2-README.md).

## Running locally

Prerequisites: MiniStack on `http://localhost:4566`, `terraform`
(`brew install hashicorp/tap/terraform`), `awscli` (`brew install awscli`).

```bash
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

```bash
alias awslocal='AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 aws --endpoint-url=http://localhost:4566'
awslocal s3 ls
awslocal dynamodb scan --table-name file-ledger
```

```bash
python3 -m pytest tests/ -v
```

## Day-by-day logs

Build history, manual verification output, and issues hit each day live in
`dayN-README.md` (see [day2-README.md](./day2-README.md)) — this file stays
a current snapshot of the architecture, not a changelog.

## Not yet done

- Nothing writes `status=failed` yet (no downstream processor exists)
- Bucket versioning/encryption/lifecycle rules
- Lambda dead-letter queue / error handling for a failed S3 `get_object` or DynamoDB write

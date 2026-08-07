# idempotent-file-ledger

## Day 1 — Terraform + MiniStack bootstrap

Terraform project targeting [MiniStack](http://localhost:4566) (local AWS
emulator) instead of real AWS.

### Layout

- `versions.tf` — Terraform + AWS provider version pins
- `provider.tf` — AWS provider pointed at MiniStack (dummy creds, validation skipped)
- `s3.tf` — `file-ledger-landing` bucket for incoming files
- `iam.tf` — `file-ledger-lambda-role` + policy (read S3 landing bucket, write DynamoDB) for the future ingest Lambda

### Prerequisites

- MiniStack running locally on `http://localhost:4566`
- `terraform` (`brew install hashicorp/tap/terraform`)
- `awscli` (`brew install awscli`)

### Run

```bash
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

### Verify

```bash
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
  aws --endpoint-url=http://localhost:4566 s3 ls
# → file-ledger-landing
```

Optional shell alias so you don't retype creds/endpoint every time:

```bash
alias awslocal='AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 aws --endpoint-url=http://localhost:4566'
```

### Not yet done

- DynamoDB ledger table (IAM policy currently scoped to `resources = ["*"]`, narrow once the table ARN exists)
- Lambda function itself
- Bucket versioning/encryption/lifecycle rules

# The hash-dedup ledger the ingest Lambda reads/writes on every S3 upload.
# DynamoDB is schemaless beyond its key attributes — status, file_name,
# first_seen_at, last_seen_at, and attempt_count are written per-item by the
# Lambda (see src/handler.py) and don't need to be declared here.
resource "aws_dynamodb_table" "ledger" {
  name         = "file-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_hash"

  attribute {
    name = "file_hash"
    type = "S"
  }
}

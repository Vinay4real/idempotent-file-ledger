# Landing bucket for incoming files. Its ObjectCreated events trigger the
# ingest Lambda (wired in lambda.tf).
resource "aws_s3_bucket" "landing" {
  bucket = "file-ledger-landing"
}

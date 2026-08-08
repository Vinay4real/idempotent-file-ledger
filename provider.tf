# AWS provider pointed at MiniStack instead of real AWS. Every service this
# project provisions must be listed in `endpoints {}` below, or Terraform
# quietly falls back to hitting real AWS for that service and fails on the
# dummy credentials (bit us with `lambda` on Day 2 — see day2-README.md).
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://localhost:4566"
    iam      = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
    sts      = "http://localhost:4566"
    lambda   = "http://localhost:4566"
  }
}

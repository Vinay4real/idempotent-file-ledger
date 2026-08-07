data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ledger_lambda" {
  name               = "file-ledger-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "ledger_lambda" {
  statement {
    sid       = "ReadLandingBucket"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.landing.arn, "${aws_s3_bucket.landing.arn}/*"]
  }

  statement {
    sid = "WriteDynamoDB"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    # No table exists yet; scope to a table ARN once the ledger table is added.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ledger_lambda" {
  name   = "file-ledger-lambda-policy"
  role   = aws_iam_role.ledger_lambda.id
  policy = data.aws_iam_policy_document.ledger_lambda.json
}

# Packages src/ into a zip and deploys it as the ingest function, which
# fires on every ObjectCreated event from the landing bucket (s3.tf).
data "archive_file" "ledger_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/ledger_lambda.zip"
}

resource "aws_lambda_function" "ledger" {
  function_name    = "file-ledger-ingest"
  role             = aws_iam_role.ledger_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.ledger_lambda.output_path
  source_code_hash = data.archive_file.ledger_lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.ledger.name
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ledger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.landing.arn
}

resource "aws_s3_bucket_notification" "landing" {
  bucket = aws_s3_bucket.landing.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ledger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

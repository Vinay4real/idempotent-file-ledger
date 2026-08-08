output "landing_bucket_name" {
  value = aws_s3_bucket.landing.bucket
}

output "ledger_table_name" {
  value = aws_dynamodb_table.ledger.name
}

output "lambda_function_name" {
  value = aws_lambda_function.ledger.function_name
}

output "lambda_role_arn" {
  value = aws_iam_role.ledger_lambda.arn
}

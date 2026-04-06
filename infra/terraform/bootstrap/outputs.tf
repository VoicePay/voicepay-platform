output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dev_state_policy_arn" {
  description = "IAM policy ARN for dev state access"
  value       = aws_iam_policy.terraform_state_dev.arn
}

output "staging_state_policy_arn" {
  description = "IAM policy ARN for staging state access"
  value       = aws_iam_policy.terraform_state_staging.arn
}

output "prod_state_policy_arn" {
  description = "IAM policy ARN for prod state access"
  value       = aws_iam_policy.terraform_state_prod.arn
}

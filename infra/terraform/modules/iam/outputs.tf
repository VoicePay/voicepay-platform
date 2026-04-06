output "app_role_arn" {
  description = "Application IAM role ARN"
  value       = aws_iam_role.app.arn
}

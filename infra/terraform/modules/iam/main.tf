resource "aws_iam_role" "app" {
  name = "voicepay-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "voicepay-${var.environment}-app-role"
    Environment = var.environment
  }
}

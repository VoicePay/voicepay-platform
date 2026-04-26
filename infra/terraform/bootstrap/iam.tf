resource "aws_iam_policy" "terraform_state_dev" {
  name        = "voicepay-terraform-state-dev"
  description = "Scoped access to dev Terraform state"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}/dev/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}"
      }
    ]
  })

  tags = {
    Name        = "voicepay-terraform-state-dev"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "terraform_state_staging" {
  name        = "voicepay-terraform-state-staging"
  description = "Scoped access to staging Terraform state"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}/staging/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}"
      }
    ]
  })

  tags = {
    Name        = "voicepay-terraform-state-staging"
    ManagedBy   = "Terraform"
    Environment = "staging"
  }
}

resource "aws_iam_policy" "terraform_state_prod" {
  name        = "voicepay-terraform-state-prod"
  description = "Scoped access to prod Terraform state"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}/prod/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::voicepay-terraform-state-${var.aws_account_id}"
      }
    ]
  })

  tags = {
    Name        = "voicepay-terraform-state-prod"
    ManagedBy   = "Terraform"
    Environment = "prod"
  }
}

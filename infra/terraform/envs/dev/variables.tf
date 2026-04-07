variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "147177189510"
}

variable "github_org" {
  description = "GitHub organisation name"
  type        = string
  default     = "VoicePay"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "voicepay-platform"
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  type        = string

  validation {
    condition     = length(var.github_oidc_provider_arn) > 0
    error_message = "github_oidc_provider_arn must be set before provisioning."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "voicepay"
    Environment = "dev"
    Owner       = "platform-team"
    ManagedBy   = "Terraform"
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_org" {
  description = "GitHub organisation name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider for CI/CD role"
  type        = string

  validation {
    condition     = length(var.github_oidc_provider_arn) > 0
    error_message = "github_oidc_provider_arn must be set before provisioning."
  }
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for ArgoCD role"
  type        = string
  default     = ""
}

variable "eks_oidc_issuer" {
  description = "EKS OIDC issuer URL for ArgoCD role"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
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
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.2.4.0/24", "10.2.5.0/24", "10.2.6.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway"
  type        = bool
  default     = true
}

variable "ecr_repository_names" {
  description = "List of ECR repository names"
  type        = list(string)
  default     = ["auth", "payment", "notification"]
}

variable "ecr_image_retention_count" {
  description = "Number of images to retain per ECR repository"
  type        = number
  default     = 3
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability — IMMUTABLE in prod to prevent tag overwriting"
  type        = string
  default     = "IMMUTABLE"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "voicepay"
    Environment = "prod"
    Owner       = "platform-team"
    ManagedBy   = "Terraform"
  }
}

# VoicePay Infrastructure

This directory contains all infrastructure-as-code for the VoicePay platform using Terraform.

## Structure

```
terraform/
├── envs/                  # Environment-specific configurations
│   ├── dev/               # Development environment
│   ├── staging/           # Staging environment
│   └── prod/              # Production environment
└── modules/               # Reusable Terraform modules
    ├── vpc/               # VPC and networking
    ├── eks/               # EKS cluster
    └── iam/               # IAM roles and policies
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- AWS CLI configured with appropriate credentials
- IAM user with required permissions

## Usage

Navigate to the environment you want to work with:

```bash
cd envs/dev
```

Initialize Terraform:

```bash
terraform init
```

Preview changes:

```bash
terraform plan
```

Apply changes:

```bash
terraform apply
```

## Modules

- `vpc` — Provisions a VPC with DNS support enabled
- `eks` — Provisions an EKS cluster with the required IAM role
- `iam` — Provisions application IAM roles with least privilege

## Environment Variables

Each environment uses the following variables:

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region to deploy resources | `us-east-1` |
| `environment` | Deployment environment | `dev` / `staging` / `prod` |

## Notes

- Never commit `.tfvars` files — they may contain sensitive values
- State files (`*.tfstate`) are excluded from version control
- Remote state backend (S3 + DynamoDB) will be configured in a future task

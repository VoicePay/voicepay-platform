# VoicePay Infrastructure

This directory contains all infrastructure-as-code for the VoicePay platform using Terraform.

## Structure

```
terraform/
├── bootstrap/             # One-time setup for remote state infrastructure
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

## Remote State

Terraform state is stored remotely in AWS S3 with DynamoDB for state locking.

| Resource | Name |
|---|---|
| S3 Bucket | `voicepay-terraform-state-<account-id>` |
| DynamoDB Table | `voicepay-terraform-locks` |

Each environment has its own isolated state file:

| Environment | State Key |
|---|---|
| dev | `dev/terraform.tfstate` |
| staging | `staging/terraform.tfstate` |
| prod | `prod/terraform.tfstate` |

### Bootstrap

The S3 bucket and DynamoDB table are provisioned once using the `bootstrap` configuration. This only needs to be run once per AWS account:

```bash
cd bootstrap
terraform init
terraform apply -var="aws_account_id=<your-account-id>"
```

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

## Tagging Strategy

All resources are tagged consistently using a `tags` variable of type `map(string)` defined in each environment and passed down to all modules via `merge(var.tags, {...})`.

Standard tags applied to every resource:

| Tag | Description | Example |
|---|---|---|
| `Project` | Project name | `voicepay` |
| `Environment` | Deployment environment | `dev`, `staging`, `prod` |
| `Owner` | Team responsible for the resource | `platform-team` |
| `ManagedBy` | How the resource is managed | `Terraform` |
| `Name` | Resource-specific name | `voicepay-dev-vpc` |

## Modules

- `vpc` — Provisions a VPC with DNS support enabled
- `eks` — Provisions an EKS cluster with the required IAM role
- `iam` — Provisions the following IAM roles with least privilege:
  - `cicd` — GitHub Actions OIDC role scoped to ECR push on `voicepay-*` repositories
  - `terraform` — Terraform execution role scoped to `us-east-1`
  - `eks_cluster` — EKS control plane role using AWS managed `AmazonEKSClusterPolicy`
  - `eks_node` — EKS worker node role with ECR read, CNI, and worker node policies
  - `argocd` — IRSA-based role scoped to ECR pull on `voicepay-*` repositories

## Environment Variables

Each environment uses the following variables:

| Variable | Description | Default |
|---|---|---|
| `aws_region` | AWS region to deploy resources | `us-east-1` |
| `environment` | Deployment environment | `dev` / `staging` / `prod` |

## Notes

- Never commit `.tfvars` files — they may contain sensitive values
- State files (`*.tfstate`) are excluded from version control
- Remote state is stored in S3 with state locking via DynamoDB

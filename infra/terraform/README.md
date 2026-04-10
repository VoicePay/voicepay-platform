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
    ├── ecr/               # Container registries
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

## CI/CD

Terraform changes are validated and deployed via GitHub Actions. See [`.github/workflows/terraform.yml`](../../../.github/workflows/terraform.yml).

On every pull request to `dev`, `staging`, or `prod`:
- `terraform init` — initializes the backend and modules
- `terraform fmt -check` — validates formatting
- `terraform validate` — checks configuration is valid
- `terraform plan` — shows what will change, posted as a PR comment

On merge:
- `staging` — automatically applies
- `dev` and `prod` — require manual trigger via `workflow_dispatch`

### Manual Trigger

Go to **GitHub Actions → Terraform → Run workflow** and select:
- **Environment** — `dev`, `staging`, or `prod`
- **Action** — `plan`, `apply`, or `destroy`

## Environment Configuration

Each environment is isolated with its own state file and environment-specific variables while sharing the same module structure.

| Configuration | dev | staging | prod |
|---|---|---|---|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| Availability Zones | 2 | 2 | 3 |
| NAT Gateway | Disabled | Enabled | Enabled |
| Node Instance Type | `t3.medium` | `t3.medium` | `t3.large` |
| Node Desired Count | 2 | 2 | 3 |
| Image Tag Mutability | `MUTABLE` | `MUTABLE` | `IMMUTABLE` |

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

- `vpc` — Provisions a VPC with public and private subnets, internet gateway, route tables, and optional NAT gateway. Key variables:
  - `vpc_cidr` — configurable CIDR block (default `10.0.0.0/16`)
  - `availability_zones` — list of AZs to deploy subnets into
  - `public_subnet_cidrs` / `private_subnet_cidrs` — configurable subnet CIDRs
  - `enable_nat_gateway` — toggle NAT gateway on/off (disabled by default in dev for cost optimization)
- `ecr` — Provisions ECR repositories with lifecycle policies and image scanning. Key variables:
  - `repository_names` — list of repositories to create (default: `auth`, `payment`, `notification`)
  - `image_retention_count` — number of images to retain per repository (default: `3`)
  - `image_tag_mutability` — `MUTABLE` in dev, `IMMUTABLE` in prod to prevent tag overwriting
- `eks` — Provisions an EKS cluster with a managed node group and OIDC provider for IRSA. Key variables:
  - `kubernetes_version` — configurable Kubernetes version (default `1.29`)
  - `cluster_role_arn` / `node_role_arn` — IAM roles passed from the IAM module
  - `subnet_ids` — private subnet IDs passed from the VPC module
  - `node_instance_types` — configurable EC2 instance types (default `t3.medium`)
  - `node_desired_size` / `node_min_size` / `node_max_size` — configurable node scaling
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

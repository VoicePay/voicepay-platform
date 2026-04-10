# Terraform Bootstrap

This directory provisions the foundational AWS resources required for Terraform remote state management. It is a **one-time setup** and should be run before any environment (`dev`, `staging`, `prod`) is initialized.

## What This Provisions

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `voicepay-terraform-state-<account-id>` | Stores Terraform state files |
| DynamoDB Table | `voicepay-terraform-locks` | Provides state locking to prevent concurrent modifications |
| IAM Policy | `voicepay-terraform-state-dev` | Scoped access to dev state only |
| IAM Policy | `voicepay-terraform-state-staging` | Scoped access to staging state only |
| IAM Policy | `voicepay-terraform-state-prod` | Scoped access to prod state only |

## S3 Bucket Configuration

- **Versioning** — enabled, allowing state recovery from previous versions
- **Encryption** — AES256 server-side encryption
- **Public access** — fully blocked
- **Lifecycle policy** — non-current versions expire after 90 days to optimize cost

## Important Notes

> ⚠️ The bootstrap state is stored **locally**. This is an intentional trade-off — the bootstrap provisions the very infrastructure needed for remote state, so it cannot use remote state itself. The local state file (`terraform.tfstate`) should be kept safe and never committed to version control.

> ⚠️ `prevent_destroy` has been removed during the testing phase to allow easy cleanup. It should be re-added before production use.

## Usage

**Run once per AWS account:**

```bash
cd infra/terraform/bootstrap
terraform init
terraform plan -var="aws_account_id=<your-account-id>"
terraform apply -var="aws_account_id=<your-account-id>"
```

After applying, initialize each environment:

```bash
cd infra/terraform/envs/dev
terraform init
```

## After Bootstrap

Each environment is configured to use the remote backend automatically. State files are isolated per environment:

| Environment | State Key |
|---|---|
| dev | `dev/terraform.tfstate` |
| staging | `staging/terraform.tfstate` |
| prod | `prod/terraform.tfstate` |

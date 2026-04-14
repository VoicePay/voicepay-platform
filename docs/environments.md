# Environments — VoicePay Platform

## Overview

VoicePay uses three isolated environments:

- dev → development and testing
- staging → pre-production validation
- prod → production workloads

Each environment is deployed using the same Terraform modules with different configurations.

---

## Environment Structure

Each environment is defined under:

infra/terraform/envs/<environment>

Example:
- envs/dev
- envs/staging
- envs/prod

Each contains:
- main.tf
- variables.tf
- outputs.tf
- backend.tf
- terraform.tfvars

---

## Environment Differences

| Feature              | dev              | staging          | prod             |
|---------------------|------------------|------------------|------------------|
| Purpose             | Development      | Pre-production   | Production       |
| NAT Gateway         | Disabled         | Enabled (1)      | Enabled (1)      |
| EKS Node Size       | Small (t3.medium)| Medium           | Production-grade |
| Apply Mode          | Manual           | Controlled       | Manual (gated)   |
| Image Mutability    | Mutable          | Immutable        | Immutable        |

---

## CI/CD Behavior

- dev:
  - Used for testing changes
  - Apply via manual trigger

- staging:
  - Used for validation
  - Previously auto-applied, now controlled to reduce cost

- prod:
  - Manual apply only
  - Requires explicit approval

---

## State Management

Each environment has:
- Separate S3 state file
- Shared DynamoDB locking table

Example:
- dev/terraform.tfstate
- staging/terraform.tfstate
- prod/terraform.tfstate

---

## Deployment Workflow

Standard flow:

1. Create feature branch
2. Open PR → triggers:
   - terraform fmt
   - validate
   - plan
3. Review changes
4. Merge to dev
5. Apply via workflow_dispatch

---

## Branching Strategy

- prod → production-ready (protected)
- dev → integration/testing
- feature/* → new work
- fix/* → hotfixes

---

## Safety Controls

- No direct changes to prod
- All changes go through PR
- Manual approval required for critical environments
- State locking enforced

---

## Cost Considerations

- Minimal resources in dev
- Controlled provisioning in staging
- Manual apply in prod

---

## Summary

Each environment is:
- Isolated
- Consistent in structure
- Controlled in deployment

This ensures safe and predictable infrastructure management.
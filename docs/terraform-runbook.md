# Terraform Runbook — VoicePay Platform

## Purpose

This runbook provides standard procedures for handling Terraform failures,
state issues, and safe recovery across all environments (dev, staging, prod).

It is designed to ensure:
- Safe infrastructure operations
- Consistent recovery from failures
- Protection against state corruption

## Preconditions

Before performing any Terraform operation:

- Confirm the target environment (dev/staging/prod)
- Ensure no other Terraform runs are active
- Review the latest CI/CD pipeline status
- Always run `terraform plan` before `apply`

## State Locking

Terraform uses DynamoDB to prevent concurrent state modifications.

Expected behavior:
- Only one operation can run at a time
- Concurrent runs will fail with a lock error

## Scenario: Failed Terraform Apply

### Symptoms
- `terraform apply` fails with an error
- Some resources may have been created

### Possible Causes
- IAM permission issues
- Invalid configuration
- Dependency failures (EKS, ECR)

### Resolution

1. Do NOT re-run immediately
2. Run:
   terraform plan
3. Review changes carefully
4. Identify and fix the root cause
5. Re-run:
   terraform apply

### Notes
- Always validate state before re-applying
- Avoid repeated apply attempts without investigation

## Scenario: State Lock Error

### Symptoms
Error acquiring the state lock

### Resolution

1. Confirm no active Terraform processes
2. Extract lock ID from error
3. Run:
   terraform force-unlock <LOCK_ID>

4. Validate state:
   terraform plan

### Warning
Only use force-unlock when no active process exists.
Improper use can corrupt Terraform state.

## Scenario: Safe Re-run After Failure

1. Run:
   terraform plan

2. Confirm:
   - No unexpected changes
   - State is consistent

3. Apply:
   terraform apply

 ### ECR Repository Not Empty

Error:
RepositoryNotEmptyException

Resolution:
- Enable force_delete in Terraform
OR
- Manually delete images before destroy

### EKS Destroy Timeout

Symptoms:
- CI job times out
- Destroy takes too long

Resolution:
- Run destroy locally
- Ensure no active workloads

## Scenario: Plan/Apply Variable Conflict

Error:
Can't change variable when applying a saved plan

Cause:
- Different variables used in plan vs apply

Resolution:
- Ensure consistency between plan and apply
- Avoid passing new variables during apply

## Scenario: Infrastructure Drift

Steps:
1. Run:
   terraform plan
2. Review unexpected changes
3. Decide:
   - Accept (update Terraform)
   - Revert (apply Terraform state)

## Standard Recovery Flow

Failure → Investigate → Plan → Fix → Apply → Validate

## Safety Rules

- Never run apply without reviewing plan
- Do not manually modify resources in AWS
- Avoid force-unlock unless necessary
- Use feature/hotfix branches for all fixes
- Do not push directly to dev/prod branches

## Known Issues

- EKS updates may fail due to no-op configuration changes
- ECR repositories must be empty before deletion
- Long-running operations may fail in CI due to timeouts

## Ownership

This runbook must be followed for all Terraform operations.
All engineers are responsible for safe execution and recovery.

## Scenario: Partial Infrastructure Failure

### Symptoms
- Terraform apply fails midway
- Some resources created, others not

### Recovery Steps

1. Run:
   terraform plan

2. Evaluate the plan output:

   - If resources are pending creation → safe to apply
   - If unexpected changes appear → investigate before applying

3. Identify root cause:
   - IAM permission issues
   - Dependency failures (EKS, ECR)
   - Misconfiguration

4. Fix the issue

5. Re-run:
   terraform apply

---

### Escalation Rule

Do NOT proceed if:
- Plan shows unexpected resource deletion
- State appears inconsistent

In this case:
- Stop execution
- Review Terraform state
- Validate against AWS console
# How I Built a Production-Grade Cloud Platform in 30 Days

## The Project

VoicePay is a cloud-native fintech platform that enables secure, voice-driven financial transactions. Over 30 days, I built the entire platform infrastructure from scratch — CI/CD, infrastructure as code, Kubernetes orchestration, secrets management, observability, and automated deployments.

This isn't a tutorial. This is what I actually built, the problems I hit, and how I solved them.

## The Stack

- **Cloud:** AWS (EKS, ECR, VPC, IAM, EBS)
- **Infrastructure as Code:** Terraform (modular, multi-environment)
- **Container Orchestration:** Kubernetes (EKS)
- **GitOps:** ArgoCD (App of Apps pattern)
- **Secrets Management:** HashiCorp Vault (sidecar injection)
- **Monitoring:** kube-prometheus-stack (Prometheus, Grafana, node-exporter, kube-state-metrics)
- **Logging:** Fluent Bit → Loki → Grafana
- **CI/CD:** GitHub Actions
- **Application:** Django (Python)

## What I Built — Day by Day

### Days 1-5: Foundation

Started with the basics — repository structure, CI pipeline, linting, testing, Docker, and ECR integration.

The CI pipeline runs on every push: black + flake8 for Python, yamllint for YAML, pytest for tests, and Docker build + push to ECR with commit SHA tags.

Key decision: monorepo architecture. Services, infrastructure, and Kubernetes manifests all in one repository. This makes cross-cutting changes atomic and simplifies CI.

### Days 6-10: Terraform & Infrastructure

Built a modular Terraform setup with reusable modules for VPC, EKS, IAM, and ECR. Each environment (dev/staging/prod) has its own configuration but shares the same modules.

Remote state lives in S3 with native state locking — no DynamoDB needed. Bootstrap pattern creates the state bucket and IAM policies.

The Terraform pipeline uses a reusable workflow with matrix strategy — dev, staging, and prod run in parallel. Supports plan, apply, and destroy via workflow_dispatch.

Added tflint and tfsec to the pipeline. tfsec caught several issues on the first run — IAM conditional roles, EKS version constraints, OIDC validation.

### Days 11-14: Pipeline Hardening

This is where things got real. Fixed terraform destroy steps, added plan artifact uploads, ECR existence checks in CI, and workflow_dispatch with plan/apply/destroy options.

Discovered EKS limitations the hard way: can't skip minor versions, nodes in private subnets need NAT gateway, t3.medium isn't Free Tier eligible.

### Days 15-17: Observability

Deployed Prometheus with django-prometheus metrics, alerting rules (ServiceDown, HighRequestLatency, HighErrorRate), and Grafana with auto-provisioned dashboards.

Integrated New Relic APM — learned the difference between EU and US endpoints, and that the Key ID is not the Key Value. Small things that cost hours.

Later upgraded to kube-prometheus-stack for production-grade monitoring: node-exporter on every node, kube-state-metrics, and pre-built Grafana dashboards.

### Days 18-19: GitOps with ArgoCD

Deployed ArgoCD locally on Docker Desktop first, then to EKS. Configured auto-sync with pruning and self-healing. Reduced sync interval from 3 minutes to 60 seconds.

Implemented the App of Apps pattern — one parent Application deploys all child apps (monitoring, logging, auth). Add a new manifest to Git, ArgoCD picks it up automatically.

Hit an issue where the ArgoCD configmap got replaced instead of patched, causing all apps to show "Unknown." Fixed by using kubectl patch and restarting the application controller.

### Days 20-22: Logging & Tracing

Built the centralized logging stack: Fluent Bit as a DaemonSet collecting from all containers, Loki as the aggregation backend with 72h retention, Grafana for querying.

Added request trace IDs using Python's ContextVar — thread-safe, injected into every log entry, propagated via X-Trace-ID header. This was initially implemented with setLogRecordFactory (not thread-safe) and refactored to use a logging Filter with ContextVar.

### Days 21-22: Secrets Management with Vault

Deployed HashiCorp Vault via Helm. Enabled Kubernetes authentication so pods authenticate using service account tokens. Created least-privilege policies — the auth service can only read its own secrets.

The key pattern: Vault Agent Injector adds a sidecar container to annotated pods. The sidecar authenticates to Vault and writes secrets to /vault/secrets/config. The application reads this file at startup. No hardcoded credentials, no environment variable secrets.

Enabled audit logging to stdout, which flows through Fluent Bit → Loki → Grafana. Every secret access is logged and queryable.

Revoked the root token after creating an orphan admin token. First attempt failed because child tokens get revoked with the parent — learned to use the -orphan flag.

### Days 23-24: Deploy to AWS

This was the big day. Provisioned the dev environment on EKS via GitHub Actions and ran the bootstrap script.

Problems hit:
- EBS CSI driver needed IRSA role — created IAM role with OIDC trust policy
- t3.small has an 11 pod limit per node — had to scale from 1 to 3 nodes
- Vault PVC pending — needed gp3 StorageClass
- Lost unseal key when Vault crashed during init — fresh install required
- ArgoCD sync delay — had to force hard refresh

All resolved. Auth service accessible via AWS LoadBalancer returning {"status": "ok"}.

### Days 25-26: Optimization & Automation

Took community feedback and implemented three optimizations:
- Switched EBS from gp2 to gp3 (lower cost, better performance)
- Removed unused DynamoDB table (already using S3 native locking)
- Tuned ArgoCD sync interval to 60 seconds

Created the bootstrap script — one command deploys the entire platform:
```bash
./scripts/bootstrap.sh voicepay-dev us-east-1
```

Made it fully idempotent after hitting failures on re-runs. The script now checks Vault state before init/unseal, skips Helm installs if already deployed, and saves credentials for recovery.

### Days 27-28: High Availability & Blue-Green

Added high availability: 2 replicas with pod anti-affinity spreading across nodes, rolling updates with maxUnavailable: 0 for zero-downtime deploys.

Implemented blue-green deployments: two deployments (blue active, green standby at 0 replicas). Traffic switch is a one-line change to the service selector in Git. Rollback is instant — switch the selector back.

Added Cluster Autoscaler to Terraform so nodes scale automatically when pods can't schedule.

### Days 29-30: Validation & Production Readiness

Ran the full end-to-end validation on a fresh EKS cluster. terraform apply + bootstrap script + everything running. No manual steps.

Final production hardening:
- PodDisruptionBudget — at least 1 pod survives node drains
- NetworkPolicy — restricts ingress to port 8000 only
- ALLOWED_HOSTS — restricted from wildcard to ELB domains
- Deployment runbook — complete documentation for any engineer to follow

Created a teardown script to clean up Kubernetes-created AWS resources before terraform destroy. Without this, ELBs and security groups block VPC deletion.

## Architecture

```
GitHub Actions (CI/CD)
    ├── Terraform → AWS (VPC, EKS, ECR, IAM, EBS CSI)
    └── Docker Build → ECR

Bootstrap Script
    ├── ArgoCD (GitOps)
    │   └── App of Apps
    │       ├── Auth Service (blue-green)
    │       ├── Monitoring (kube-prometheus-stack)
    │       └── Logging (Fluent Bit → Loki)
    ├── Vault (secrets injection)
    └── Cluster Autoscaler

Traffic Flow:
    User → LoadBalancer → Auth Service (blue/green) → Vault Secrets
```

## What I'd Do Differently

1. **Start with kube-prometheus-stack from day one** — building manual Prometheus/Grafana manifests was educational but wasted time.
2. **Use Karpenter instead of Cluster Autoscaler** — faster scaling, better instance selection.
3. **Vault auto-unseal with AWS KMS** — manual unseal doesn't scale.
4. **Terraform Helm provider** — manage ArgoCD and Vault installs via Terraform instead of a bash script.
5. **Separate infrastructure and application repos** — monorepo worked for learning but gets messy at scale.

## Numbers

- **30 days** of building
- **60+ pull requests** merged
- **8 Terraform modules** (VPC, EKS, ECR, IAM, EBS CSI, Cluster Autoscaler)
- **5 Kubernetes namespaces** (default, argocd, vault, monitoring, logging)
- **4 ArgoCD applications** managed via App of Apps
- **2 deployment slots** (blue-green)
- **1 bootstrap command** to deploy the entire platform
- **0 hardcoded secrets**

## Key Takeaways

**Automation isn't optional.** If you deployed it manually more than once, you should have automated it the first time.

**Idempotency matters.** Scripts that only work on first run aren't automation — they're one-time setup instructions.

**Production-grade isn't about features.** It's about what happens when things break. Pod disruption budgets, network policies, health probes, rollback strategies — these are what separate a demo from a platform.

**Build in public.** Posting daily forced me to ship every day, document my decisions, and accept feedback. The community caught things I missed.

The full source code and deployment runbook are in the repository. Two commands. Full platform. Repeatable.

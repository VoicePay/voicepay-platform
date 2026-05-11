# VoicePay Platform — Interview Questions & Answers

## Architecture & Design

**Q: Walk me through the architecture of this platform.**

A: VoicePay is a cloud-native platform running on AWS EKS. Infrastructure is provisioned via Terraform with modular, reusable components — VPC, EKS, IAM, ECR — each as a separate module with environment-specific configurations for dev, staging, and prod. The CI/CD pipeline uses GitHub Actions with a reusable workflow pattern and matrix strategy to run all environments in parallel.

On the Kubernetes side, ArgoCD manages all deployments using the App of Apps pattern — a single parent Application that auto-deploys child apps for monitoring, logging, and the auth service. Secrets are managed by HashiCorp Vault with sidecar injection, so no credentials exist in code or environment variables. Observability is handled by kube-prometheus-stack for metrics and Fluent Bit → Loki → Grafana for centralized logging.

The entire platform can be deployed from scratch with two commands: `terraform apply` via GitHub Actions, then `./scripts/bootstrap.sh`.

---

**Q: Why did you choose a monorepo architecture?**

A: For a platform engineering project, a monorepo makes cross-cutting changes atomic. When I update a Terraform module, the Kubernetes manifests, and the CI pipeline in the same PR, I can review the full impact in one place. It also simplifies CI — one pipeline handles linting, testing, building, and infrastructure validation.

The trade-off is that it gets harder to manage at scale with multiple teams. If this were a larger organization, I'd split into separate repos for infrastructure and application code, with a shared module registry for Terraform.

---

**Q: Why EKS over ECS or plain EC2?**

A: EKS gives us Kubernetes-native tooling — ArgoCD for GitOps, Vault Agent for secret injection, Prometheus for monitoring, and standard deployment strategies like blue-green. These patterns are portable across cloud providers. ECS would lock us into AWS-specific deployment patterns, and EC2 would require managing orchestration ourselves.

The trade-off is cost — EKS control plane is $0.10/hr. For a startup, ECS Fargate might be more cost-effective initially, but EKS scales better as the platform grows.

---

## Terraform & Infrastructure

**Q: How do you manage Terraform state?**

A: Remote state in S3 with native state locking — no DynamoDB needed. S3 added native locking support, so we removed the DynamoDB table to simplify the setup. State is encrypted at rest, versioned with 90-day noncurrent expiration, and scoped per environment with separate state keys (dev/terraform.tfstate, staging/terraform.tfstate, prod/terraform.tfstate).

Each environment has its own IAM policy that restricts access to only its state file path.

---

**Q: How do you handle environment differences in Terraform?**

A: Each environment has its own variables file with environment-specific values. Dev uses t3.small with 3 nodes, public subnets, NAT gateway disabled, and mutable ECR tags. Prod uses t3.large with 3 nodes, private subnets, NAT gateway enabled, immutable ECR tags, and public API access disabled.

The modules are identical — only the inputs change. This ensures consistency while allowing cost optimization per environment.

---

**Q: How do you handle Terraform in CI/CD?**

A: A reusable workflow runs init, fmt, validate, tflint, tfsec, and plan on every PR. Apply and destroy are triggered manually via workflow_dispatch with environment selection. The plan output is posted as a PR comment with the full plan available as an artifact.

The matrix strategy runs all three environments in parallel, so a single PR shows the impact across dev, staging, and prod.

---

**Q: What security scanning do you run on Terraform?**

A: tflint for Terraform-specific linting and tfsec for security scanning. tfsec caught several issues early — IAM roles without conditions, EKS public access without CIDR restrictions, and missing encryption configurations. Both run on every PR before plan.

---

## Kubernetes & Deployments

**Q: Explain your blue-green deployment strategy.**

A: Two deployments exist — blue and green — with a slot label. The service selector points to the active slot. Blue runs 2 replicas and receives traffic. Green runs 0 replicas as standby.

To deploy a new version: scale green to 2 replicas with the new image, verify it's healthy, then change the service selector from slot: blue to slot: green. Push to Git, ArgoCD syncs it, traffic switches instantly. Rollback is the same — change the selector back.

The key advantage over rolling updates is that rollback is instant. With rolling updates, you have to redeploy the old version and wait. With blue-green, the old pods are still running.

---

**Q: How do you ensure high availability?**

A: Multiple layers. The auth service runs 2 replicas with pod anti-affinity spreading them across different nodes. A PodDisruptionBudget ensures at least 1 pod survives during node drains. Rolling updates use maxUnavailable: 0 so a new pod must be ready before the old one terminates. Readiness probes prevent traffic from reaching pods that aren't ready. The LoadBalancer distributes traffic across healthy pods.

---

**Q: What happens when a node goes down?**

A: The pod on that node gets rescheduled to another node. During the transition, the other replica on a different node (thanks to anti-affinity) continues serving traffic. The PodDisruptionBudget prevents Kubernetes from evicting both pods simultaneously. The Cluster Autoscaler adds a new node if there's no capacity.

---

**Q: Why App of Apps pattern instead of applying manifests directly?**

A: App of Apps gives us a single entry point. Instead of applying 3 separate ArgoCD Applications, we apply one parent that manages all children. Adding a new service is just creating a manifest file in the apps directory — ArgoCD picks it up automatically. It also means the bootstrap script only needs to apply one resource, and ArgoCD handles the rest.

---

## Secrets Management

**Q: How do secrets get into your application pods?**

A: Vault Agent Injector. Pods are annotated with Vault injection annotations. When a pod is created, the Vault webhook adds an init container and sidecar. The init container authenticates to Vault using the pod's Kubernetes service account token, retrieves the secrets, and writes them to /vault/secrets/config as JSON. The application reads this file at startup.

No secrets in environment variables, no secrets in Git, no secrets in ConfigMaps. The application code has a fallback to env vars for local development where Vault isn't running.

---

**Q: How do you handle Vault authentication?**

A: Kubernetes auth method. Each service has a dedicated service account, a Vault policy scoped to only its secrets path, and a Vault role that binds the service account to the policy. The auth service can only read secret/data/voicepay-auth — it can't access any other secrets.

The root token is revoked after initial setup. An orphan admin token is used for operations. Audit logging captures every secret access and flows through Fluent Bit → Loki → Grafana.

---

**Q: What happens if Vault goes down?**

A: Existing pods continue running — they already have their secrets in /vault/secrets/config. New pods can't start because the init container can't authenticate. This is a known limitation of sidecar injection.

For production, I'd add Vault HA with Raft storage and auto-unseal via AWS KMS. Currently it's standalone mode with manual unseal, which is appropriate for dev but not production.

---

## Observability

**Q: Describe your observability stack.**

A: Three pillars. Metrics: kube-prometheus-stack gives us node-level metrics via node-exporter, container metrics via cAdvisor, Kubernetes state via kube-state-metrics, and application metrics via django-prometheus. Logs: Fluent Bit runs as a DaemonSet on every node, collects container logs, enriches them with Kubernetes metadata, and ships to Loki with 72-hour retention. Grafana queries both Prometheus and Loki.

Tracing: every request gets a unique trace ID via middleware using Python's ContextVar. The trace ID is injected into all log entries and returned in the X-Trace-ID response header for client correlation.

---

**Q: Why Loki over Elasticsearch?**

A: Cost and simplicity. Loki doesn't index log content — it only indexes labels (pod name, namespace, etc.) and stores log lines as compressed chunks. This makes it significantly cheaper to run than Elasticsearch, especially on a small cluster. For our use case — querying logs by service, namespace, or pod — Loki is sufficient.

If we needed full-text search across log content at scale, Elasticsearch would be the better choice.

---

**Q: How do you trace a request across services?**

A: Each request gets a UUID trace ID, either generated automatically or accepted from the X-Trace-ID header. The middleware sets it in a ContextVar, a logging Filter injects it into every log record, and it's returned in the response header. In Grafana, I can query Loki with the trace ID to see every log entry for that request lifecycle.

For cross-service tracing, the calling service passes the X-Trace-ID header to downstream services, maintaining the same trace ID across the entire request chain.

---

## CI/CD & Automation

**Q: How does your CI/CD pipeline work?**

A: Two pipelines. The CI pipeline runs on every push to dev/prod: lint (black, flake8), yamllint, pytest, then Docker build and push to ECR with commit SHA and latest tags. The Terraform pipeline runs on changes to infra/ files: init, fmt, validate, tflint, tfsec, plan on PRs, and apply/destroy via manual trigger.

After Terraform apply, it automatically triggers the CI pipeline to push the Docker image to ECR — this solved the chicken-and-egg problem where ECR repos are empty after infrastructure provisioning.

---

**Q: What makes your bootstrap script idempotent?**

A: Every step checks state before acting. Vault: checks if initialized before running init, checks if sealed before unsealing, checks if secrets engine exists before enabling. ArgoCD: uses --server-side apply and --dry-run=client for namespace creation. Helm: checks helm status before installing. Credentials are saved to a temp file so re-runs can find them.

The script can be run on a fresh cluster or an existing one and produces the same result.

---

**Q: Why not manage ArgoCD and Vault through Terraform?**

A: Terraform's Helm provider could install them, but the Vault configuration (init, unseal, secrets, policies) requires imperative steps that don't fit Terraform's declarative model. The bootstrap script handles this sequential, stateful setup better.

In a more mature setup, I'd use Terraform for the Helm installs and a separate configuration management tool (or Vault's Terraform provider) for the Vault configuration.

---

## Cost & Trade-offs

**Q: How do you optimize costs?**

A: Several layers. gp3 EBS volumes instead of gp2 — 20% cheaper with better baseline performance. NAT gateway disabled in dev — saves $32/month. Green deployment at 0 replicas when inactive — no wasted compute. ECR lifecycle policies keep only 3 images. S3 native locking removed the DynamoDB table. t3.small in dev, t3.large only in prod.

The biggest cost optimization is tearing down dev after testing. The bootstrap script makes reprovisioning fast enough that we don't need to keep dev running 24/7.

---

**Q: What would you do differently if starting over?**

A: Five things. Start with kube-prometheus-stack from day one instead of building manual Prometheus manifests. Use Karpenter instead of Cluster Autoscaler for faster, smarter scaling. Implement Vault auto-unseal with AWS KMS from the start. Use Terraform's Helm provider for ArgoCD and Vault installs. And consider separating infrastructure and application repos earlier.

---

## Failure Scenarios

**Q: What happens if terraform destroy fails?**

A: Usually because Kubernetes created AWS resources outside Terraform — LoadBalancers create ELBs and security groups, PVCs create EBS volumes. These block VPC/subnet deletion. The teardown script handles this by deleting K8s services, Helm releases, and PVCs before Terraform runs. If it still fails, we manually delete orphaned security groups and ENIs.

This is a real production problem. The long-term fix is using the AWS Load Balancer Controller which tags resources for proper cleanup, or managing Helm releases through Terraform.

---

**Q: How do you handle a bad deployment?**

A: Blue-green rollback. The previous version's pods are still running on the inactive slot. Change the service selector back to the previous slot in Git, push, ArgoCD syncs within 60 seconds, traffic switches instantly. No redeployment, no waiting for new pods.

If both slots are compromised, we can roll back the Git commit and ArgoCD will revert to the previous state.

---

**Q: What's your disaster recovery plan?**

A: Everything is in Git — infrastructure code, Kubernetes manifests, CI/CD pipelines. The bootstrap script can recreate the entire platform from scratch in under 30 minutes. Terraform state is in S3 with versioning. Vault data is on persistent EBS volumes with gp3 storage.

The gap is Vault — if the EBS volume is lost, secrets are gone. For production, I'd add Vault snapshots to S3 and HA with Raft storage across multiple nodes.

# VoicePay Platform — Deployment Runbook

This runbook covers the complete deployment lifecycle for the VoicePay platform on AWS EKS.

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Helm installed
- GitHub repository access with secrets configured:
  - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`
  - `AWS_ACCOUNT_ID`, `ECR_REGISTRY`
  - `TF_GITHUB_OIDC_PROVIDER_ARN`, `EKS_PUBLIC_CIDRS`

## 1. Provision Infrastructure

Infrastructure is provisioned via Terraform through GitHub Actions.

**Steps:**
1. Go to GitHub → Actions → Terraform → Run workflow
2. Select branch: `dev`
3. Select action: `apply`
4. Wait for completion (~10-15 minutes)

**What gets created:**
- VPC with public subnets
- IAM roles (EKS cluster, node, CICD, Terraform)
- EKS cluster with managed node group (3x t3.small)
- ECR repositories (voicepay-auth, voicepay-payment, voicepay-notification)
- EBS CSI driver with IRSA role
- Cluster Autoscaler IRSA role

**Expected output:**
```
Apply complete! Resources: X added, 0 changed, 0 destroyed.
```

**After Terraform completes:**
- CI workflow is automatically triggered to push Docker images to ECR
- Wait for CI to complete before running bootstrap

## 2. Bootstrap Platform

The bootstrap script installs and configures all platform components.

**Steps:**
```bash
./scripts/bootstrap.sh voicepay-dev us-east-1
```

**What the script does:**

| Step | Component | Action |
|------|-----------|--------|
| 1/8 | EKS | Connects to cluster, verifies nodes |
| 2/8 | Storage | Applies gp3 StorageClass |
| 3/8 | ArgoCD | Installs ArgoCD, sets 60s sync interval |
| 4/8 | Vault | Installs via Helm |
| 5/8 | Vault Config | Init, unseal, secrets, K8s auth, policies, audit |
| 6/8 | Autoscaler | Deploys Cluster Autoscaler |
| 7/8 | App of Apps | Deploys ArgoCD parent app |
| 8/8 | Summary | Outputs credentials and access instructions |

**Expected output:**
```
[8/8] Bootstrap complete!

=== Platform Summary ===
ArgoCD UI:    kubectl port-forward svc/argocd-server -n argocd 8080:443
ArgoCD Pass:  <generated>
Grafana:      kubectl port-forward svc/grafana -n monitoring 3000:3000
Vault UI:     kubectl port-forward svc/vault -n vault 8200:8200

=== Vault Credentials (SAVE THESE) ===
Unseal Key:   <generated>
Admin Token:  <generated>
```

**IMPORTANT:** Save the Vault unseal key and admin token. They are needed for re-runs and recovery.

## 3. Verify Deployment

After bootstrap completes, verify all components:

```bash
# Nodes
kubectl get nodes
# Expected: 3+ nodes in Ready state

# ArgoCD applications
kubectl get applications -n argocd
# Expected: platform, auth, monitoring, logging — all Synced & Healthy

# Deployments
kubectl get deployments -n default
# Expected: voicepay-auth-blue (2/2), voicepay-auth-green (0/0)

# All pods
kubectl get pods --all-namespaces | grep -v kube-system

# Auth service
kubectl get svc voicepay-auth -n default
# Expected: LoadBalancer with EXTERNAL-IP

# Health check
curl http://<EXTERNAL-IP>/health/
# Expected: {"status": "ok"}

# Vault secrets
kubectl exec <auth-pod> -c voicepay-auth -- cat /vault/secrets/config
# Expected: JSON with django_secret_key and db_password
```

## 4. Accessing Platform Components

All internal tools are accessed via port-forward:

| Component | Command | URL |
|-----------|---------|-----|
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 |
| Grafana | `kubectl port-forward svc/kube-prometheus-grafana -n monitoring 3000:80` | http://localhost:3000 |
| Prometheus | `kubectl port-forward svc/kube-prometheus-kube-prome-prometheus -n monitoring 9090:9090` | http://localhost:9090 |
| Vault | `kubectl port-forward svc/vault -n vault 8200:8200` | http://localhost:8200 |

**Credentials:**
- ArgoCD: admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- Grafana: admin / admin
- Vault: use admin token from bootstrap output

## 5. ArgoCD Usage

ArgoCD manages all workload deployments via Git.

**How it works:**
- ArgoCD watches the `dev` branch
- App of Apps (`infra/kubernetes/base/argocd/app-of-apps.yml`) deploys child apps
- Child apps are in `infra/kubernetes/base/argocd/apps/`
- Each child app points to a manifest directory (auth, monitoring, logging)
- Changes pushed to Git are auto-synced within 60 seconds

**Adding a new application:**
1. Create manifests in `infra/kubernetes/base/<app-name>/`
2. Create an ArgoCD Application in `infra/kubernetes/base/argocd/apps/application-<app-name>.yml`
3. Push to `dev` — ArgoCD picks it up automatically

**Force sync:**
```bash
kubectl patch application <app-name> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

## 6. Vault — Secrets Management

Vault manages all application secrets.

**How secrets are injected:**
- Pods are annotated with Vault injection annotations
- Vault Agent Injector adds a sidecar container
- Sidecar authenticates via Kubernetes service account
- Secrets are written to `/vault/secrets/config` as JSON
- Application reads the file at startup

**Adding secrets:**
```bash
kubectl exec -n vault vault-0 -- vault kv put secret/voicepay-auth \
  django_secret_key=<value> \
  db_password=<value>
```

**Adding a new service to Vault:**
1. Create a policy in `infra/kubernetes/base/vault/policies/<service>.hcl`
2. Apply the policy:
   ```bash
   kubectl cp <policy-file> vault/vault-0:/tmp/<service>.hcl
   kubectl exec -n vault vault-0 -- vault policy write <service> /tmp/<service>.hcl
   ```
3. Create a Kubernetes auth role:
   ```bash
   kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/<service> \
     bound_service_account_names=<service> \
     bound_service_account_namespaces=default \
     policies=<service> \
     ttl=1h
   ```

**If Vault is sealed after pod restart:**
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>
```

## 7. Blue-Green Deployments

The auth service uses blue-green deployments for zero-downtime releases.

**Current state:**
- Blue: active (2 replicas, receiving traffic)
- Green: inactive (0 replicas, standby)

**Deploy a new version:**
1. Update `deployment-green.yml` — set `replicas: 2` and new image tag
2. Push to Git → ArgoCD deploys green pods
3. Verify: `kubectl get pods -l slot=green`
4. Switch `service.yml` selector from `slot: blue` to `slot: green`
5. Push to Git → traffic switches instantly
6. Scale down blue: set `replicas: 0` in `deployment-blue.yml`

**Rollback:**
Change service selector back to the previous slot. Push to Git. Instant.

## 8. Teardown

Always run the teardown script before Terraform destroy:

```bash
# 1. Clean up Kubernetes resources
./scripts/teardown.sh voicepay-dev us-east-1

# 2. Destroy infrastructure
# GitHub → Actions → Terraform → Run workflow → dev → destroy
```

**Why teardown first?**
Kubernetes creates AWS resources outside Terraform (ELBs, security groups, EBS volumes). If not cleaned up first, `terraform destroy` fails with dependency violations.

## 9. Troubleshooting

### Pods stuck in Pending
**Cause:** Node capacity — t3.small has an 11 pod limit per node.
**Fix:** Scale node group or wait for Cluster Autoscaler:
```bash
aws eks update-nodegroup-config --cluster-name voicepay-dev \
  --nodegroup-name voicepay-dev-nodes \
  --scaling-config desiredSize=4,minSize=2,maxSize=5 \
  --region us-east-1
```

### ImagePullBackOff
**Cause:** ECR image doesn't exist (repo was recreated by Terraform).
**Fix:** Re-run CI to push the image: GitHub → Actions → CI → Re-run all jobs.

### ArgoCD apps stuck in Unknown
**Cause:** argocd-cm configmap was replaced instead of patched.
**Fix:**
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"timeout.reconciliation":"60s"}}'
kubectl rollout restart statefulset argocd-application-controller -n argocd
```

### Vault sealed after pod restart
**Cause:** Vault uses Shamir unseal — requires manual unseal after restart.
**Fix:**
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>
```

### Terraform destroy fails with DependencyViolation
**Cause:** Kubernetes-created AWS resources (ELBs, security groups) still exist.
**Fix:** Run teardown script first, then retry destroy:
```bash
./scripts/teardown.sh voicepay-dev us-east-1
```
If still failing, manually delete orphaned resources:
```bash
# Find and delete orphaned ELBs
aws elb describe-load-balancers --region us-east-1
aws elb delete-load-balancer --load-balancer-name <name> --region us-east-1

# Find and delete orphaned security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>" --region us-east-1
aws ec2 delete-security-group --group-id <sg-id> --region us-east-1
```

### EBS CSI driver crash looping
**Cause:** Missing IRSA role for EBS CSI driver.
**Fix:** Ensure Terraform has been applied with the EBS CSI module. The IRSA role is created automatically.

### Grafana not loading via port-forward
**Cause:** Port-forward latency to remote EKS cluster.
**Fix:** Use terminal commands to verify metrics/logs instead:
```bash
# Prometheus targets
kubectl exec -n monitoring prometheus-kube-prometheus-kube-prome-prometheus-0 \
  -c prometheus -- wget -qO- "http://localhost:9090/api/v1/targets" | python3 -m json.tool | head -20

# Loki logs
kubectl exec -n logging deploy/loki -- wget -qO- \
  "http://localhost:3100/loki/api/v1/query?query={job=%22fluent-bit%22}&limit=2" | python3 -m json.tool | head -20
```

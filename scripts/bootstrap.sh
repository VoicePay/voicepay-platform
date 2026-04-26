#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-voicepay-dev}"
REGION="${2:-us-east-1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_VALUES="$REPO_ROOT/infra/kubernetes/base/vault/values.yml"
VAULT_POLICY="$REPO_ROOT/infra/kubernetes/base/vault/policies/voicepay-auth.hcl"
APP_OF_APPS="$REPO_ROOT/infra/kubernetes/base/argocd/app-of-apps.yml"
ARGOCD_CM_PATCH="$REPO_ROOT/infra/kubernetes/base/argocd/argocd-cm-patch.yml"
STORAGE_CLASS="$REPO_ROOT/infra/kubernetes/base/storage/gp3-storageclass.yml"

echo "=== VoicePay Platform Bootstrap ==="
echo "Cluster: $CLUSTER_NAME | Region: $REGION"

# Step 1: Connect to EKS
echo "[1/7] Connecting to EKS..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl get nodes

# Step 2: Apply gp3 StorageClass
echo "[2/7] Applying gp3 StorageClass..."
kubectl apply -f "$STORAGE_CLASS"

# Step 3: Install ArgoCD
echo "[3/7] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
echo "Waiting for ArgoCD pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=argocd -n argocd --timeout=180s
kubectl apply -f "$ARGOCD_CM_PATCH"

# Step 4: Install Vault
echo "[4/7] Installing Vault..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
helm upgrade --install vault hashicorp/vault -n vault -f "$VAULT_VALUES"
echo "Waiting for Vault pod..."
sleep 30
kubectl wait --for=condition=ready pod/vault-agent-injector -l app.kubernetes.io/name=vault-agent-injector -n vault --timeout=120s || true

# Step 5: Configure Vault
echo "[5/7] Configuring Vault..."
echo "Waiting for vault-0 to be running..."
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 -n vault --timeout=120s

INIT_OUTPUT=$(kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json 2>/dev/null || echo "ALREADY_INIT")

if [ "$INIT_OUTPUT" = "ALREADY_INIT" ]; then
  echo "Vault already initialized. Provide unseal key manually."
  echo "Run: kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>"
  exit 1
fi

UNSEAL_KEY=$(echo "$INIT_OUTPUT" | grep -o '"unseal_keys_b64":\[\"[^"]*\"' | cut -d'"' -f4)
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4)

echo "Unsealing Vault..."
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"

echo "Configuring Vault..."
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN" > /dev/null
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
kubectl exec -n vault vault-0 -- vault kv put secret/voicepay-auth \
  django_secret_key=voicepay-secret-key-change-me \
  db_password=change-me
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Apply policy
kubectl cp "$VAULT_POLICY" vault/vault-0:/tmp/voicepay-auth.hcl
kubectl exec -n vault vault-0 -- vault policy write voicepay-auth /tmp/voicepay-auth.hcl

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/voicepay-auth \
  bound_service_account_names=voicepay-auth \
  bound_service_account_namespaces=default \
  policies=voicepay-auth \
  ttl=1h

# Enable audit logging
kubectl exec -n vault vault-0 -- vault audit enable file file_path=stdout

# Create orphan admin token and revoke root
ADMIN_TOKEN=$(kubectl exec -n vault vault-0 -- vault token create -policy=admin -orphan -format=json 2>/dev/null | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -n "$ADMIN_TOKEN" ]; then
  # Create admin policy first
  kubectl exec -n vault vault-0 -- sh -c 'vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF'
  ADMIN_TOKEN=$(kubectl exec -n vault vault-0 -- vault token create -policy=admin -orphan -format=json | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)
  kubectl exec -n vault vault-0 -- vault token revoke "$ROOT_TOKEN"
  echo "Root token revoked."
fi

# Step 6: Deploy App of Apps
echo "[6/7] Deploying App of Apps..."
kubectl apply -f "$APP_OF_APPS"

# Step 7: Output summary
echo "[7/7] Bootstrap complete!"
echo ""
echo "=== Platform Summary ==="
echo "ArgoCD UI:    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "ArgoCD Pass:  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "Grafana:      kubectl port-forward svc/grafana -n monitoring 3000:3000"
echo "Vault UI:     kubectl port-forward svc/vault -n vault 8200:8200"
echo ""
echo "=== Vault Credentials (SAVE THESE) ==="
echo "Unseal Key:   $UNSEAL_KEY"
[ -n "$ADMIN_TOKEN" ] && echo "Admin Token:  $ADMIN_TOKEN"
echo ""
echo "=== ArgoCD Apps ==="
kubectl get applications -n argocd 2>/dev/null || echo "Apps syncing..."

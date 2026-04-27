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
echo ""
echo "[1/7] Connecting to EKS..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl get nodes

# Step 2: Apply gp3 StorageClass
echo ""
echo "[2/7] Applying gp3 StorageClass..."
kubectl apply -f "$STORAGE_CLASS"

# Step 3: Install ArgoCD
echo ""
echo "[3/7] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
echo "Waiting for ArgoCD pods (60s)..."
sleep 60
kubectl get pods -n argocd
kubectl apply -f "$ARGOCD_CM_PATCH" --server-side

# Step 4: Install Vault
echo ""
echo "[4/7] Installing Vault..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
helm upgrade --install vault hashicorp/vault -n vault -f "$VAULT_VALUES"
echo "Waiting for Vault pod (45s)..."
sleep 45

# Step 5: Configure Vault
echo ""
echo "[5/7] Configuring Vault..."

# Wait for vault-0 to be running
for i in $(seq 1 12); do
  STATUS=$(kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "$STATUS" = "Running" ]; then
    break
  fi
  echo "  vault-0 status: $STATUS (attempt $i/12)"
  sleep 10
done

# Init Vault
INIT_OUTPUT=$(kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json)

UNSEAL_KEY=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

echo "Unsealing Vault..."
kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
sleep 5

echo "Logging in..."
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN" > /dev/null

echo "Enabling secrets engine..."
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

echo "Storing secrets..."
kubectl exec -n vault vault-0 -- vault kv put secret/voicepay-auth \
  django_secret_key=voicepay-secret-key-change-me \
  db_password=change-me

echo "Enabling Kubernetes auth..."
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

echo "Creating policies..."
kubectl cp "$VAULT_POLICY" vault/vault-0:/tmp/voicepay-auth.hcl
kubectl exec -n vault vault-0 -- vault policy write voicepay-auth /tmp/voicepay-auth.hcl

kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/voicepay-auth \
  bound_service_account_names=voicepay-auth \
  bound_service_account_namespaces=default \
  policies=voicepay-auth \
  ttl=1h 2>/dev/null

echo "Enabling audit logging..."
kubectl exec -n vault vault-0 -- vault audit enable file file_path=stdout

echo "Creating admin policy and token..."
kubectl exec -n vault vault-0 -- sh -c 'vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF'

ADMIN_TOKEN=$(kubectl exec -n vault vault-0 -- vault token create -policy=admin -orphan -format=json | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

echo "Revoking root token..."
kubectl exec -n vault vault-0 -- vault token revoke "$ROOT_TOKEN"

# Step 6: Deploy App of Apps
echo ""
echo "[6/7] Deploying App of Apps..."
kubectl apply -f "$APP_OF_APPS"
echo "Waiting for apps to sync (60s)..."
sleep 60

# Step 7: Output summary
echo ""
echo "[7/7] Bootstrap complete!"
echo ""
echo "=== Platform Summary ==="
echo "ArgoCD UI:    kubectl port-forward svc/argocd-server -n argocd 8080:443"
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Pass:  $ARGOCD_PASS"
echo "Grafana:      kubectl port-forward svc/grafana -n monitoring 3000:3000"
echo "Vault UI:     kubectl port-forward svc/vault -n vault 8200:8200"
echo ""
echo "=== Vault Credentials (SAVE THESE) ==="
echo "Unseal Key:   $UNSEAL_KEY"
echo "Admin Token:  $ADMIN_TOKEN"
echo ""
echo "=== ArgoCD Apps ==="
kubectl get applications -n argocd 2>/dev/null || echo "Apps syncing..."
echo ""
echo "=== All Pods ==="
kubectl get pods --all-namespaces | grep -v kube-system

#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-voicepay-dev}"
REGION="${2:-us-east-1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_VALUES="$REPO_ROOT/infra/kubernetes/base/vault/values.yml"
VAULT_POLICY="$REPO_ROOT/infra/kubernetes/base/vault/policies/voicepay-auth.hcl"
APP_OF_APPS="$REPO_ROOT/infra/kubernetes/base/argocd/app-of-apps.yml"
STORAGE_CLASS="$REPO_ROOT/infra/kubernetes/base/storage/gp3-storageclass.yml"
VAULT_CREDS_FILE="/tmp/voicepay-vault-creds-${CLUSTER_NAME}.json"

UNSEAL_KEY=""
ROOT_TOKEN=""
ADMIN_TOKEN=""

echo "=== VoicePay Platform Bootstrap ==="
echo "Cluster: $CLUSTER_NAME | Region: $REGION"

# Step 1: Connect to EKS
echo ""
echo "[1/8] Connecting to EKS..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl get nodes

# Step 2: Apply gp3 StorageClass
echo ""
echo "[2/8] Applying gp3 StorageClass..."
kubectl apply -f "$STORAGE_CLASS"

# Step 3: Install ArgoCD
echo ""
echo "[3/8] Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
echo "Waiting for ArgoCD pods (60s)..."
sleep 60
kubectl get pods -n argocd
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"timeout.reconciliation":"60s"}}'

# Step 4: Install Vault
echo ""
echo "[4/8] Installing Vault..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update
if helm status vault -n vault > /dev/null 2>&1; then
  echo "Vault already installed, skipping Helm install."
else
  helm install vault hashicorp/vault -n vault -f "$VAULT_VALUES"
  echo "Waiting for Vault pod (45s)..."
  sleep 45
fi

# Step 5: Configure Vault
echo ""
echo "[5/8] Configuring Vault..."

# Wait for vault-0 to be running
for i in $(seq 1 12); do
  STATUS=$(kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "$STATUS" = "Running" ]; then
    break
  fi
  echo "  vault-0 status: $STATUS (attempt $i/12)"
  sleep 10
done

# Check Vault state
VAULT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null || echo '{"initialized":false,"sealed":true}')
IS_INIT=$(echo "$VAULT_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('initialized', False))")
IS_SEALED=$(echo "$VAULT_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sealed', True))")

# Load saved credentials if they exist
if [ -f "$VAULT_CREDS_FILE" ]; then
  UNSEAL_KEY=$(python3 -c "import json; print(json.load(open('$VAULT_CREDS_FILE')).get('unseal_key',''))")
  ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('$VAULT_CREDS_FILE')).get('root_token',''))")
  ADMIN_TOKEN=$(python3 -c "import json; print(json.load(open('$VAULT_CREDS_FILE')).get('admin_token',''))")
fi

if [ "$IS_INIT" = "False" ]; then
  echo "Initializing Vault..."
  INIT_OUTPUT=$(kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json)
  UNSEAL_KEY=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")
  echo "{\"unseal_key\":\"$UNSEAL_KEY\",\"root_token\":\"$ROOT_TOKEN\"}" > "$VAULT_CREDS_FILE"
  echo "Vault credentials saved to $VAULT_CREDS_FILE"

  echo "Unsealing Vault..."
  kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
  sleep 5

  echo "Logging in with root token..."
  kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN" > /dev/null
else
  echo "Vault already initialized."

  # Unseal if needed
  if [ "$IS_SEALED" = "True" ]; then
    if [ -n "$UNSEAL_KEY" ]; then
      echo "Unsealing Vault..."
      kubectl exec -n vault vault-0 -- vault operator unseal "$UNSEAL_KEY"
      sleep 5
    else
      echo "ERROR: Vault is sealed and no unseal key found."
      echo "Run: kubectl exec -n vault vault-0 -- vault operator unseal <KEY>"
      exit 1
    fi
  else
    echo "Vault already unsealed."
  fi

  # Login with whatever token we have
  LOGGED_IN=false
  if [ -n "$ADMIN_TOKEN" ]; then
    if kubectl exec -n vault vault-0 -- vault login "$ADMIN_TOKEN" > /dev/null 2>&1; then
      LOGGED_IN=true
      echo "Logged in with admin token."
    fi
  fi
  if [ "$LOGGED_IN" = "false" ] && [ -n "$ROOT_TOKEN" ]; then
    if kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN" > /dev/null 2>&1; then
      LOGGED_IN=true
      echo "Logged in with root token."
    fi
  fi
  if [ "$LOGGED_IN" = "false" ]; then
    echo "Vault already configured, skipping Vault config steps."
    echo "  (No valid token available — using existing configuration)"
    UNSEAL_KEY="${UNSEAL_KEY:-(see previous bootstrap output)}"
    ADMIN_TOKEN="${ADMIN_TOKEN:-(see previous bootstrap output)}"
    # Skip to Step 6
    SKIP_VAULT_CONFIG=true
  fi
fi

if [ "${SKIP_VAULT_CONFIG:-false}" = "false" ]; then
  echo "Enabling secrets engine..."
  kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2 2>/dev/null || echo "  Already enabled."

  echo "Storing secrets..."
  kubectl exec -n vault vault-0 -- vault kv put secret/voicepay-auth \
    django_secret_key=voicepay-secret-key-change-me \
    db_password=change-me

  echo "Enabling Kubernetes auth..."
  kubectl exec -n vault vault-0 -- vault auth enable kubernetes 2>/dev/null || echo "  Already enabled."
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
  kubectl exec -n vault vault-0 -- vault audit enable file file_path=stdout 2>/dev/null || echo "  Already enabled."

  echo "Creating admin policy and token..."
  kubectl exec -n vault vault-0 -- sh -c 'vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF'

  NEW_ADMIN=$(kubectl exec -n vault vault-0 -- vault token create -policy=admin -orphan -format=json 2>/dev/null || echo "")
  if [ -n "$NEW_ADMIN" ]; then
    ADMIN_TOKEN=$(echo "$NEW_ADMIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")
    python3 -c "
import json, os
creds = json.load(open('$VAULT_CREDS_FILE')) if os.path.exists('$VAULT_CREDS_FILE') else {}
creds['admin_token'] = '$ADMIN_TOKEN'
json.dump(creds, open('$VAULT_CREDS_FILE', 'w'))
"
    if [ -n "$ROOT_TOKEN" ]; then
      echo "Revoking root token..."
      kubectl exec -n vault vault-0 -- vault token revoke "$ROOT_TOKEN" 2>/dev/null || true
      python3 -c "
import json
creds = json.load(open('$VAULT_CREDS_FILE'))
creds.pop('root_token', None)
json.dump(creds, open('$VAULT_CREDS_FILE', 'w'))
"
    fi
  fi
fi

# Step 6: Deploy Cluster Autoscaler
echo ""
echo "[6/8] Deploying Cluster Autoscaler..."
AUTOSCALER_ROLE_ARN=$(aws iam get-role --role-name voicepay-${CLUSTER_NAME##*-}-cluster-autoscaler-role --query 'Role.Arn' --output text 2>/dev/null || echo "")
if [ -n "$AUTOSCALER_ROLE_ARN" ]; then
  sed -e "s|REPLACE_WITH_ROLE_ARN|$AUTOSCALER_ROLE_ARN|" \
      -e "s|REPLACE_WITH_CLUSTER_NAME|$CLUSTER_NAME|" \
      "$REPO_ROOT/infra/kubernetes/base/cluster-autoscaler/deployment.yml" | kubectl apply -f -
  echo "Cluster Autoscaler deployed."
else
  echo "Autoscaler IAM role not found, skipping. Run terraform apply first."
fi

# Step 7: Deploy App of Apps
echo ""
echo "[7/8] Deploying App of Apps..."
kubectl apply -f "$APP_OF_APPS"
echo "Waiting for apps to sync (60s)..."
sleep 60

# Step 8: Output summary
echo ""
echo "[8/8] Bootstrap complete!"
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

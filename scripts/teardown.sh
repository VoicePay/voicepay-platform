#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-voicepay-dev}"
REGION="${2:-us-east-1}"

echo "=== VoicePay Platform Teardown ==="
echo "Cluster: $CLUSTER_NAME | Region: $REGION"

# Connect to EKS
echo ""
echo "[1/6] Connecting to EKS..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || {
  echo "Cluster not found or already deleted. Nothing to tear down."
  exit 0
}

# Delete LoadBalancer services (removes ELBs, security groups, ENIs)
echo ""
echo "[2/6] Deleting LoadBalancer services..."
kubectl delete svc --all-namespaces -l type=LoadBalancer 2>/dev/null || true
kubectl delete svc voicepay-auth -n default 2>/dev/null || true

# Delete ArgoCD applications (removes all workloads)
echo ""
echo "[3/6] Deleting ArgoCD applications..."
kubectl delete application --all -n argocd 2>/dev/null || true

# Uninstall Helm releases (removes PVCs/EBS volumes)
echo ""
echo "[4/6] Uninstalling Helm releases..."
helm uninstall vault -n vault 2>/dev/null || true
helm uninstall kube-prometheus -n monitoring 2>/dev/null || true

# Delete PVCs (releases EBS volumes)
echo ""
echo "[5/6] Deleting PVCs and namespaces..."
kubectl delete pvc --all --all-namespaces 2>/dev/null || true
kubectl delete namespace vault argocd monitoring logging 2>/dev/null || true

# Wait for AWS to clean up
echo ""
echo "[6/6] Waiting 60s for AWS resource cleanup..."
sleep 60

# Verify ELBs are gone
ELBS=$(aws elb describe-load-balancers --region "$REGION" --query "LoadBalancerDescriptions[*].LoadBalancerName" --output text 2>/dev/null || echo "")
if [ -n "$ELBS" ]; then
  echo "WARNING: Orphaned ELBs found, deleting..."
  for ELB in $ELBS; do
    aws elb delete-load-balancer --load-balancer-name "$ELB" --region "$REGION"
    echo "  Deleted ELB: $ELB"
  done
  sleep 30
fi

echo ""
echo "=== Teardown complete ==="
echo "Now run: terraform destroy (via GitHub Actions)"

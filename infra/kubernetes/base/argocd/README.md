# ArgoCD Setup

ArgoCD provides GitOps-based continuous delivery for the VoicePay platform.

## Prerequisites

- Kubernetes cluster running (Docker Desktop, kind, or EKS)
- `kubectl` configured and pointing to the target cluster

## Installation

```bash
# Create namespace
kubectl apply -f namespace.yml

# Install ArgoCD from official manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Verify all pods are running
kubectl get pods -n argocd
```

Expected pods:
- `argocd-application-controller`
- `argocd-applicationset-controller`
- `argocd-dex-server`
- `argocd-notifications-controller`
- `argocd-redis`
- `argocd-repo-server`
- `argocd-server`

## Accessing the UI

```bash
# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Retrieve the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Open `https://localhost:8080` and log in with username `admin` and the retrieved password.

## Architecture

ArgoCD watches this Git repository and automatically syncs Kubernetes manifests from `infra/kubernetes/` to the cluster, ensuring the deployed state always matches the declared state in Git.

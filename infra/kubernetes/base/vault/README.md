# HashiCorp Vault Setup

Vault provides centralized secrets management for the VoicePay platform.

## Prerequisites

- Kubernetes cluster running
- Helm installed

## Installation

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
kubectl create namespace vault
helm install vault hashicorp/vault -n vault -f values.yml
```

## Initialize & Unseal

```bash
kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>
```

Store the unseal key and root token securely. Never commit them to Git.

## Enable Secrets Engine

```bash
kubectl exec -n vault vault-0 -- vault login <ROOT_TOKEN>
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2
```

## Enable Kubernetes Auth

```bash
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
```

## Create Policy & Role

```bash
kubectl exec -n vault vault-0 -- vault policy write voicepay-auth /vault/policies/voicepay-auth.hcl
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/voicepay-auth \
  bound_service_account_names=voicepay-auth \
  bound_service_account_namespaces=default \
  policies=voicepay-auth \
  ttl=1h
```

## Audit Logging

```bash
kubectl exec -n vault vault-0 -- vault audit enable file file_path=stdout
```

Audit logs are sent to stdout, collected by Fluent Bit, and queryable in Grafana via Loki.

## Root Token Revocation

After initial setup, create an admin token and revoke the root token:

```bash
kubectl exec -n vault vault-0 -- vault policy write admin policies/admin.hcl
kubectl exec -n vault vault-0 -- vault token create -policy=admin
kubectl exec -n vault vault-0 -- vault token revoke <ROOT_TOKEN>
```

Store the admin token securely. Never commit tokens to Git.

## Architecture

- Vault runs in standalone mode with file storage
- Kubernetes auth allows pods to authenticate using service account tokens
- Policies enforce least-privilege access to secrets
- Audit logging enabled — all secret access logged to stdout → Fluent Bit → Loki
- Root token revoked after setup — admin token used for operations
- No secrets stored in Git — all managed through Vault API

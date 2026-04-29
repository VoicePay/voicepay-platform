# voicepay-platform
VoicePay is a cloud-native fintech platform that enables secure, voice-driven financial transactions. This repository follows a monorepo architecture, combining multiple microservices and infrastructure code in a single, organized codebase.

## Repository Structure

```
voicepay-platform/
├── .github/
│   └── workflows/       # CI/CD GitHub Actions workflows
├── scripts/             # Automation scripts
│   └── bootstrap.sh     # One-command platform bootstrap
├── services/            # Application microservices
│   ├── auth/            # Authentication service
│   ├── notification/    # Notification service
│   └── payment/         # Payment service
└── infra/               # Infrastructure and deployment code
    ├── kubernetes/      # Kubernetes manifests
    │   ├── base/
    │   └── overlays/
    ├── monitoring/      # Observability configs
    │   └── prometheus/  # Prometheus config and alerting rules
    └── terraform/       # Terraform IaC
        ├── envs/
        └── modules/
```

## CI

GitHub Actions runs on every push and pull request to `dev` and `prod`. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

The pipeline includes the following stages:

- `build` — validates the pipeline runs successfully
- `docker-build` — builds the Docker image for `services/auth`
- `test` — runs pytest against `services/auth`
- `lint` — checks code formatting with `black` and `flake8`
- `yaml-lint` — validates all `.yml` / `.yaml` files with `yamllint`

## Running Locally with Docker

Make sure Docker Desktop is running, then:

```bash
cd services/auth
cp .env.example .env  # update values as needed
docker-compose up --build
```

The app will be available at `http://localhost:8000`.
Prometheus UI will be available at `http://localhost:9090`.
Grafana will be available at `http://localhost:3000` (login: `admin` / `admin`).

### Environment Variables

Create a `.env` file in `services/auth/` based on `.env.example`:

| Variable | Description |
|---|---|
| `DEBUG` | Django debug mode (`1` for local dev) |
| `SECRET_KEY` | Django secret key |
| `DJANGO_SETTINGS_MODULE` | Settings module path |
| `DATABASE_URL` | PostgreSQL connection string |
| `ALLOWED_HOSTS` | Comma-separated list of allowed hosts |
| `NEW_RELIC_LICENSE_KEY` | New Relic license key |
| `NEW_RELIC_APP_NAME` | New Relic application name |
| `NEW_RELIC_HOST` | New Relic collector endpoint |

## Monitoring

Prometheus is configured to scrape metrics from all services. The auth service exposes a `/metrics` endpoint via `django-prometheus`.

Alerting rules are defined in `infra/monitoring/prometheus/alerts.yml`:

- `ServiceDown` (critical) — fires when a target is down for 5 minutes
- `HighRequestLatency` (warning) — fires when average latency exceeds 1s for 5 minutes
- `HighErrorRate` (warning) — fires when 5xx error rate exceeds 5% for 5 minutes

## Logging

All services output structured JSON logs to stdout. Each log entry includes:

- `timestamp` — when the event occurred
- `level` — severity (INFO, WARNING, ERROR)
- `message` — description of the event
- `service` — name of the service emitting the log (e.g. `auth`)
- `trace_id` — unique request identifier for end-to-end tracing

Logging is configured centrally in `settings.py` and is ready for integration with observability tools like Grafana, Prometheus, and New Relic.

**Request Tracing:**

Every request is assigned a unique trace ID (UUID). The trace ID is:
- Generated automatically or accepted via `X-Trace-ID` request header
- Injected into all log entries for the request lifecycle
- Returned in the `X-Trace-ID` response header for client correlation
- Thread-safe using Python `ContextVar`

**Example log output:**

```json
{"timestamp": "2026-01-01 00:00:00,000", "level": "INFO", "message": "Voice login successful", "service": "auth", "trace_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "Voice authentication failed", "service": "auth", "trace_id": "f9e8d7c6-b5a4-3210-fedc-ba9876543210"}
```

## Centralized Logging

Logs are collected from all Kubernetes workloads using the Fluent Bit → Loki → Grafana stack:

- **Fluent Bit** — DaemonSet log collector, enriches logs with Kubernetes metadata
- **Loki** — log aggregation backend with 72h retention and compaction
- **Grafana** — query and explore logs via Loki datasource

Manifests are in `infra/kubernetes/base/logging/` and managed via ArgoCD.

## GitOps (ArgoCD)

ArgoCD manages workload deployments via Git as the single source of truth:

- Auto-sync enabled with pruning and self-healing
- Monitors `dev` branch for changes
- Deploys manifests from `infra/kubernetes/base/`

Setup instructions: [`infra/kubernetes/base/argocd/README.md`](infra/kubernetes/base/argocd/README.md)

## Secrets Management (Vault)

HashiCorp Vault provides centralized secrets management:

- Deployed via Helm in standalone mode with UI enabled
- Kubernetes auth enabled — pods authenticate using service account tokens
- Vault Agent sidecar automatically injects secrets into pods at runtime
- Least-privilege policies control access per service
- Audit logging enabled — all secret access logged to stdout → Fluent Bit → Loki
- Root token revoked after setup

**How it works:**

Pods are annotated with Vault injection annotations. The Vault Agent Injector webhook automatically adds a sidecar container that authenticates to Vault and writes secrets to `/vault/secrets/config`. The application reads this file at startup — no hardcoded credentials, no env var secrets.

Setup instructions: [`infra/kubernetes/base/vault/README.md`](infra/kubernetes/base/vault/README.md)

## Platform Bootstrap

The full platform can be deployed to EKS with two commands:

```bash
# 1. Provision infrastructure (via GitHub Actions)
# GitHub → Actions → Terraform → Run workflow → dev → apply

# 2. Bootstrap platform components
./scripts/bootstrap.sh voicepay-dev us-east-1
```

The bootstrap script automatically:
- Connects to the EKS cluster
- Applies gp3 StorageClass
- Installs ArgoCD with tuned sync interval (60s)
- Installs and configures Vault (init, unseal, K8s auth, policies, audit logging)
- Deploys App of Apps — which auto-deploys monitoring, logging, and auth service
- Outputs access instructions and credentials

EBS CSI driver and IRSA role are provisioned by Terraform as part of the EKS module.

## Blue-Green Deployments

The auth service uses a blue-green deployment strategy for zero-downtime releases:

- **Blue** — active (2 replicas, receiving traffic)
- **Green** — inactive (0 replicas, standby)

**Deploy a new version:**
1. Update `deployment-green.yml` — set `replicas: 2` and new image tag
2. Push to Git → ArgoCD deploys green pods
3. Verify green is healthy: `kubectl get pods -l slot=green`
4. Switch `service.yml` selector from `slot: blue` to `slot: green`
5. Push to Git → traffic switches instantly
6. Scale down blue: set `replicas: 0` in `deployment-blue.yml`

**Rollback:** Change service selector back to the previous slot. Push to Git. Instant rollback.

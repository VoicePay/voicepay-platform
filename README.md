# voicepay-platform
VoicePay is a cloud-native fintech platform that enables secure, voice-driven financial transactions. This repository follows a monorepo architecture, combining multiple microservices and infrastructure code in a single, organized codebase.

## Repository Structure

```
voicepay-platform/
├── .github/
│   └── workflows/       # CI/CD GitHub Actions workflows
├── services/            # Application microservices
│   ├── auth/            # Authentication service
│   ├── notification/    # Notification service
│   └── payment/         # Payment service
└── infra/               # Infrastructure and deployment code
    ├── kubernetes/      # Kubernetes manifests
    │   ├── base/
    │   └── overlays/
    └── terraform/       # Terraform IaC
        ├── envs/
        └── modules/
```

## CI

GitHub Actions runs on every push and pull request to `dev` and `prod`. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

The pipeline includes the following stages:

- `build` — validates the pipeline runs successfully
- `test` — runs pytest against `services/auth`
- `lint` — checks code formatting with `black` and `flake8`
- `yaml-lint` — validates all `.yml` / `.yaml` files with `yamllint`

## Logging

All services output structured JSON logs to stdout. Each log entry includes:

- `timestamp` — when the event occurred
- `level` — severity (INFO, WARNING, ERROR)
- `message` — description of the event
- `service` — name of the service emitting the log (e.g. `auth`)

Logging is configured centrally in `settings.py` and is ready for integration with observability tools like Grafana, Prometheus, and New Relic.

**Example log output:**

```json
{"timestamp": "2026-01-01 00:00:00,000", "level": "INFO", "message": "Voice login successful", "service": "auth", "email": "alice@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "Voice authentication failed", "service": "auth", "email": "bob@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "Login attempted for non-existent user", "service": "auth", "email": "ghost@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "User registration attempted without voice sample", "service": "auth"}
```

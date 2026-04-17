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

Logging is configured centrally in `settings.py` and is ready for integration with observability tools like Grafana, Prometheus, and New Relic.

**Example log output:**

```json
{"timestamp": "2026-01-01 00:00:00,000", "level": "INFO", "message": "Voice login successful", "service": "auth", "email": "alice@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "Voice authentication failed", "service": "auth", "email": "bob@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "Login attempted for non-existent user", "service": "auth", "email": "ghost@example.com"}
{"timestamp": "2026-01-01 00:00:00,000", "level": "WARNING", "message": "User registration attempted without voice sample", "service": "auth"}
```

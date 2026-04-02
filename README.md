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

GitHub Actions runs on every push and pull request to `main`. See [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

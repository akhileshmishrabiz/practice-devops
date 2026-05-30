# GitHub Actions Workflows

This folder contains GitHub Actions workflow files for CI/CD.

## Setup

To use these workflows, copy them to `.github/workflows/`:

```bash
mkdir -p .github/workflows
cp github-action/*.yml .github/workflows/
```

## Workflows

### ci-pipeline.yml

Runs on pull requests to `main` branch.

**Jobs:**

| Job | Description | Matrix |
|-----|-------------|--------|
| secret-scan | Scans for secrets using Gitleaks | - |
| go-services | Lint + test Go services | product-service, order-service |
| node-services | Lint + test Node.js services | user-service, cart-service |
| python-services | Lint + test Python services | payment-service, notification-service |
| docker-scan | Build & scan images with Trivy | All 6 services |
| ci-summary | Reports overall status | - |

**Features:**

- Matrix strategy for parallel testing
- Trivy vulnerability scanning (CRITICAL, HIGH)
- Gitleaks secret detection
- SARIF upload to GitHub Security tab
- Coverage artifact uploads

## Service Test Commands

### Go Services
```bash
cd apps/services/product-service
go test -v ./...

cd apps/services/order-service
go test -v ./...
```

### Node.js Services
```bash
cd apps/services/user-service
npm install && npm test

cd apps/services/cart-service
npm install && npm test
```

### Python Services
```bash
cd apps/services/payment-service
pip install -r requirements.txt
pytest tests/ -v

cd apps/services/notification-service
pip install -r requirements.txt
pytest tests/ -v
```

tea# E-Commerce Seed Data Job

Kubernetes job to seed product data into the e-commerce microservices via API gateway.

## ECR Image

```
879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed
- kubectl configured to access your cluster

## Steps to Pull from ECR

### 1. Authenticate Docker with ECR

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.us-east-1.amazonaws.com
```

### 2. Pull the Image

```bash
docker pull 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
```

### 3. Create ECR Pull Secret in Kubernetes (for EKS/non-Kind clusters)

```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=879381241087.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-east-1) \
  -n ecommerce
```

### 4. Run the Job

For EKS clusters with ECR access:
```bash
kubectl apply -f seed-job.yaml
```

For Kind clusters (load image locally first):
```bash
docker pull 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
kind load docker-image 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest --name <cluster-name>
kubectl apply -f seed-job.yaml
```

## Building the Image

```bash
# Build
docker build -t ms-ecom-seed:latest .

# Tag for ECR
docker tag ms-ecom-seed:latest 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest

# Push to ECR
docker push 879381241087.dkr.ecr.us-east-1.amazonaws.com/ms-ecom-seed:latest
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_URL` | API Gateway URL | `http://localhost:8080` |

## Seeded Data

The job seeds 15 products across categories:
- Electronics (iPhone, Samsung, MacBook, Sony headphones, iPad)
- Footwear (Nike, Adidas)
- Clothing (Levi's, North Face)
- Accessories (Ray-Ban)
- Gaming (PS5, Nintendo Switch)
- Home & Kitchen (Dyson, Instant Pot, KitchenAid)

## Test Credentials

```
Email: john.doe@example.com
Password: NewPassword123!
```

# Infrastructure as Code

This directory contains Infrastructure as Code (IaC) for deploying the SSE Notification System to various cloud providers.

## Quick Start

### Local Development
```bash
../scripts/setup-local.sh
```

### AWS (CDK)
```bash
cd aws
./deploy.sh deploy
```

### GCP (Terraform)
```bash
cd gcp
export GCP_PROJECT_ID=your-project
./deploy.sh deploy
```

### Azure (Terraform)
```bash
cd azure
./deploy.sh deploy
```

## Directory Structure

```
infra/
├── aws/                    # AWS CDK (TypeScript)
│   ├── bin/
│   │   └── app.ts          # CDK app entry point
│   ├── lib/
│   │   └── sse-notification-stack.ts  # Main stack
│   ├── deploy.sh           # Deployment script
│   ├── package.json
│   ├── tsconfig.json
│   └── cdk.json
│
├── gcp/                    # GCP Terraform
│   ├── main.tf             # Terraform configuration
│   └── deploy.sh           # Deployment script
│
├── azure/                  # Azure Terraform
│   ├── main.tf             # Terraform configuration
│   └── deploy.sh           # Deployment script
│
└── README.md               # This file
```

## Comparison

| Feature | AWS | GCP | Azure |
|---------|-----|-----|-------|
| IaC Tool | CDK (TypeScript) | Terraform | Terraform |
| Compute | ECS Fargate | Cloud Run | Container Apps |
| Redis | ElastiCache | Memorystore | Azure Cache for Redis |
| Load Balancer | ALB | Cloud LB | Built-in Ingress |
| Auto-scaling | Yes | Yes | Yes |
| Est. Cost (3 nodes) | ~$140/mo | ~$160/mo | ~$150/mo |

## Prerequisites

All platforms require:
- Docker installed and running
- Cloud CLI authenticated
- Terraform (GCP/Azure) or Node.js (AWS)

### AWS
```bash
aws configure
npm install -g aws-cdk
```

### GCP
```bash
gcloud auth login
gcloud auth application-default login
brew install terraform  # or equivalent
```

### Azure
```bash
az login
brew install terraform  # or equivalent
```

## Environment Variables

### AWS
| Variable | Description | Default |
|----------|-------------|---------|
| AWS_REGION | Deployment region | us-east-1 |
| ENVIRONMENT | Environment name | production |
| DESIRED_COUNT | Number of ECS tasks | 3 |

### GCP
| Variable | Description | Default |
|----------|-------------|---------|
| GCP_PROJECT_ID | GCP project ID | (required) |
| GCP_REGION | Deployment region | us-central1 |
| MIN_INSTANCES | Min Cloud Run instances | 3 |
| MAX_INSTANCES | Max Cloud Run instances | 100 |

### Azure
| Variable | Description | Default |
|----------|-------------|---------|
| AZURE_RESOURCE_GROUP | Resource group name | sse-notification-rg |
| AZURE_LOCATION | Azure region | eastus |
| MIN_REPLICAS | Min container replicas | 3 |
| MAX_REPLICAS | Max container replicas | 100 |

## Detailed Documentation

- [Local Setup Guide](../docs/LOCAL_SETUP.md)
- [AWS Deployment Guide](../docs/AWS_DEPLOYMENT.md)
- [GCP Deployment Guide](../docs/GCP_DEPLOYMENT.md)
- [Azure Deployment Guide](../docs/AZURE_DEPLOYMENT.md)

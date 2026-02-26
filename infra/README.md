# Infrastructure as Code - Coding to Interface

This infrastructure follows the **"Coding to Interface"** pattern, where the same configuration works across all cloud providers (AWS, GCP, Azure) with zero code changes.

## Architecture

```
infra/
├── config/                    # Shared configuration (the "Interface")
│   ├── common.tfvars          # Cloud-agnostic infrastructure config
│   └── monitoring.tfvars      # Cloud-agnostic monitoring config
├── modules/                   # Reusable modules
│   ├── monitoring/            # Monitoring interface + implementations
│   │   ├── interface.tf       # Common variables and types
│   │   ├── aws.tf             # AWS CloudWatch implementation
│   │   ├── gcp.tf             # GCP Cloud Monitoring implementation
│   │   ├── azure.tf           # Azure Monitor implementation
│   │   └── outputs.tf         # Unified outputs
│   ├── compute/               # Container orchestration interface
│   ├── database/              # PostgreSQL interface
│   └── cache/                 # Redis interface
├── aws/                       # AWS-specific deployment
│   ├── terraform/             # Terraform version (recommended)
│   └── lib/                   # CDK version (alternative)
├── gcp/                       # GCP-specific deployment
└── azure/                     # Azure-specific deployment
```

## Quick Start

### Local Development
```bash
../scripts/setup-local.sh
```

### AWS (Terraform)
```bash
cd aws/terraform
terraform init
terraform apply \
  -var-file="../../config/common.tfvars" \
  -var-file="../../config/monitoring.tfvars" \
  -var="aws_region=us-east-1"
```

### GCP (Terraform)
```bash
cd gcp
terraform init
terraform apply \
  -var-file="../config/common.tfvars" \
  -var-file="../config/monitoring.tfvars" \
  -var="project_id=your-project-id"
```

### Azure (Terraform)
```bash
cd azure
terraform init
terraform apply \
  -var-file="../config/common.tfvars" \
  -var-file="../config/monitoring.tfvars"
```

## The Interface Pattern

### Common Configuration (`config/common.tfvars`)

Define your infrastructure **once** using cloud-agnostic terms:

```hcl
# Container configuration - works on ECS, Cloud Run, or Container Apps
container_config = {
  image          = "sse-notification:latest"
  port           = 3000
  cpu            = 1000      # millicores
  memory         = 512       # MB
  min_instances  = 3
  max_instances  = 100
  health_path    = "/health"
  timeout        = 3600
}

# Database configuration - works on RDS, Cloud SQL, or Azure Database
database_config = {
  name           = "sseapp"
  engine_version = "16"
  instance_class = "small"   # small | medium | large
  storage_gb     = 20
  multi_az       = false
}

# Redis configuration - works on ElastiCache, Memorystore, or Azure Cache
redis_config = {
  version         = "7.0"
  instance_class  = "small"  # small | medium | large
  memory_gb       = 1
  high_availability = true
}
```

### Instance Class Mapping

The `instance_class` abstraction maps to provider-specific sizes:

| Interface | AWS | GCP | Azure |
|-----------|-----|-----|-------|
| **Database** |
| small | db.t3.micro | db-f1-micro | B_Standard_B1ms |
| medium | db.t3.medium | db-custom-2-4096 | GP_Standard_D2s_v3 |
| large | db.r5.large | db-custom-4-8192 | GP_Standard_D4s_v3 |
| **Redis** |
| small | cache.t3.micro | BASIC | C0 Standard |
| medium | cache.t3.medium | STANDARD_HA | C1 Standard |
| large | cache.r5.large | STANDARD_HA (5GB) | C3 Premium |

## Monitoring Module

The monitoring module implements a **unified alerting interface**:

### Define Alerts Once

```hcl
# config/monitoring.tfvars
alerts = [
  {
    name        = "high-cpu"
    description = "CPU utilization exceeded 80%"
    metric      = "cpu"           # Abstracted metric name
    threshold   = 80
    operator    = "gt"            # gt, lt, gte, lte
    period      = 300             # seconds
    severity    = "warning"       # critical, warning, info
  }
]
```

### Automatic Translation

The module automatically translates to each cloud's native format:

| Metric | AWS (CloudWatch) | GCP (Cloud Monitoring) | Azure (Monitor) |
|--------|------------------|------------------------|-----------------|
| cpu | `AWS/ECS:CPUUtilization` | `run.googleapis.com/container/cpu/utilizations` | `UsageNanoCores` |
| memory | `AWS/ECS:MemoryUtilization` | `run.googleapis.com/container/memory/utilizations` | `WorkingSetBytes` |
| errors | `AWS/ApplicationELB:HTTPCode_ELB_5XX_Count` | `run.googleapis.com/request_count` (5xx) | `Requests` (5xx) |
| latency | `AWS/ApplicationELB:TargetResponseTime` | `run.googleapis.com/request_latencies` | `RequestDuration` |

## Unified Outputs

All cloud deployments provide the same outputs:

```hcl
output "service_url"        # Application URL
output "database_endpoint"  # Database connection endpoint
output "redis_endpoint"     # Redis connection endpoint
output "dashboard_url"      # Monitoring dashboard URL
output "monitoring"         # Monitoring summary
```

## Comparison

| Feature | AWS | GCP | Azure |
|---------|-----|-----|-------|
| IaC Tool | Terraform / CDK | Terraform | Terraform |
| Compute | ECS Fargate | Cloud Run | Container Apps |
| Database | RDS PostgreSQL | Cloud SQL | Azure Database |
| Redis | ElastiCache | Memorystore | Azure Cache |
| Load Balancer | ALB | Cloud LB | Built-in Ingress |
| Monitoring | CloudWatch | Cloud Monitoring | Azure Monitor |
| Auto-scaling | Yes | Yes | Yes |
| Est. Cost (3 nodes) | ~$140/mo | ~$160/mo | ~$150/mo |

## Why This Pattern?

### 1. Single Source of Truth
Change `instance_class = "medium"` in one place, and it updates across all clouds.

### 2. Cloud Portability
Switch from AWS to GCP by running a different `terraform apply`. Zero code changes.

### 3. Consistent Operations
Same alert definitions, same dashboard structure, same outputs across all environments.

### 4. Reduced Cognitive Load
Teams don't need to know the specifics of each cloud's monitoring API.

### 5. Easy Testing
Test on one cloud, deploy to another with confidence.

## Prerequisites

All platforms require:
- Docker installed and running
- Cloud CLI authenticated
- Terraform >= 1.0.0

### AWS
```bash
aws configure
# Optional: for CDK version
npm install -g aws-cdk
```

### GCP
```bash
gcloud auth login
gcloud auth application-default login
```

### Azure
```bash
az login
```

## Extending the Interface

To add a new metric:

1. Add to `interface.tf` documentation
2. Add mapping in each provider file (`aws.tf`, `gcp.tf`, `azure.tf`)
3. Use in `config/monitoring.tfvars`

```hcl
# In aws.tf - add to local.aws_metric_mapping
new_metric = {
  namespace   = "AWS/SomeService"
  metric_name = "SomeMetric"
  dimensions  = { ... }
}

# In gcp.tf - add to local.gcp_metric_mapping
new_metric = {
  resource_type = "some_resource"
  metric_type   = "some.googleapis.com/metric"
  filter_extra  = "..."
}

# In azure.tf - add to local.azure_metric_mapping
new_metric = {
  resource_id = var.azure_some_resource_id
  metric_name = "SomeMetric"
  namespace   = "Microsoft.SomeService/resources"
  aggregation = "Average"
}
```

## Detailed Documentation

- [Local Setup Guide](../docs/LOCAL_SETUP.md)
- [AWS Deployment Guide](../docs/AWS_DEPLOYMENT.md)
- [GCP Deployment Guide](../docs/GCP_DEPLOYMENT.md)
- [Azure Deployment Guide](../docs/AZURE_DEPLOYMENT.md)

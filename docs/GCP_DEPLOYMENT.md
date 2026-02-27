# GCP Deployment Guide

Deploy the ChatPulse to Google Cloud Platform using Terraform.

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                 Google Cloud Platform                │
                    │                                                      │
    Internet        │   ┌─────────────────────────────────────────────┐   │
        │           │   │            Global Load Balancer              │   │
        │           │   │         (HTTP/HTTPS, no affinity)           │   │
        ▼           │   └───────────────────┬─────────────────────────┘   │
┌───────────────┐   │                       │                              │
│    Users      │───┼───────────────────────┤                              │
└───────────────┘   │                       │                              │
                    │   ┌───────────────────▼─────────────────────────┐   │
                    │   │              Cloud Run Service               │   │
                    │   │                                              │   │
                    │   │   ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
                    │   │   │Instance │ │Instance │ │Instance │ ...   │   │
                    │   │   │   1     │ │   2     │ │   N     │       │   │
                    │   │   └────┬────┘ └────┬────┘ └────┬────┘       │   │
                    │   │        │           │           │             │   │
                    │   └────────┼───────────┼───────────┼─────────────┘   │
                    │            │           │           │                 │
                    │   ┌────────▼───────────▼───────────▼─────────────┐   │
                    │   │             VPC Connector                     │   │
                    │   └────────────────────┬────────────────────────┘   │
                    │                        │                             │
                    │   ┌────────────────────▼────────────────────────┐   │
                    │   │              Cloud Memorystore               │   │
                    │   │            (Redis 7.0, HA mode)              │   │
                    │   └─────────────────────────────────────────────┘   │
                    │                                                      │
                    │   ┌─────────────────────────────────────────────┐   │
                    │   │              Cloud SQL PostgreSQL            │   │
                    │   │            (Private IP, HA mode)             │   │
                    │   └─────────────────────────────────────────────┘   │
                    │                                                      │
                    └──────────────────────────────────────────────────────┘
```

## Components

| Component | GCP Service | Purpose |
|-----------|-------------|---------|
| Load Balancer | Cloud Load Balancing | Global HTTP(S) load balancing |
| Compute | Cloud Run | Serverless containers with auto-scaling |
| Database | Cloud SQL PostgreSQL | User authentication & storage |
| Redis | Cloud Memorystore | Managed Redis with HA |
| Secrets | Secret Manager | Store JWT secret |
| Networking | VPC + Connector | Private connectivity |
| Container Registry | Artifact Registry | Docker image storage |

## Quick Deploy (One Command)

```bash
cd infra/gcp
chmod +x deploy.sh
export GCP_PROJECT_ID="your-project-id"
./deploy.sh deploy
```

## Prerequisites

### 1. Install Google Cloud SDK

**macOS:**
```bash
brew install google-cloud-sdk
```

**Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Windows:**
Download installer from: https://cloud.google.com/sdk/docs/install

### 2. Install Terraform

**macOS:**
```bash
brew install terraform
```

**Linux:**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Windows:**
```powershell
choco install terraform
```

### 3. Authenticate with GCP

```bash
# Login to GCP
gcloud auth login

# Set default project
gcloud config set project your-project-id

# Application default credentials (for Terraform)
gcloud auth application-default login
```

### 4. Install Docker

Required for building the container image. See [Local Setup Guide](./LOCAL_SETUP.md).

## Deployment Options

### Basic Deployment

```bash
export GCP_PROJECT_ID="your-project-id"
./deploy.sh deploy
```

### Custom Configuration

```bash
# Deploy to different region
GCP_PROJECT_ID=my-project GCP_REGION=europe-west1 ./deploy.sh deploy

# Deploy with more instances
GCP_PROJECT_ID=my-project MIN_INSTANCES=5 MAX_INSTANCES=200 ./deploy.sh deploy

# Staging environment
GCP_PROJECT_ID=my-project ENVIRONMENT=staging ./deploy.sh deploy
```

### Available Commands

```bash
./deploy.sh deploy    # Build image and deploy
./deploy.sh destroy   # Destroy all resources
./deploy.sh status    # Show deployment status
./deploy.sh build     # Build and push image only
./deploy.sh plan      # Preview Terraform changes
./deploy.sh output    # Show deployment outputs
```

## Manual Deployment

### Step 1: Create terraform.tfvars

```hcl
project_id    = "your-project-id"
region        = "us-central1"
environment   = "production"
min_instances = 3
max_instances = 100
```

### Step 2: Initialize Terraform

```bash
cd infra/gcp
terraform init
```

### Step 3: Build and Push Image

```bash
# Configure Docker
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build and push
docker build -t us-central1-docker.pkg.dev/PROJECT_ID/sse-notification/app:latest ../../
docker push us-central1-docker.pkg.dev/PROJECT_ID/sse-notification/app:latest
```

### Step 4: Deploy

```bash
terraform plan
terraform apply
```

## Post-Deployment

### Get Service URL

```bash
gcloud run services describe sse-notification-app \
  --region=us-central1 \
  --format="value(status.url)"
```

### Verify Health

```bash
SERVICE_URL=$(gcloud run services describe sse-notification-app \
  --region=us-central1 \
  --format="value(status.url)")

curl $SERVICE_URL/health
```

### View Logs

```bash
# Stream logs
gcloud logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=sse-notification-app"

# View in console
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=sse-notification-app" --limit=100
```

### Scale Service

```bash
gcloud run services update sse-notification-app \
  --region=us-central1 \
  --min-instances=5 \
  --max-instances=500
```

## Cost Estimation

| Resource | Configuration | Est. Monthly Cost |
|----------|--------------|-------------------|
| Cloud Run | 3 instances, 1 vCPU, 512 MB | ~$50 |
| Cloud SQL | db-f1-micro PostgreSQL | ~$10 |
| Memorystore | 1 GB, Standard HA | ~$70 |
| Load Balancer | Global HTTP | ~$20 |
| VPC Connector | f1-micro | ~$10 |
| Secret Manager | 2 secrets | ~$1 |
| Egress | 100 GB | ~$10 |
| **Total** | | **~$171/month** |

*Use GCP Pricing Calculator for accurate estimates.*

## Scaling to 10M Users

Modify `main.tf` for high-scale deployment:

```hcl
# Increase Cloud Run resources
resource "google_cloud_run_v2_service" "sse_app" {
  template {
    scaling {
      min_instance_count = 50
      max_instance_count = 1000
    }

    containers {
      resources {
        limits = {
          cpu    = "2000m"  # 2 vCPUs
          memory = "2Gi"    # 2 GB RAM
        }
      }
    }
  }
}

# Use larger Redis instance
resource "google_redis_instance" "redis" {
  tier           = "STANDARD_HA"
  memory_size_gb = 16
  replica_count  = 2
}

# Use larger Cloud SQL instance with HA
resource "google_sql_database_instance" "postgres" {
  settings {
    tier              = "db-custom-4-16384"  # 4 vCPU, 16 GB
    availability_type = "REGIONAL"            # High availability
  }
  deletion_protection = true
}
```

## Adding Custom Domain

### Step 1: Reserve Static IP

```bash
gcloud compute addresses create sse-notification-ip --global
```

### Step 2: Create SSL Certificate

```hcl
resource "google_compute_managed_ssl_certificate" "cert" {
  name = "sse-notification-cert"

  managed {
    domains = ["sse.yourdomain.com"]
  }
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "sse-notification-https-proxy"
  url_map          = google_compute_url_map.urlmap.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cert.id]
}

resource "google_compute_global_forwarding_rule" "https_frontend" {
  name       = "sse-notification-https-frontend"
  target     = google_compute_target_https_proxy.https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.ip.address
}
```

### Step 3: Update DNS

Point your domain to the load balancer IP:
```bash
gcloud compute addresses describe sse-notification-ip --global --format="value(address)"
```

## Troubleshooting

### Cloud Run Not Starting

```bash
# Check service status
gcloud run services describe sse-notification-app --region=us-central1

# Check revision logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

### Redis Connection Failed

```bash
# Verify VPC connector
gcloud compute networks vpc-access connectors describe sse-vpc-connector \
  --region=us-central1

# Check Redis status
gcloud redis instances describe sse-notification-redis --region=us-central1
```

### Image Push Failed

```bash
# Re-authenticate
gcloud auth configure-docker us-central1-docker.pkg.dev

# Check Artifact Registry permissions
gcloud artifacts repositories describe sse-notification \
  --location=us-central1
```

## Cleanup

```bash
./deploy.sh destroy
```

This removes all GCP resources including:
- Cloud Run service
- Memorystore Redis
- VPC and connector
- Load balancer
- Artifact Registry

## Next Steps

- [AWS Deployment Guide](./AWS_DEPLOYMENT.md)
- [Azure Deployment Guide](./AZURE_DEPLOYMENT.md)

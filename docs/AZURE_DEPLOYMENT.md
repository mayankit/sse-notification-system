# Azure Deployment Guide

Deploy the SSE Notification System to Microsoft Azure using Terraform.

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                  Microsoft Azure                     │
                    │                                                      │
    Internet        │   ┌─────────────────────────────────────────────┐   │
        │           │   │           Container Apps Ingress             │   │
        │           │   │         (HTTPS, no session affinity)        │   │
        ▼           │   └───────────────────┬─────────────────────────┘   │
┌───────────────┐   │                       │                              │
│    Users      │───┼───────────────────────┤                              │
└───────────────┘   │                       │                              │
                    │   ┌───────────────────▼─────────────────────────┐   │
                    │   │         Container Apps Environment           │   │
                    │   │                                              │   │
                    │   │   ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
                    │   │   │Replica  │ │Replica  │ │Replica  │ ...   │   │
                    │   │   │   1     │ │   2     │ │   N     │       │   │
                    │   │   └────┬────┘ └────┬────┘ └────┬────┘       │   │
                    │   │        │           │           │             │   │
                    │   └────────┼───────────┼───────────┼─────────────┘   │
                    │            │           │           │                 │
                    │   ┌────────▼───────────▼───────────▼─────────────┐   │
                    │   │                   VNet                        │   │
                    │   │                                               │   │
                    │   │   ┌─────────────────────────────────────┐    │   │
                    │   │   │        Azure Cache for Redis         │    │   │
                    │   │   │           (Standard C1)              │    │   │
                    │   │   └─────────────────────────────────────┘    │   │
                    │   │                                               │   │
                    │   │   ┌─────────────────────────────────────┐    │   │
                    │   │   │   PostgreSQL Flexible Server        │    │   │
                    │   │   │         (B_Standard_B1ms)           │    │   │
                    │   │   └─────────────────────────────────────┘    │   │
                    │   │                                               │   │
                    │   └───────────────────────────────────────────────┘   │
                    │                                                      │
                    └──────────────────────────────────────────────────────┘
```

## Components

| Component | Azure Service | Purpose |
|-----------|--------------|---------|
| Compute | Container Apps | Serverless containers with auto-scaling |
| Database | PostgreSQL Flexible Server | User authentication & storage |
| Redis | Azure Cache for Redis | Managed Redis with HA |
| Registry | Container Registry | Docker image storage |
| Networking | VNet + Subnets | Private connectivity |
| Logs | Log Analytics | Centralized logging |

## Quick Deploy (One Command)

```bash
cd infra/azure
chmod +x deploy.sh
./deploy.sh deploy
```

## Prerequisites

### 1. Install Azure CLI

**macOS:**
```bash
brew install azure-cli
```

**Linux:**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Windows:**
```powershell
winget install Microsoft.AzureCLI
```

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

### 3. Login to Azure

```bash
# Interactive login
az login

# Set subscription (if you have multiple)
az account set --subscription "Your Subscription Name"

# Verify
az account show
```

### 4. Install Docker

Required for building the container image. See [Local Setup Guide](./LOCAL_SETUP.md).

## Deployment Options

### Basic Deployment

```bash
./deploy.sh deploy
```

### Custom Configuration

```bash
# Deploy to different region
AZURE_LOCATION=westeurope ./deploy.sh deploy

# Deploy with more replicas
MIN_REPLICAS=5 MAX_REPLICAS=200 ./deploy.sh deploy

# Custom resource group
AZURE_RESOURCE_GROUP=my-sse-rg ./deploy.sh deploy

# Combine options
AZURE_LOCATION=westus2 MIN_REPLICAS=10 ENVIRONMENT=staging ./deploy.sh deploy
```

### Available Commands

```bash
./deploy.sh deploy    # Deploy infrastructure and app
./deploy.sh destroy   # Destroy all resources
./deploy.sh status    # Show deployment status
./deploy.sh build     # Build and push image only
./deploy.sh plan      # Preview Terraform changes
./deploy.sh output    # Show deployment outputs
```

## Manual Deployment

### Step 1: Create terraform.tfvars

```hcl
resource_group_name = "sse-notification-rg"
location            = "eastus"
environment         = "production"
min_replicas        = 3
max_replicas        = 100
```

### Step 2: Initialize Terraform

```bash
cd infra/azure
terraform init
```

### Step 3: Deploy Infrastructure

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 4: Build and Push Image

```bash
# Get ACR credentials
ACR_NAME=$(terraform output -raw acr_login_server)
ACR_USER=$(terraform output -raw acr_username)
ACR_PASS=$(terraform output -raw acr_password)

# Login and push
echo $ACR_PASS | docker login $ACR_NAME -u $ACR_USER --password-stdin
docker build -t ${ACR_NAME}/sse-notification:latest ../../
docker push ${ACR_NAME}/sse-notification:latest

# Update Container App
terraform apply -auto-approve
```

## Post-Deployment

### Get Application URL

```bash
az containerapp show \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

### Verify Health

```bash
APP_URL=$(az containerapp show \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --query "properties.configuration.ingress.fqdn" -o tsv)

curl https://$APP_URL/health
```

### View Logs

```bash
# Stream logs
az containerapp logs show \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --follow

# View in Log Analytics (Azure Portal)
# Navigate to: Resource Group > Log Analytics > Logs
# Query: ContainerAppConsoleLogs_CL | where ContainerAppName_s == "sse-notification-app"
```

### Scale Application

```bash
az containerapp update \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --min-replicas 5 \
  --max-replicas 50
```

## Cost Estimation

| Resource | Configuration | Est. Monthly Cost |
|----------|--------------|-------------------|
| Container Apps | 3 replicas, 0.5 vCPU, 1 GB | ~$50 |
| PostgreSQL Flexible | B_Standard_B1ms | ~$15 |
| Azure Cache for Redis | Standard C1 | ~$80 |
| Container Registry | Basic | ~$5 |
| Log Analytics | 5 GB/day | ~$10 |
| VNet | Standard | ~$5 |
| **Total** | | **~$165/month** |

*Use Azure Pricing Calculator for accurate estimates.*

## Scaling to 10M Users

Modify `main.tf` for high-scale deployment:

```hcl
# Increase Container App resources
resource "azurerm_container_app" "app" {
  template {
    min_replicas = 50
    max_replicas = 1000

    container {
      cpu    = 2.0
      memory = "4Gi"
    }

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = 500
    }
  }
}

# Use larger PostgreSQL instance with HA
resource "azurerm_postgresql_flexible_server" "postgres" {
  sku_name                     = "GP_Standard_D4s_v3"  # 4 vCPU, 16 GB
  high_availability {
    mode = "ZoneRedundant"
  }
  geo_redundant_backup_enabled = true
}

# Use Premium Redis
resource "azurerm_redis_cache" "redis" {
  capacity     = 3
  family       = "P"
  sku_name     = "Premium"
  shard_count  = 3  # Cluster mode

  redis_configuration {
    enable_authentication = true
  }
}
```

## Adding Custom Domain

### Step 1: Configure Domain in Container Apps

```bash
# Add custom domain
az containerapp hostname add \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --hostname sse.yourdomain.com

# Bind certificate
az containerapp hostname bind \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --hostname sse.yourdomain.com \
  --environment sse-notification-env \
  --validation-method CNAME
```

### Step 2: Update DNS

Create a CNAME record pointing to your Container App FQDN:
```
sse.yourdomain.com -> sse-notification-app.xxx.azurecontainerapps.io
```

## Troubleshooting

### Container App Not Starting

```bash
# Check app status
az containerapp show \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --query "properties.runningStatus"

# View logs
az containerapp logs show \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --tail 100
```

### Redis Connection Failed

```bash
# Check Redis status
az redis show \
  --name <redis-name> \
  --resource-group sse-notification-rg \
  --query "provisioningState"

# Test connectivity from Container App
az containerapp exec \
  --name sse-notification-app \
  --resource-group sse-notification-rg \
  --command "redis-cli -h <redis-host> ping"
```

### Image Push Failed

```bash
# Re-authenticate to ACR
az acr login --name <acr-name>

# Check ACR status
az acr check-health --name <acr-name>
```

## Cleanup

```bash
./deploy.sh destroy
```

This removes all Azure resources including:
- Container App and Environment
- Azure Cache for Redis
- Container Registry
- Virtual Network
- Log Analytics Workspace
- Resource Group

## Next Steps

- [AWS Deployment Guide](./AWS_DEPLOYMENT.md)
- [GCP Deployment Guide](./GCP_DEPLOYMENT.md)

#!/bin/bash

#######################################################################
# Azure Terraform Deployment Script for SSE Notification System
#######################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Configuration
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-sse-notification-rg}"
LOCATION="${AZURE_LOCATION:-eastus}"
ENVIRONMENT="${ENVIRONMENT:-production}"
MIN_REPLICAS="${MIN_REPLICAS:-3}"
MAX_REPLICAS="${MAX_REPLICAS:-100}"
ACTION="${1:-deploy}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

print_header "SSE Notification System - Azure Deployment"

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        echo "Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI installed"

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        echo "Install: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi
    print_success "Terraform installed: $(terraform version -json | jq -r '.terraform_version')"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_success "Docker installed"

    # Check if logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure"
        echo "Run: az login"
        exit 1
    fi
    print_success "Azure CLI authenticated"

    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_info "Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    print_info "Location: $LOCATION"
}

# Initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    terraform init -upgrade
    print_success "Terraform initialized"
}

# Create terraform.tfvars
create_tfvars() {
    cat > terraform.tfvars << EOF
resource_group_name = "${RESOURCE_GROUP}"
location            = "${LOCATION}"
environment         = "${ENVIRONMENT}"
min_replicas        = ${MIN_REPLICAS}
max_replicas        = ${MAX_REPLICAS}
EOF
    print_success "terraform.tfvars created"
}

# Deploy infrastructure first (without app)
deploy_infrastructure() {
    print_header "Deploying Infrastructure"

    create_tfvars

    print_info "Planning deployment..."
    terraform plan -out=tfplan

    print_info "Applying deployment..."
    terraform apply tfplan

    rm -f tfplan

    print_success "Infrastructure deployed!"
}

# Build and push Docker image
build_and_push_image() {
    print_header "Building and Pushing Docker Image"

    # Get ACR credentials from Terraform outputs
    ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
    ACR_USERNAME=$(terraform output -raw acr_username)
    ACR_PASSWORD=$(terraform output -raw acr_password)

    print_info "ACR: $ACR_LOGIN_SERVER"

    # Login to ACR
    print_info "Logging in to Azure Container Registry..."
    echo $ACR_PASSWORD | docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME --password-stdin

    # Build image
    print_info "Building Docker image..."
    docker build -t ${ACR_LOGIN_SERVER}/sse-notification:latest ${PROJECT_ROOT}

    # Push image
    print_info "Pushing image to ACR..."
    docker push ${ACR_LOGIN_SERVER}/sse-notification:latest

    print_success "Image pushed: ${ACR_LOGIN_SERVER}/sse-notification:latest"
}

# Update Container App with new image
update_container_app() {
    print_header "Updating Container App"

    # Force re-apply to update container app with the new image
    terraform apply -auto-approve -var-file=terraform.tfvars

    print_success "Container App updated!"
}

# Show outputs
show_outputs() {
    print_header "Deployment Outputs"
    terraform output

    echo ""
    APP_URL=$(terraform output -raw container_app_url 2>/dev/null || echo "")
    if [ -n "$APP_URL" ]; then
        print_info "Application URL: $APP_URL"
        print_info "Test UI: $APP_URL"
        print_info "Dashboard: $APP_URL/dashboard.html"
        print_info "Health: $APP_URL/health"
    fi
}

# Destroy infrastructure
destroy_infrastructure() {
    print_warning "This will destroy all Azure resources!"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" = "yes" ]; then
        create_tfvars
        print_info "Destroying infrastructure..."
        terraform destroy -auto-approve
        print_success "Infrastructure destroyed"
    else
        print_info "Cancelled"
    fi
}

# Show status
show_status() {
    print_header "Deployment Status"

    print_info "Container App:"
    az containerapp show \
        --name sse-notification-app \
        --resource-group $RESOURCE_GROUP \
        --query "{Name:name, URL:properties.configuration.ingress.fqdn, Replicas:properties.template.scale}" \
        -o table 2>/dev/null || print_warning "Container App not found"

    echo ""
    print_info "Redis Cache:"
    az redis show \
        --name $(az redis list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv 2>/dev/null) \
        --resource-group $RESOURCE_GROUP \
        --query "{Name:name, HostName:hostName, Port:port, ProvisioningState:provisioningState}" \
        -o table 2>/dev/null || print_warning "Redis not found"
}

# Main execution
cd "$SCRIPT_DIR"

check_prerequisites

case $ACTION in
    deploy)
        init_terraform
        deploy_infrastructure
        build_and_push_image
        update_container_app
        show_outputs
        ;;
    destroy)
        init_terraform
        destroy_infrastructure
        ;;
    status)
        show_status
        ;;
    build)
        init_terraform
        build_and_push_image
        update_container_app
        ;;
    plan)
        init_terraform
        create_tfvars
        terraform plan
        ;;
    output)
        terraform output
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|status|build|plan|output}"
        echo ""
        echo "Commands:"
        echo "  deploy   - Deploy infrastructure and application"
        echo "  destroy  - Destroy all resources"
        echo "  status   - Show deployment status"
        echo "  build    - Build and push image, update Container App"
        echo "  plan     - Preview Terraform changes"
        echo "  output   - Show Terraform outputs"
        echo ""
        echo "Environment variables:"
        echo "  AZURE_RESOURCE_GROUP - Resource group name (default: sse-notification-rg)"
        echo "  AZURE_LOCATION       - Azure region (default: eastus)"
        echo "  ENVIRONMENT          - Environment name (default: production)"
        echo "  MIN_REPLICAS         - Minimum replicas (default: 3)"
        echo "  MAX_REPLICAS         - Maximum replicas (default: 100)"
        exit 1
        ;;
esac

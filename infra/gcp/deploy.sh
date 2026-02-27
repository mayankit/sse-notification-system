#!/bin/bash

#######################################################################
# GCP Terraform Deployment Script for ChatPulse
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
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
MIN_INSTANCES="${MIN_INSTANCES:-3}"
MAX_INSTANCES="${MAX_INSTANCES:-100}"
ACTION="${1:-deploy}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

print_header "ChatPulse - GCP Deployment"

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud SDK (gcloud) is not installed"
        echo "Install: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_success "gcloud CLI installed"

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

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null 2>&1; then
        print_error "Not authenticated with gcloud"
        echo "Run: gcloud auth login"
        exit 1
    fi
    print_success "gcloud authenticated"

    # Get or set project ID
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            print_error "GCP_PROJECT_ID not set and no default project"
            echo "Set: export GCP_PROJECT_ID=your-project-id"
            echo "Or:  gcloud config set project your-project-id"
            exit 1
        fi
    fi

    print_info "Project ID: $PROJECT_ID"
    print_info "Region: $REGION"
}

# Build and push Docker image
build_and_push_image() {
    print_header "Building and Pushing Docker Image"

    REPO_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/sse-notification"
    IMAGE_URL="${REPO_URL}/app:latest"

    # Configure Docker for Artifact Registry
    print_info "Configuring Docker authentication..."
    gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

    # Build image
    print_info "Building Docker image..."
    docker build -t ${IMAGE_URL} ${PROJECT_ROOT}

    # Push image
    print_info "Pushing image to Artifact Registry..."
    docker push ${IMAGE_URL}

    print_success "Image pushed: ${IMAGE_URL}"
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
project_id    = "${PROJECT_ID}"
region        = "${REGION}"
environment   = "${ENVIRONMENT}"
min_instances = ${MIN_INSTANCES}
max_instances = ${MAX_INSTANCES}
EOF
    print_success "terraform.tfvars created"
}

# Deploy infrastructure
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

# Show outputs
show_outputs() {
    print_header "Deployment Outputs"
    terraform output
}

# Destroy infrastructure
destroy_infrastructure() {
    print_warning "This will destroy all GCP resources!"
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

    print_info "Cloud Run Service:"
    gcloud run services describe sse-notification-app \
        --region=$REGION \
        --format="table(status.url, status.conditions[0].status)" 2>/dev/null || \
        print_warning "Service not found"

    echo ""
    print_info "Redis Instance:"
    gcloud redis instances describe sse-notification-redis \
        --region=$REGION \
        --format="table(host, port, state)" 2>/dev/null || \
        print_warning "Redis not found"
}

# Main execution
cd "$SCRIPT_DIR"

check_prerequisites

case $ACTION in
    deploy)
        init_terraform
        build_and_push_image
        deploy_infrastructure
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
        build_and_push_image
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
        echo "  deploy   - Build image and deploy infrastructure"
        echo "  destroy  - Destroy all resources"
        echo "  status   - Show deployment status"
        echo "  build    - Build and push Docker image only"
        echo "  plan     - Preview Terraform changes"
        echo "  output   - Show Terraform outputs"
        echo ""
        echo "Environment variables:"
        echo "  GCP_PROJECT_ID  - GCP Project ID (required)"
        echo "  GCP_REGION      - GCP Region (default: us-central1)"
        echo "  ENVIRONMENT     - Environment name (default: production)"
        echo "  MIN_INSTANCES   - Minimum Cloud Run instances (default: 3)"
        echo "  MAX_INSTANCES   - Maximum Cloud Run instances (default: 100)"
        exit 1
        ;;
esac

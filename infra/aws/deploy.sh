#!/bin/bash

#######################################################################
# AWS CDK Deployment Script for SSE Notification System
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

# Default values
REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
DESIRED_COUNT="${DESIRED_COUNT:-3}"
ACTION="${1:-deploy}"

print_header "SSE Notification System - AWS Deployment"

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    print_success "AWS CLI installed"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    fi
    print_success "AWS credentials configured"

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_info "AWS Account: $ACCOUNT_ID"
    print_info "AWS Region: $REGION"

    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed"
        exit 1
    fi
    print_success "Node.js installed: $(node --version)"

    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        exit 1
    fi
    print_success "npm installed: $(npm --version)"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_success "Docker installed"
}

# Install dependencies
install_dependencies() {
    print_info "Installing CDK dependencies..."
    npm install
    print_success "Dependencies installed"
}

# Bootstrap CDK (first-time setup)
bootstrap_cdk() {
    print_info "Bootstrapping CDK (if needed)..."
    npx cdk bootstrap aws://$ACCOUNT_ID/$REGION
    print_success "CDK bootstrapped"
}

# Deploy the stack
deploy_stack() {
    print_header "Deploying SSE Notification System"

    print_info "Configuration:"
    echo "  Region:        $REGION"
    echo "  Environment:   $ENVIRONMENT"
    echo "  Desired Count: $DESIRED_COUNT"
    echo ""

    npx cdk deploy --all \
        --require-approval never \
        --context region=$REGION \
        --context environment=$ENVIRONMENT \
        --context desiredCount=$DESIRED_COUNT

    print_success "Deployment complete!"

    # Get outputs
    echo ""
    print_header "Deployment Outputs"
    aws cloudformation describe-stacks \
        --stack-name SSENotificationStack \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table \
        --region $REGION
}

# Destroy the stack
destroy_stack() {
    print_warning "This will destroy all resources!"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" = "yes" ]; then
        print_info "Destroying stack..."
        npx cdk destroy --all --force
        print_success "Stack destroyed"
    else
        print_info "Cancelled"
    fi
}

# Show stack status
show_status() {
    print_header "Stack Status"
    aws cloudformation describe-stacks \
        --stack-name SSENotificationStack \
        --query 'Stacks[0].{Status:StackStatus,Created:CreationTime,Updated:LastUpdatedTime}' \
        --output table \
        --region $REGION 2>/dev/null || print_warning "Stack not found"

    echo ""
    print_info "ECS Service Status:"
    aws ecs describe-services \
        --cluster SSENotificationStack-cluster \
        --services SSENotificationStack-service \
        --query 'services[0].{DesiredCount:desiredCount,RunningCount:runningCount,Status:status}' \
        --output table \
        --region $REGION 2>/dev/null || print_warning "Service not found"
}

# Main execution
cd "$(dirname "$0")"

check_prerequisites
install_dependencies

case $ACTION in
    deploy)
        bootstrap_cdk
        deploy_stack
        ;;
    destroy)
        destroy_stack
        ;;
    status)
        show_status
        ;;
    bootstrap)
        bootstrap_cdk
        ;;
    diff)
        npx cdk diff --context region=$REGION
        ;;
    synth)
        npx cdk synth --context region=$REGION
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|status|bootstrap|diff|synth}"
        echo ""
        echo "Commands:"
        echo "  deploy    - Deploy the stack (default)"
        echo "  destroy   - Destroy the stack"
        echo "  status    - Show stack status"
        echo "  bootstrap - Bootstrap CDK"
        echo "  diff      - Show changes"
        echo "  synth     - Synthesize CloudFormation"
        echo ""
        echo "Environment variables:"
        echo "  AWS_REGION     - AWS region (default: us-east-1)"
        echo "  ENVIRONMENT    - Environment name (default: production)"
        echo "  DESIRED_COUNT  - Number of ECS tasks (default: 3)"
        exit 1
        ;;
esac

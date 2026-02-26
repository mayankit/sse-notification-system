#!/bin/bash

#######################################################################
# SSE Notification System - Local Setup Script
# Supports: macOS, Linux (Ubuntu/Debian, RHEL/CentOS/Fedora, Arch)
#######################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_info "Detected: macOS"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        print_info "Detected: Debian/Ubuntu"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        print_info "Detected: RHEL/CentOS/Fedora"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
        print_info "Detected: Arch Linux"
    else
        OS="unknown"
        print_warning "Unknown OS, will attempt generic installation"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Homebrew on macOS
install_homebrew() {
    if ! command_exists brew; then
        print_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add to PATH for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        print_success "Homebrew installed"
    else
        print_success "Homebrew already installed"
    fi
}

# Install Docker on macOS
install_docker_macos() {
    if ! command_exists docker; then
        print_info "Installing Docker Desktop for macOS..."

        # Detect architecture
        ARCH=$(uname -m)
        if [[ "$ARCH" == "arm64" ]]; then
            DOCKER_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
        else
            DOCKER_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
        fi

        # Download Docker
        print_info "Downloading Docker Desktop..."
        curl -L -o /tmp/Docker.dmg "$DOCKER_URL"

        # Mount and install
        print_info "Installing Docker Desktop..."
        hdiutil attach /tmp/Docker.dmg -nobrowse -quiet
        cp -R "/Volumes/Docker/Docker.app" /Applications/
        hdiutil detach "/Volumes/Docker" -quiet
        rm /tmp/Docker.dmg

        print_success "Docker Desktop installed"
        print_info "Starting Docker Desktop..."
        open /Applications/Docker.app

        # Wait for Docker to start
        print_info "Waiting for Docker to initialize (this may take 60 seconds)..."
        for i in {1..60}; do
            if docker info >/dev/null 2>&1; then
                print_success "Docker is running"
                return 0
            fi
            sleep 2
            echo -n "."
        done
        echo ""
        print_warning "Docker may still be starting. Please wait and re-run this script."
        exit 1
    else
        print_success "Docker already installed"

        # Check if Docker daemon is running
        if ! docker info >/dev/null 2>&1; then
            print_info "Starting Docker Desktop..."
            open /Applications/Docker.app

            print_info "Waiting for Docker to start..."
            for i in {1..30}; do
                if docker info >/dev/null 2>&1; then
                    print_success "Docker is running"
                    return 0
                fi
                sleep 2
                echo -n "."
            done
            echo ""
            print_error "Docker failed to start. Please start Docker Desktop manually."
            exit 1
        fi
    fi
}

# Install Docker on Debian/Ubuntu
install_docker_debian() {
    if ! command_exists docker; then
        print_info "Installing Docker on Debian/Ubuntu..."

        # Update package index
        sudo apt-get update

        # Install prerequisites
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker's official GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # Set up the repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

        # Add current user to docker group
        sudo usermod -aG docker $USER

        # Start Docker
        sudo systemctl start docker
        sudo systemctl enable docker

        print_success "Docker installed"
        print_warning "You may need to log out and back in for group changes to take effect"
    else
        print_success "Docker already installed"
    fi
}

# Install Docker on RHEL/CentOS/Fedora
install_docker_redhat() {
    if ! command_exists docker; then
        print_info "Installing Docker on RHEL/CentOS/Fedora..."

        # Remove old versions
        sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

        # Install prerequisites
        sudo yum install -y yum-utils

        # Add Docker repository
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        # Install Docker
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

        # Add current user to docker group
        sudo usermod -aG docker $USER

        # Start Docker
        sudo systemctl start docker
        sudo systemctl enable docker

        print_success "Docker installed"
        print_warning "You may need to log out and back in for group changes to take effect"
    else
        print_success "Docker already installed"
    fi
}

# Install Docker on Arch Linux
install_docker_arch() {
    if ! command_exists docker; then
        print_info "Installing Docker on Arch Linux..."

        sudo pacman -Sy --noconfirm docker docker-compose

        # Add current user to docker group
        sudo usermod -aG docker $USER

        # Start Docker
        sudo systemctl start docker
        sudo systemctl enable docker

        print_success "Docker installed"
        print_warning "You may need to log out and back in for group changes to take effect"
    else
        print_success "Docker already installed"
    fi
}

# Install Node.js (optional, for local development without Docker)
install_nodejs() {
    if ! command_exists node; then
        print_info "Installing Node.js..."

        case $OS in
            macos)
                brew install node@20
                ;;
            debian)
                curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
                sudo apt-get install -y nodejs
                ;;
            redhat)
                curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
                sudo yum install -y nodejs
                ;;
            arch)
                sudo pacman -Sy --noconfirm nodejs npm
                ;;
        esac

        print_success "Node.js installed"
    else
        print_success "Node.js already installed: $(node --version)"
    fi
}

# Verify Docker installation
verify_docker() {
    print_info "Verifying Docker installation..."

    if docker --version >/dev/null 2>&1; then
        print_success "Docker CLI: $(docker --version)"
    else
        print_error "Docker CLI not found"
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        print_success "Docker Compose: $(docker compose version)"
    else
        print_error "Docker Compose not found"
        return 1
    fi

    if docker info >/dev/null 2>&1; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

# Start the application
start_application() {
    print_header "Starting SSE Notification System"

    # Navigate to project directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    cd "$PROJECT_DIR"

    print_info "Project directory: $PROJECT_DIR"

    # Stop any existing containers
    print_info "Stopping any existing containers..."
    docker compose down 2>/dev/null || true

    # Build and start
    print_info "Building and starting services..."
    docker compose up --build -d

    # Wait for services to be ready
    print_info "Waiting for services to be healthy..."
    sleep 5

    # Check health
    for port in 3001 3002 3003; do
        if curl -s "http://localhost:$port/health" | grep -q '"status":"ok"'; then
            print_success "server on port $port is healthy"
        else
            print_warning "server on port $port may still be starting"
        fi
    done

    print_header "Setup Complete!"
    echo -e "${GREEN}The SSE Notification System is now running!${NC}\n"
    echo -e "Access the application:"
    echo -e "  ${BLUE}Chat UI:${NC}        http://localhost:3000/chat.html  (with login/signup)"
    echo -e "  ${BLUE}Test UI:${NC}        http://localhost:3000"
    echo -e "  ${BLUE}Dashboard:${NC}      http://localhost:3000/dashboard.html"
    echo -e "  ${BLUE}Health Check:${NC}   http://localhost:3000/health"
    echo -e ""
    echo -e "Individual nodes (bypass load balancer):"
    echo -e "  ${BLUE}Server 1:${NC}       http://localhost:3001/health"
    echo -e "  ${BLUE}Server 2:${NC}       http://localhost:3002/health"
    echo -e "  ${BLUE}Server 3:${NC}       http://localhost:3003/health"
    echo -e ""
    echo -e "Services running:"
    echo -e "  ${GREEN}PostgreSQL:${NC}     localhost:5432  (user storage)"
    echo -e "  ${GREEN}Redis:${NC}          localhost:6379  (messaging)"
    echo -e "  ${GREEN}Nginx:${NC}          localhost:3000  (load balancer)"
    echo -e ""
    echo -e "Useful commands:"
    echo -e "  ${YELLOW}docker compose logs -f${NC}     # View logs"
    echo -e "  ${YELLOW}docker compose down${NC}        # Stop all services"
    echo -e "  ${YELLOW}docker compose restart${NC}     # Restart services"
    echo -e "  ${YELLOW}docker compose down -v${NC}     # Stop and remove data"
}

# Main execution
main() {
    print_header "SSE Notification System - Local Setup"

    detect_os

    # Install Docker based on OS
    case $OS in
        macos)
            install_homebrew
            install_docker_macos
            ;;
        debian)
            install_docker_debian
            ;;
        redhat)
            install_docker_redhat
            ;;
        arch)
            install_docker_arch
            ;;
        *)
            print_error "Unsupported OS. Please install Docker manually."
            echo "Visit: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    # Verify installation
    if ! verify_docker; then
        print_error "Docker installation verification failed"
        exit 1
    fi

    # Start the application
    start_application
}

# Run main function
main "$@"


# Local Setup Guide

Complete guide to run the ChatPulse locally on any platform.

## Features

- Real-time notifications using Server-Sent Events (SSE)
- User authentication with JWT (signup/login)
- PostgreSQL database for user storage
- Redis for pub/sub messaging and session management
- 3 load-balanced application nodes
- Nginx as reverse proxy

## Quick Start (One Command)

### macOS / Linux

```bash
# Clone and run
git clone <repository-url>
cd SSEApplication
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

### Windows (PowerShell - Run as Administrator)

```powershell
# Clone and run
git clone <repository-url>
cd SSEApplication
.\scripts\setup-local.ps1
```

### Windows (Command Prompt - Run as Administrator)

```cmd
REM Clone and run
git clone <repository-url>
cd SSEApplication
scripts\setup-local.bat
```

## What the Setup Script Does

1. **Detects your operating system** (macOS, Ubuntu, Debian, RHEL, CentOS, Fedora, Arch, Windows)
2. **Installs Docker** if not present
3. **Starts Docker daemon** if not running
4. **Builds and launches** all services (3 app nodes + PostgreSQL + Redis + Nginx)
5. **Initializes the database** schema automatically
6. **Opens the application** in your browser

## Manual Installation

If you prefer manual installation or the script fails:

### macOS

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Docker Desktop
brew install --cask docker

# Start Docker Desktop
open /Applications/Docker.app

# Wait for Docker to start, then run the app
cd SSEApplication
docker compose up --build -d

# Open browser
open http://localhost:3000
```

### Ubuntu / Debian

```bash
# Update packages
sudo apt-get update

# Install prerequisites
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to docker group (logout/login required)
sudo usermod -aG docker $USER

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Run the app (after logout/login or use sudo)
cd SSEApplication
docker compose up --build -d
```

### RHEL / CentOS / Fedora

```bash
# Install prerequisites
sudo yum install -y yum-utils

# Add Docker repository
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to docker group
sudo usermod -aG docker $USER

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Run the app
cd SSEApplication
docker compose up --build -d
```

### Windows 10/11

1. **Enable WSL2**
   ```powershell
   # Run in PowerShell as Administrator
   wsl --install
   ```

2. **Download Docker Desktop**
   - Visit: https://www.docker.com/products/docker-desktop
   - Download and run the installer
   - Restart your computer when prompted

3. **Run the application**
   ```powershell
   cd SSEApplication
   docker compose up --build -d
   ```

4. **Open browser**
   - Visit: http://localhost:3000

## Verifying Installation

After setup completes, verify all services are running:

```bash
# Check container status
docker compose ps

# Expected output:
# NAME                       STATUS
# sseapplication-postgres-1  Up (healthy)
# sseapplication-redis-1     Up (healthy)
# sseapplication-app1-1      Up
# sseapplication-app2-1      Up
# sseapplication-app3-1      Up
# sseapplication-nginx-1     Up

# Check health endpoints
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health

# Test authentication
# Create a new user
curl -X POST http://localhost:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "email": "test@example.com", "password": "password123"}'

# Login
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "password123"}'
```

## Accessing the Application

| URL | Description |
|-----|-------------|
| http://localhost:3000/chat.html | Chat UI with login/signup |
| http://localhost:3000 | Legacy test UI |
| http://localhost:3000/dashboard.html | Health Dashboard |
| http://localhost:3000/health | Load-balanced health check |
| http://localhost:3001/health | Server 1 direct health |
| http://localhost:3002/health | Server 2 direct health |
| http://localhost:3003/health | Server 3 direct health |

## Authentication

The application uses JWT-based authentication:

1. **Sign Up**: Create a new account with username, email, and password
2. **Login**: Authenticate with username and password to receive a JWT token
3. **Connect**: Use the token to establish SSE connection and send messages

All API endpoints (except `/auth/signup`, `/auth/login`, and `/health`) require authentication via Bearer token in the Authorization header.

## Common Commands

```bash
# View logs (all services)
docker compose logs -f

# View logs (specific service)
docker compose logs -f app1

# Stop all services
docker compose down

# Restart all services
docker compose restart

# Rebuild and restart
docker compose up --build -d

# Remove all data (including volumes)
docker compose down -v

# Check Redis
docker exec sseapplication-redis-1 redis-cli PING

# Check PostgreSQL
docker exec sseapplication-postgres-1 psql -U postgres -d sseapp -c "SELECT COUNT(*) FROM users;"

# Connect to PostgreSQL
docker exec -it sseapplication-postgres-1 psql -U postgres -d sseapp
```

## Troubleshooting

### Docker not starting (macOS)

```bash
# Reset Docker Desktop
rm -rf ~/Library/Containers/com.docker.docker
rm -rf ~/.docker
# Then reinstall Docker Desktop
```

### Permission denied (Linux)

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and log back in, or run:
newgrp docker
```

### Port already in use

```bash
# Find process using port 3000
lsof -i :3000  # macOS/Linux
netstat -ano | findstr :3000  # Windows

# Kill the process or change ports in docker-compose.yml
```

### Container keeps restarting

```bash
# Check logs for errors
docker compose logs app1

# Common fixes:
# - Ensure Redis is healthy first
# - Check if .env.docker exists
# - Verify no syntax errors in JS files
```

### WSL2 issues (Windows)

```powershell
# Update WSL
wsl --update

# Set WSL2 as default
wsl --set-default-version 2

# Restart Docker Desktop
```

## Development Without Docker

If you want to run without Docker (single node, local PostgreSQL and Redis required):

```bash
# Install Node.js 20+
# Install PostgreSQL 16+
# Install Redis locally

# Start PostgreSQL
pg_ctl -D /usr/local/var/postgres start

# Create database
createdb sseapp

# Start Redis
redis-server

# Install dependencies
npm install

# Create .env file
cp .env.example .env

# Edit .env with your local settings:
# DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sseapp
# REDIS_URL=redis://localhost:6379
# JWT_SECRET=your-super-secret-jwt-key-change-in-production

# Start the application
npm start
```

## Next Steps

- [AWS Deployment Guide](./AWS_DEPLOYMENT.md)
- [GCP Deployment Guide](./GCP_DEPLOYMENT.md)
- [Azure Deployment Guide](./AZURE_DEPLOYMENT.md)

#######################################################################
# SSE Notification System - Local Setup Script for Windows
# Run as Administrator: Right-click PowerShell -> Run as Administrator
# Then execute: .\scripts\setup-local.ps1
#######################################################################

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Colors
function Write-Header($message) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  $message" -ForegroundColor Blue
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host ""
}

function Write-Success($message) {
    Write-Host "✓ $message" -ForegroundColor Green
}

function Write-Warning($message) {
    Write-Host "⚠ $message" -ForegroundColor Yellow
}

function Write-Error($message) {
    Write-Host "✗ $message" -ForegroundColor Red
}

function Write-Info($message) {
    Write-Host "ℹ $message" -ForegroundColor Cyan
}

# Check if a command exists
function Test-Command($command) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {
        if (Get-Command $command) { return $true }
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Install Chocolatey package manager
function Install-Chocolatey {
    if (-not (Test-Command "choco")) {
        Write-Info "Installing Chocolatey package manager..."

        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        Write-Success "Chocolatey installed"
    } else {
        Write-Success "Chocolatey already installed"
    }
}

# Install Docker Desktop
function Install-Docker {
    if (-not (Test-Command "docker")) {
        Write-Info "Installing Docker Desktop..."

        # Check Windows version and features
        $osVersion = [System.Environment]::OSVersion.Version
        Write-Info "Windows version: $($osVersion.Major).$($osVersion.Minor).$($osVersion.Build)"

        # Enable required Windows features
        Write-Info "Enabling required Windows features..."

        # Enable WSL
        try {
            dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
            Write-Success "WSL feature enabled"
        } catch {
            Write-Warning "Could not enable WSL feature (may already be enabled)"
        }

        # Enable Virtual Machine Platform
        try {
            dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
            Write-Success "Virtual Machine Platform enabled"
        } catch {
            Write-Warning "Could not enable Virtual Machine Platform (may already be enabled)"
        }

        # Download Docker Desktop
        Write-Info "Downloading Docker Desktop..."
        $dockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
        $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

        try {
            Invoke-WebRequest -Uri $dockerUrl -OutFile $installerPath -UseBasicParsing
            Write-Success "Docker Desktop downloaded"
        } catch {
            Write-Error "Failed to download Docker Desktop"
            throw
        }

        # Install Docker Desktop
        Write-Info "Installing Docker Desktop (this may take several minutes)..."
        Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet", "--accept-license" -Wait

        # Clean up
        Remove-Item $installerPath -Force

        Write-Success "Docker Desktop installed"
        Write-Warning "A system restart may be required"
        Write-Info "After restart, Docker Desktop will start automatically"

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    } else {
        Write-Success "Docker already installed"
    }
}

# Wait for Docker to be ready
function Wait-ForDocker {
    Write-Info "Waiting for Docker to be ready..."

    $maxAttempts = 30
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        try {
            $result = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Docker is running"
                return $true
            }
        } catch {
            # Docker not ready yet
        }

        $attempt++
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
    }

    Write-Host ""
    return $false
}

# Start Docker Desktop
function Start-DockerDesktop {
    Write-Info "Starting Docker Desktop..."

    # Find Docker Desktop executable
    $dockerDesktopPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
    )

    $dockerDesktopPath = $null
    foreach ($path in $dockerDesktopPaths) {
        if (Test-Path $path) {
            $dockerDesktopPath = $path
            break
        }
    }

    if ($dockerDesktopPath) {
        Start-Process -FilePath $dockerDesktopPath
        Write-Info "Docker Desktop starting..."

        if (Wait-ForDocker) {
            return $true
        }
    }

    Write-Warning "Please start Docker Desktop manually and re-run this script"
    return $false
}

# Verify Docker installation
function Test-DockerInstallation {
    Write-Info "Verifying Docker installation..."

    try {
        $dockerVersion = docker --version
        Write-Success "Docker CLI: $dockerVersion"
    } catch {
        Write-Error "Docker CLI not found"
        return $false
    }

    try {
        $composeVersion = docker compose version
        Write-Success "Docker Compose: $composeVersion"
    } catch {
        Write-Error "Docker Compose not found"
        return $false
    }

    try {
        docker info | Out-Null
        Write-Success "Docker daemon is running"
    } catch {
        Write-Warning "Docker daemon is not running"

        if (-not (Start-DockerDesktop)) {
            return $false
        }
    }

    return $true
}

# Install Git (needed for some operations)
function Install-Git {
    if (-not (Test-Command "git")) {
        Write-Info "Installing Git..."
        choco install git -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Success "Git installed"
    } else {
        Write-Success "Git already installed"
    }
}

# Start the application
function Start-Application {
    Write-Header "Starting SSE Notification System"

    # Navigate to project directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectDir = Split-Path -Parent $scriptDir
    Set-Location $projectDir

    Write-Info "Project directory: $projectDir"

    # Stop any existing containers
    Write-Info "Stopping any existing containers..."
    docker compose down 2>$null

    # Build and start
    Write-Info "Building and starting services..."
    docker compose up --build -d

    # Wait for services to be ready
    Write-Info "Waiting for services to be healthy..."
    Start-Sleep -Seconds 5

    # Check health
    foreach ($port in @(3001, 3002, 3003)) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:$port/health" -TimeoutSec 5
            if ($response.status -eq "ok") {
                Write-Success "Server on port $port is healthy"
            }
        } catch {
            Write-Warning "Server on port $port may still be starting"
        }
    }

    Write-Header "Setup Complete!"

    Write-Host "The SSE Notification System is now running!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access the application:" -ForegroundColor White
    Write-Host "  Test UI:        " -NoNewline; Write-Host "http://localhost:3000" -ForegroundColor Cyan
    Write-Host "  Dashboard:      " -NoNewline; Write-Host "http://localhost:3000/dashboard.html" -ForegroundColor Cyan
    Write-Host "  Health Check:   " -NoNewline; Write-Host "http://localhost:3000/health" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Individual nodes (bypass load balancer):" -ForegroundColor White
    Write-Host "  Server 1:       " -NoNewline; Write-Host "http://localhost:3001/health" -ForegroundColor Cyan
    Write-Host "  Server 2:       " -NoNewline; Write-Host "http://localhost:3002/health" -ForegroundColor Cyan
    Write-Host "  Server 3:       " -NoNewline; Write-Host "http://localhost:3003/health" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor White
    Write-Host "  docker compose logs -f     " -ForegroundColor Yellow -NoNewline; Write-Host "# View logs"
    Write-Host "  docker compose down        " -ForegroundColor Yellow -NoNewline; Write-Host "# Stop all services"
    Write-Host "  docker compose restart     " -ForegroundColor Yellow -NoNewline; Write-Host "# Restart services"
    Write-Host ""

    # Open browser
    Write-Info "Opening browser..."
    Start-Process "http://localhost:3000"
}

# Main execution
function Main {
    Write-Header "SSE Notification System - Local Setup (Windows)"

    if (-not (Test-Administrator)) {
        Write-Error "This script must be run as Administrator"
        Write-Info "Right-click PowerShell and select 'Run as Administrator'"
        exit 1
    }

    # Install dependencies
    Install-Chocolatey
    Install-Git
    Install-Docker

    # Verify Docker
    if (-not (Test-DockerInstallation)) {
        Write-Error "Docker installation verification failed"
        Write-Info "Please restart your computer and run this script again"
        exit 1
    }

    # Start application
    Start-Application
}

# Run main function
Main

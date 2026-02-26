#######################################################################
# SSE Notification System - Azure Infrastructure
# Terraform configuration for Azure deployment
#######################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

  # Uncomment for remote state storage
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "terraformstate"
  #   container_name       = "tfstate"
  #   key                  = "sse-notification.tfstate"
  # }
}

# ═══════════════════════════════════════════════════════════════
# Variables
# ═══════════════════════════════════════════════════════════════

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "sse-notification-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "min_replicas" {
  description = "Minimum number of Container App replicas"
  type        = number
  default     = 3
}

variable "max_replicas" {
  description = "Maximum number of Container App replicas"
  type        = number
  default     = 100
}

# ═══════════════════════════════════════════════════════════════
# Provider Configuration
# ═══════════════════════════════════════════════════════════════

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ═══════════════════════════════════════════════════════════════
# Resource Group
# ═══════════════════════════════════════════════════════════════

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    Application = "sse-notification"
  }
}

# ═══════════════════════════════════════════════════════════════
# Virtual Network
# ═══════════════════════════════════════════════════════════════

resource "azurerm_virtual_network" "vnet" {
  name                = "sse-notification-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet" "container_apps" {
  name                 = "container-apps-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "redis" {
  name                 = "redis-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

# ═══════════════════════════════════════════════════════════════
# Azure Cache for Redis
# ═══════════════════════════════════════════════════════════════

resource "azurerm_redis_cache" "redis" {
  name                = "sse-notification-redis-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  capacity            = 1
  family              = "C"
  sku_name            = "Standard"
  enable_non_ssl_port = true
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_policy = "volatile-lru"
  }

  tags = {
    Environment = var.environment
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# ═══════════════════════════════════════════════════════════════
# Azure Database for PostgreSQL Flexible Server
# ═══════════════════════════════════════════════════════════════

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "sse-notification-db-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "16"
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = "sseapp"
  administrator_password = random_password.db_password.result
  zone                   = "1"

  storage_mb   = 32768
  storage_tier = "P4"

  sku_name = "B_Standard_B1ms"  # Change to GP_Standard_D2s_v3 for production

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false  # Set to true for production

  tags = {
    Environment = var.environment
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "database" {
  name      = "sseapp"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# ═══════════════════════════════════════════════════════════════
# Container Registry
# ═══════════════════════════════════════════════════════════════

resource "azurerm_container_registry" "acr" {
  name                = "ssenotificationacr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Log Analytics Workspace
# ═══════════════════════════════════════════════════════════════

resource "azurerm_log_analytics_workspace" "logs" {
  name                = "sse-notification-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Container Apps Environment
# ═══════════════════════════════════════════════════════════════

resource "azurerm_container_app_environment" "env" {
  name                       = "sse-notification-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  infrastructure_subnet_id = azurerm_subnet.container_apps.id

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Container App
# ═══════════════════════════════════════════════════════════════

resource "azurerm_container_app" "app" {
  name                         = "sse-notification-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "sse-app"
      image  = "${azurerm_container_registry.acr.login_server}/sse-notification:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "PORT"
        value = "3000"
      }

      env {
        name  = "REDIS_URL"
        value = "redis://:${azurerm_redis_cache.redis.primary_access_key}@${azurerm_redis_cache.redis.hostname}:${azurerm_redis_cache.redis.port}"
      }

      env {
        name  = "REDIS_TLS"
        value = "false"
      }

      env {
        name  = "HEARTBEAT_INTERVAL"
        value = "30000"
      }

      env {
        name  = "MAX_CONNECTIONS_PER_SERVER"
        value = "50000"
      }

      env {
        name  = "INBOX_TTL_SECONDS"
        value = "604800"
      }

      env {
        name  = "EVENT_STREAM_MAXLEN"
        value = "500"
      }

      env {
        name  = "EVENT_STREAM_TTL"
        value = "3600"
      }

      env {
        name  = "RATE_LIMIT_MAX"
        value = "100"
      }

      env {
        name  = "RATE_LIMIT_WINDOW_SECONDS"
        value = "60"
      }

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }

      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }

      env {
        name  = "JWT_EXPIRES_IN"
        value = "7d"
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 3000

        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 3000

        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
      }
    }

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = 100
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  registry {
    server               = azurerm_container_registry.acr.login_server
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.acr.admin_password
  }

  secret {
    name  = "database-url"
    value = "postgresql://sseapp:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/sseapp?sslmode=require"
  }

  secret {
    name  = "jwt-secret"
    value = random_password.jwt_secret.result
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [
    azurerm_redis_cache.redis,
    azurerm_postgresql_flexible_server.postgres,
    azurerm_postgresql_flexible_server_database.database,
  ]
}

# ═══════════════════════════════════════════════════════════════
# Outputs
# ═══════════════════════════════════════════════════════════════

output "container_app_url" {
  description = "Container App URL"
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "acr_login_server" {
  description = "Container Registry login server"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_username" {
  description = "Container Registry username"
  value       = azurerm_container_registry.acr.admin_username
}

output "acr_password" {
  description = "Container Registry password"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

output "redis_hostname" {
  description = "Redis hostname"
  value       = azurerm_redis_cache.redis.hostname
}

output "redis_port" {
  description = "Redis port"
  value       = azurerm_redis_cache.redis.port
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.rg.name
}

output "postgres_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "postgres_admin_login" {
  description = "PostgreSQL admin username"
  value       = azurerm_postgresql_flexible_server.postgres.administrator_login
}

output "postgres_admin_password" {
  description = "PostgreSQL admin password"
  value       = random_password.db_password.result
  sensitive   = true
}

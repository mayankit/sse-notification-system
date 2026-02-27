#######################################################################
# ChatPulse - Azure Infrastructure (Terraform)
# Uses the common interface modules for consistent cloud deployment
#######################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ═══════════════════════════════════════════════════════════════
# Variables (Using Common Interface)
# ═══════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "sse-notification"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "sse-notification-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "container_config" {
  description = "Container configuration"
  type = object({
    image          = string
    port           = number
    cpu            = number
    memory         = number
    min_instances  = number
    max_instances  = number
    health_path    = string
    timeout        = number
  })
}

variable "scaling_config" {
  description = "Auto-scaling configuration"
  type = object({
    cpu_target_percent    = number
    memory_target_percent = number
    scale_in_cooldown     = number
    scale_out_cooldown    = number
  })
}

variable "database_config" {
  description = "Database configuration"
  type = object({
    name                = string
    engine_version      = string
    instance_class      = string
    storage_gb          = number
    max_storage_gb      = number
    multi_az            = bool
    backup_retention    = number
    deletion_protection = bool
  })
}

variable "redis_config" {
  description = "Redis configuration"
  type = object({
    version           = string
    instance_class    = string
    memory_gb         = number
    high_availability = bool
    tls_enabled       = bool
    maxmemory_policy  = string
  })
}

variable "app_env_vars" {
  description = "Application environment variables"
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Alert notification email"
  type        = string
  default     = "alerts@example.com"
}

variable "alerts" {
  description = "Alert definitions"
  type = list(object({
    name        = string
    description = string
    metric      = string
    threshold   = number
    operator    = string
    period      = number
    severity    = string
  }))
  default = []
}

variable "dashboard_config" {
  description = "Dashboard configuration"
  type = object({
    enabled = bool
    widgets = list(object({
      title   = string
      type    = string
      metrics = list(string)
      width   = number
      height  = number
    }))
  })
  default = {
    enabled = true
    widgets = []
  }
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
# Instance Class Mapping (Interface -> Azure)
# ═══════════════════════════════════════════════════════════════

locals {
  db_instance_class_map = {
    small  = "B_Standard_B1ms"
    medium = "GP_Standard_D2s_v3"
    large  = "GP_Standard_D4s_v3"
  }

  redis_sku_map = {
    small  = { capacity = 0, family = "C", sku_name = "Standard" }
    medium = { capacity = 1, family = "C", sku_name = "Standard" }
    large  = { capacity = 3, family = "C", sku_name = "Premium" }
  }

  # Convert millicores to Azure format (e.g., 0.5, 1, 2)
  container_cpu = var.container_config.cpu / 1000
}

# ═══════════════════════════════════════════════════════════════
# Random Passwords
# ═══════════════════════════════════════════════════════════════

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
# Resource Group
# ═══════════════════════════════════════════════════════════════

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    Application = var.project_name
  }
}

# ═══════════════════════════════════════════════════════════════
# Virtual Network
# ═══════════════════════════════════════════════════════════════

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.project_name}-vnet"
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
# Azure Cache for Redis (Implements Cache Interface)
# ═══════════════════════════════════════════════════════════════

resource "azurerm_redis_cache" "redis" {
  name                = "${var.project_name}-redis-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  capacity            = local.redis_sku_map[var.redis_config.instance_class].capacity
  family              = local.redis_sku_map[var.redis_config.instance_class].family
  sku_name            = local.redis_sku_map[var.redis_config.instance_class].sku_name
  enable_non_ssl_port = !var.redis_config.tls_enabled
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_policy = var.redis_config.maxmemory_policy
  }

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Azure Database for PostgreSQL (Implements Database Interface)
# ═══════════════════════════════════════════════════════════════

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "${var.project_name}-db-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = var.database_config.engine_version
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = "sseapp"
  administrator_password = random_password.db_password.result
  zone                   = "1"

  storage_mb   = var.database_config.storage_gb * 1024
  storage_tier = "P4"

  sku_name = local.db_instance_class_map[var.database_config.instance_class]

  backup_retention_days        = var.database_config.backup_retention
  geo_redundant_backup_enabled = var.database_config.multi_az

  tags = {
    Environment = var.environment
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "database" {
  name      = var.database_config.name
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
  name                = "${var.project_name}-logs"
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
  name                       = "${var.project_name}-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  infrastructure_subnet_id = azurerm_subnet.container_apps.id

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Container App (Implements Compute Interface)
# ═══════════════════════════════════════════════════════════════

resource "azurerm_container_app" "app" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  template {
    min_replicas = var.container_config.min_instances
    max_replicas = var.container_config.max_instances

    container {
      name   = "app"
      image  = "${azurerm_container_registry.acr.login_server}/${var.project_name}:latest"
      cpu    = local.container_cpu
      memory = "${var.container_config.memory / 1024}Gi"

      dynamic "env" {
        for_each = var.app_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "REDIS_URL"
        value = "redis://:${azurerm_redis_cache.redis.primary_access_key}@${azurerm_redis_cache.redis.hostname}:${azurerm_redis_cache.redis.port}"
      }

      env {
        name  = "REDIS_TLS"
        value = tostring(var.redis_config.tls_enabled)
      }

      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }

      env {
        name        = "JWT_SECRET"
        secret_name = "jwt-secret"
      }

      liveness_probe {
        transport = "HTTP"
        path      = var.container_config.health_path
        port      = var.container_config.port

        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      readiness_probe {
        transport = "HTTP"
        path      = var.container_config.health_path
        port      = var.container_config.port

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
    target_port      = var.container_config.port
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
    value = "postgresql://sseapp:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/${var.database_config.name}?sslmode=require"
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
# Monitoring Module
# ═══════════════════════════════════════════════════════════════

module "monitoring" {
  source = "../modules/monitoring"

  # Common interface
  project_name = var.project_name
  environment  = var.environment
  alert_email  = var.alert_email
  alerts       = var.alerts
  dashboard_config = var.dashboard_config

  # Azure-specific
  azure_enabled             = true
  azure_resource_group_name = azurerm_resource_group.rg.name
  azure_location            = var.location
  azure_container_app_id    = azurerm_container_app.app.id
  azure_postgres_id         = azurerm_postgresql_flexible_server.postgres.id
  azure_redis_id            = azurerm_redis_cache.redis.id
  azure_log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  # Disable other providers
  aws_enabled = false
  gcp_enabled = false

  providers = {
    aws     = aws
    google  = google
    azurerm = azurerm
  }
}

# Dummy providers for module (required but not used)
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "google" {
  project = "dummy"
  region  = "us-central1"
}

# ═══════════════════════════════════════════════════════════════
# Outputs (Unified Interface)
# ═══════════════════════════════════════════════════════════════

output "service_url" {
  description = "Application URL"
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = "${azurerm_postgresql_flexible_server.postgres.fqdn}:5432"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${azurerm_redis_cache.redis.hostname}:${azurerm_redis_cache.redis.port}"
}

output "acr_login_server" {
  description = "Container Registry login server"
  value       = azurerm_container_registry.acr.login_server
}

output "monitoring" {
  description = "Monitoring configuration"
  value       = module.monitoring.monitoring_summary
}

output "dashboard_url" {
  description = "Monitoring dashboard URL"
  value       = module.monitoring.dashboard_url
}

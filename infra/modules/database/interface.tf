#######################################################################
# Database Module Interface
# Common interface for managed PostgreSQL across all clouds
# Implementations: AWS RDS, GCP Cloud SQL, Azure Database for PostgreSQL
#######################################################################

# ═══════════════════════════════════════════════════════════════
# Input Variables (Common Interface)
# ═══════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Database Configuration (provider-agnostic)
variable "database_config" {
  description = "Database configuration"
  type = object({
    name                = string
    engine_version      = string
    instance_class      = string  # small, medium, large (mapped to provider-specific)
    storage_gb          = number
    max_storage_gb      = number
    multi_az            = bool
    backup_retention    = number  # days
    deletion_protection = bool
  })
  default = {
    name                = "sseapp"
    engine_version      = "16"
    instance_class      = "small"
    storage_gb          = 20
    max_storage_gb      = 100
    multi_az            = false
    backup_retention    = 7
    deletion_protection = false
  }
}

# Credentials (auto-generated and stored in cloud secret manager)
variable "admin_username" {
  description = "Database admin username"
  type        = string
  default     = "sseapp"
}

# Network Configuration
variable "network_config" {
  description = "Network configuration for database"
  type = object({
    vpc_id        = string
    subnet_ids    = list(string)
    allowed_cidrs = list(string)
  })
  default = {
    vpc_id        = ""
    subnet_ids    = []
    allowed_cidrs = []
  }
}

# ═══════════════════════════════════════════════════════════════
# Instance Class Mapping
# ═══════════════════════════════════════════════════════════════

# Provider-specific mappings are defined in each implementation:
# small  -> AWS: db.t3.micro,  GCP: db-f1-micro,   Azure: B_Standard_B1ms
# medium -> AWS: db.t3.medium, GCP: db-custom-2-4096, Azure: GP_Standard_D2s_v3
# large  -> AWS: db.r5.large,  GCP: db-custom-4-8192, Azure: GP_Standard_D4s_v3

# ═══════════════════════════════════════════════════════════════
# Output Interface (Common outputs all implementations must provide)
# ═══════════════════════════════════════════════════════════════

# These outputs are defined in provider-specific files:
# - connection_string: Full connection string
# - host: Database hostname
# - port: Database port
# - database_name: Database name
# - secret_arn: ARN/ID of secret containing credentials

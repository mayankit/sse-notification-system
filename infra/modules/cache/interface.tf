#######################################################################
# Cache Module Interface
# Common interface for managed Redis across all clouds
# Implementations: AWS ElastiCache, GCP Memorystore, Azure Cache for Redis
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

# Redis Configuration (provider-agnostic)
variable "redis_config" {
  description = "Redis configuration"
  type = object({
    version         = string
    instance_class  = string  # small, medium, large (mapped to provider-specific)
    memory_gb       = number
    high_availability = bool
    tls_enabled     = bool
    maxmemory_policy = string
  })
  default = {
    version         = "7.0"
    instance_class  = "small"
    memory_gb       = 1
    high_availability = true
    tls_enabled     = false
    maxmemory_policy = "volatile-lru"
  }
}

# Network Configuration
variable "network_config" {
  description = "Network configuration for Redis"
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

# Provider-specific mappings:
# small  -> AWS: cache.t3.micro,  GCP: BASIC (1GB),     Azure: C0 Standard
# medium -> AWS: cache.t3.medium, GCP: STANDARD_HA (1GB), Azure: C1 Standard
# large  -> AWS: cache.r5.large,  GCP: STANDARD_HA (5GB), Azure: C3 Premium

# ═══════════════════════════════════════════════════════════════
# Output Interface (Common outputs all implementations must provide)
# ═══════════════════════════════════════════════════════════════

# These outputs are defined in provider-specific files:
# - connection_url: Redis connection URL (redis://host:port)
# - host: Redis hostname
# - port: Redis port
# - tls_enabled: Whether TLS is enabled

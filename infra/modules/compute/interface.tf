#######################################################################
# Compute Module Interface
# Common interface for container orchestration across all clouds
# Implementations: AWS ECS Fargate, GCP Cloud Run, Azure Container Apps
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

# Container Configuration (provider-agnostic)
variable "container_config" {
  description = "Container configuration"
  type = object({
    image          = string
    port           = number
    cpu            = number    # In millicores (1000 = 1 CPU)
    memory         = number    # In MB
    min_instances  = number
    max_instances  = number
    health_path    = string
    timeout        = number    # In seconds (for long-running connections like SSE)
  })
  default = {
    image          = ""
    port           = 3000
    cpu            = 1000
    memory         = 512
    min_instances  = 3
    max_instances  = 100
    health_path    = "/health"
    timeout        = 3600      # 1 hour for SSE
  }
}

# Environment Variables (secrets handled separately)
variable "env_vars" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

# Secrets (provider will inject from its secret manager)
variable "secrets" {
  description = "Secret names to inject (will be fetched from cloud secret manager)"
  type        = list(string)
  default     = []
}

# Auto-scaling Configuration
variable "scaling_config" {
  description = "Auto-scaling configuration"
  type = object({
    cpu_target_percent    = number
    memory_target_percent = number
    scale_in_cooldown     = number  # seconds
    scale_out_cooldown    = number  # seconds
  })
  default = {
    cpu_target_percent    = 70
    memory_target_percent = 70
    scale_in_cooldown     = 60
    scale_out_cooldown    = 60
  }
}

# Network Configuration
variable "network_config" {
  description = "Network configuration"
  type = object({
    public_access    = bool
    vpc_id           = string
    subnet_ids       = list(string)
    security_groups  = list(string)
  })
  default = {
    public_access    = true
    vpc_id           = ""
    subnet_ids       = []
    security_groups  = []
  }
}

# ═══════════════════════════════════════════════════════════════
# Output Interface (Common outputs all implementations must provide)
# ═══════════════════════════════════════════════════════════════

# These outputs are defined in provider-specific files:
# - service_url: Public URL to access the service
# - service_id: Provider-specific service identifier
# - service_name: Service name

#######################################################################
# Common Infrastructure Configuration
# Cloud-agnostic configuration that works across AWS, GCP, and Azure
#
# This file defines the "interface" - the same config works on any cloud
#######################################################################

# ═══════════════════════════════════════════════════════════════
# Project Identification
# ═══════════════════════════════════════════════════════════════

project_name = "chatpulse"
environment  = "production"

# ═══════════════════════════════════════════════════════════════
# Container/Compute Configuration
# Mapped to: ECS Fargate (AWS), Cloud Run (GCP), Container Apps (Azure)
# ═══════════════════════════════════════════════════════════════

container_config = {
  image          = "chatpulse:latest"  # Provider will prefix with registry
  port           = 3000
  cpu            = 1000      # millicores (1000 = 1 vCPU)
  memory         = 512       # MB
  min_instances  = 3
  max_instances  = 100
  health_path    = "/health"
  timeout        = 3600      # 1 hour for SSE connections
}

# ═══════════════════════════════════════════════════════════════
# Auto-scaling Configuration
# ═══════════════════════════════════════════════════════════════

scaling_config = {
  cpu_target_percent    = 70
  memory_target_percent = 70
  scale_in_cooldown     = 60
  scale_out_cooldown    = 60
}

# ═══════════════════════════════════════════════════════════════
# Database Configuration
# Mapped to: RDS PostgreSQL (AWS), Cloud SQL (GCP), Azure Database (Azure)
# ═══════════════════════════════════════════════════════════════

database_config = {
  name                = "sseapp"
  engine_version      = "16"
  instance_class      = "small"   # small | medium | large
  storage_gb          = 20
  max_storage_gb      = 100
  multi_az            = false     # Set true for production
  backup_retention    = 7         # days
  deletion_protection = false     # Set true for production
}

# ═══════════════════════════════════════════════════════════════
# Redis/Cache Configuration
# Mapped to: ElastiCache (AWS), Memorystore (GCP), Azure Cache (Azure)
# ═══════════════════════════════════════════════════════════════

redis_config = {
  version           = "7.0"
  instance_class    = "small"     # small | medium | large
  memory_gb         = 1
  high_availability = true
  tls_enabled       = false
  maxmemory_policy  = "volatile-lru"
}

# ═══════════════════════════════════════════════════════════════
# Application Environment Variables
# These are injected into all containers regardless of cloud
# ═══════════════════════════════════════════════════════════════

app_env_vars = {
  PORT                       = "3000"
  HEARTBEAT_INTERVAL         = "30000"
  MAX_CONNECTIONS_PER_SERVER = "50000"
  INBOX_TTL_SECONDS          = "604800"
  EVENT_STREAM_MAXLEN        = "500"
  EVENT_STREAM_TTL           = "3600"
  RATE_LIMIT_MAX             = "100"
  RATE_LIMIT_WINDOW_SECONDS  = "60"
  JWT_EXPIRES_IN             = "7d"
}

# ═══════════════════════════════════════════════════════════════
# Monitoring Configuration
# (imported from monitoring.tfvars)
# ═══════════════════════════════════════════════════════════════

alert_email = "alerts@example.com"

# ═══════════════════════════════════════════════════════════════
# Instance Class Mapping Reference
# ═══════════════════════════════════════════════════════════════

# Database instance_class mapping:
# | Class  | AWS             | GCP               | Azure              |
# |--------|-----------------|-------------------|--------------------|
# | small  | db.t3.micro     | db-f1-micro       | B_Standard_B1ms    |
# | medium | db.t3.medium    | db-custom-2-4096  | GP_Standard_D2s_v3 |
# | large  | db.r5.large     | db-custom-4-8192  | GP_Standard_D4s_v3 |

# Redis instance_class mapping:
# | Class  | AWS              | GCP           | Azure       |
# |--------|------------------|---------------|-------------|
# | small  | cache.t3.micro   | BASIC         | C0 Standard |
# | medium | cache.t3.medium  | STANDARD_HA   | C1 Standard |
# | large  | cache.r5.large   | STANDARD_HA   | C3 Premium  |

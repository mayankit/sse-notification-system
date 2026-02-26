#######################################################################
# SSE Notification System - GCP Infrastructure (Terraform)
# Uses the common interface modules for consistent cloud deployment
#######################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
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

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
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

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ═══════════════════════════════════════════════════════════════
# Instance Class Mapping (Interface -> GCP)
# ═══════════════════════════════════════════════════════════════

locals {
  db_instance_class_map = {
    small  = "db-f1-micro"
    medium = "db-custom-2-4096"
    large  = "db-custom-4-8192"
  }

  redis_tier_map = {
    small  = "BASIC"
    medium = "STANDARD_HA"
    large  = "STANDARD_HA"
  }

  # Convert millicores to Cloud Run format (e.g., "1000m" or "1")
  cloud_run_cpu = var.container_config.cpu >= 1000 ? "${var.container_config.cpu / 1000}" : "${var.container_config.cpu}m"
}

# ═══════════════════════════════════════════════════════════════
# Enable Required APIs
# ═══════════════════════════════════════════════════════════════

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "redis.googleapis.com",
    "sqladmin.googleapis.com",
    "vpcaccess.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "servicenetworking.googleapis.com",
    "monitoring.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ═══════════════════════════════════════════════════════════════
# Random Passwords
# ═══════════════════════════════════════════════════════════════

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# ═══════════════════════════════════════════════════════════════
# VPC Network
# ═══════════════════════════════════════════════════════════════

resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true
}

resource "google_vpc_access_connector" "connector" {
  name          = "${var.project_name}-vpc-conn"
  project       = var.project_id
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc.name

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Cloud Memorystore Redis (Implements Cache Interface)
# ═══════════════════════════════════════════════════════════════

resource "google_redis_instance" "redis" {
  name               = "${var.project_name}-redis"
  project            = var.project_id
  region             = var.region
  tier               = local.redis_tier_map[var.redis_config.instance_class]
  memory_size_gb     = var.redis_config.memory_gb
  redis_version      = "REDIS_${replace(var.redis_config.version, ".", "_")}"
  display_name       = "${var.project_name} Redis"
  authorized_network = google_compute_network.vpc.id

  redis_configs = {
    maxmemory-policy = var.redis_config.maxmemory_policy
  }

  labels = {
    environment = var.environment
    app         = var.project_name
  }

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Private Service Access (for Cloud SQL)
# ═══════════════════════════════════════════════════════════════

resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.project_name}-private-ip"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id

  depends_on = [google_project_service.apis]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Cloud SQL PostgreSQL (Implements Database Interface)
# ═══════════════════════════════════════════════════════════════

resource "google_sql_database_instance" "postgres" {
  name             = "${var.project_name}-db"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_${var.database_config.engine_version}"

  settings {
    tier              = local.db_instance_class_map[var.database_config.instance_class]
    availability_type = var.database_config.multi_az ? "REGIONAL" : "ZONAL"
    disk_size         = var.database_config.storage_gb
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      binary_log_enabled = false
    }

    maintenance_window {
      day  = 7
      hour = 4
    }
  }

  deletion_protection = var.database_config.deletion_protection

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection,
  ]
}

resource "google_sql_database" "database" {
  name     = var.database_config.name
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
}

resource "google_sql_user" "user" {
  name     = "sseapp"
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  password = random_password.db_password.result
}

# ═══════════════════════════════════════════════════════════════
# Secret Manager (Implements Secret Interface)
# ═══════════════════════════════════════════════════════════════

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "${var.project_name}-jwt-secret"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = random_password.jwt_secret.result
}

# ═══════════════════════════════════════════════════════════════
# Artifact Registry
# ═══════════════════════════════════════════════════════════════

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.project_name
  description   = "Docker repository for ${var.project_name}"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Service Account
# ═══════════════════════════════════════════════════════════════

resource "google_service_account" "cloud_run" {
  account_id   = "${var.project_name}-run"
  display_name = "${var.project_name} Cloud Run Service Account"
  project      = var.project_id
}

resource "google_secret_manager_secret_iam_member" "jwt_secret_access" {
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ═══════════════════════════════════════════════════════════════
# Cloud Run Service (Implements Compute Interface)
# ═══════════════════════════════════════════════════════════════

resource "google_cloud_run_v2_service" "app" {
  name     = "${var.project_name}-app"
  location = var.region
  project  = var.project_id

  template {
    scaling {
      min_instance_count = var.container_config.min_instances
      max_instance_count = var.container_config.max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.project_name}/app:latest"

      ports {
        container_port = var.container_config.port
      }

      dynamic "env" {
        for_each = var.app_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
      }

      env {
        name  = "REDIS_TLS"
        value = tostring(var.redis_config.tls_enabled)
      }

      env {
        name  = "DATABASE_URL"
        value = "postgresql://sseapp:${random_password.db_password.result}@${google_sql_database_instance.postgres.private_ip_address}:5432/${var.database_config.name}"
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = local.cloud_run_cpu
          memory = "${var.container_config.memory}Mi"
        }
        cpu_idle = false
      }

      startup_probe {
        http_get {
          path = var.container_config.health_path
          port = var.container_config.port
        }
        initial_delay_seconds = 10
        period_seconds        = 3
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = var.container_config.health_path
          port = var.container_config.port
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    timeout = "${var.container_config.timeout}s"

    service_account = google_service_account.cloud_run.email

    labels = {
      environment = var.environment
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.repo,
    google_redis_instance.redis,
    google_sql_database_instance.postgres,
    google_sql_database.database,
    google_sql_user.user,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ═══════════════════════════════════════════════════════════════
# Global Load Balancer
# ═══════════════════════════════════════════════════════════════

resource "google_compute_region_network_endpoint_group" "neg" {
  name                  = "${var.project_name}-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.app.name
  }
}

resource "google_compute_backend_service" "backend" {
  name        = "${var.project_name}-backend"
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = var.container_config.timeout

  backend {
    group = google_compute_region_network_endpoint_group.neg.id
  }

  # No session affinity - the whole point!
  session_affinity = "NONE"
}

resource "google_compute_url_map" "urlmap" {
  name            = "${var.project_name}-urlmap"
  project         = var.project_id
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "proxy" {
  name    = "${var.project_name}-proxy"
  project = var.project_id
  url_map = google_compute_url_map.urlmap.id
}

resource "google_compute_global_forwarding_rule" "frontend" {
  name       = "${var.project_name}-frontend"
  project    = var.project_id
  target     = google_compute_target_http_proxy.proxy.id
  port_range = "80"
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

  # GCP-specific
  gcp_enabled          = true
  gcp_project_id       = var.project_id
  gcp_cloud_run_service = google_cloud_run_v2_service.app.name
  gcp_cloud_sql_instance = google_sql_database_instance.postgres.name
  gcp_redis_instance     = google_redis_instance.redis.name

  # Disable other providers
  aws_enabled   = false
  azure_enabled = false

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

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ═══════════════════════════════════════════════════════════════
# Outputs (Unified Interface)
# ═══════════════════════════════════════════════════════════════

output "service_url" {
  description = "Application URL"
  value       = google_cloud_run_v2_service.app.uri
}

output "load_balancer_ip" {
  description = "Global Load Balancer IP"
  value       = google_compute_global_forwarding_rule.frontend.ip_address
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = "${google_sql_database_instance.postgres.private_ip_address}:5432"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
}

output "artifact_registry" {
  description = "Artifact Registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.project_name}"
}

output "monitoring" {
  description = "Monitoring configuration"
  value       = module.monitoring.monitoring_summary
}

output "dashboard_url" {
  description = "Monitoring dashboard URL"
  value       = module.monitoring.dashboard_url
}

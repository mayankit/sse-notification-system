#######################################################################
# SSE Notification System - Google Cloud Platform Infrastructure
# Terraform configuration for GCP deployment
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
  }

  # Uncomment for remote state storage
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "sse-notification-system"
  # }
}

# ═══════════════════════════════════════════════════════════════
# Variables
# ═══════════════════════════════════════════════════════════════

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 3
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 100
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
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ═══════════════════════════════════════════════════════════════
# VPC Network
# ═══════════════════════════════════════════════════════════════

resource "google_compute_network" "vpc" {
  name                    = "sse-notification-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "sse-notification-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true
}

# VPC Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "sse-vpc-connector"
  project       = var.project_id
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc.name

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Cloud Memorystore (Redis)
# ═══════════════════════════════════════════════════════════════

resource "google_redis_instance" "redis" {
  name               = "sse-notification-redis"
  project            = var.project_id
  region             = var.region
  tier               = "STANDARD_HA"
  memory_size_gb     = 1
  redis_version      = "REDIS_7_0"
  display_name       = "SSE Notification Redis"
  authorized_network = google_compute_network.vpc.id

  redis_configs = {
    maxmemory-policy = "volatile-lru"
  }

  labels = {
    environment = var.environment
    app         = "sse-notification"
  }

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Private Service Access (for Cloud SQL)
# ═══════════════════════════════════════════════════════════════

resource "google_compute_global_address" "private_ip_range" {
  name          = "sse-private-ip-range"
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
# Cloud SQL PostgreSQL
# ═══════════════════════════════════════════════════════════════

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "google_sql_database_instance" "postgres" {
  name             = "sse-notification-db"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = "db-f1-micro"  # Change to db-custom-2-4096 for production
    availability_type = "ZONAL"         # Change to REGIONAL for production
    disk_size         = 10
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
      day  = 7  # Sunday
      hour = 4
    }
  }

  deletion_protection = false  # Set to true for production

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc_connection,
  ]
}

resource "google_sql_database" "database" {
  name     = "sseapp"
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
# Secret Manager
# ═══════════════════════════════════════════════════════════════

resource "google_secret_manager_secret" "db_password" {
  secret_id = "sse-db-password"
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
  secret_id = "sse-jwt-secret"
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
  repository_id = "sse-notification"
  description   = "Docker repository for SSE Notification System"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [google_project_service.apis]
}

# ═══════════════════════════════════════════════════════════════
# Cloud Run Service
# ═══════════════════════════════════════════════════════════════

resource "google_cloud_run_v2_service" "sse_app" {
  name     = "sse-notification-app"
  location = var.region
  project  = var.project_id

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/sse-notification/app:latest"

      ports {
        container_port = 3000
      }

      env {
        name  = "PORT"
        value = "3000"
      }

      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.redis.host}:${google_redis_instance.redis.port}"
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
        name  = "DATABASE_URL"
        value = "postgresql://sseapp:${random_password.db_password.result}@${google_sql_database_instance.postgres.private_ip_address}:5432/sseapp"
      }

      env {
        name  = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "JWT_EXPIRES_IN"
        value = "7d"
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle = false  # Keep CPU allocated for SSE
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 3000
        }
        initial_delay_seconds = 10
        period_seconds        = 3
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 3000
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    # Important for SSE: extend request timeout
    timeout = "3600s"

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

# Service account for Cloud Run
resource "google_service_account" "cloud_run" {
  account_id   = "sse-notification-run"
  display_name = "SSE Notification Cloud Run Service Account"
  project      = var.project_id
}

# Grant secret access to Cloud Run service account
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

# Allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.sse_app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ═══════════════════════════════════════════════════════════════
# Global Load Balancer (optional, for custom domain)
# ═══════════════════════════════════════════════════════════════

resource "google_compute_region_network_endpoint_group" "neg" {
  name                  = "sse-notification-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.sse_app.name
  }
}

resource "google_compute_backend_service" "backend" {
  name        = "sse-notification-backend"
  project     = var.project_id
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 3600  # 1 hour timeout for SSE

  backend {
    group = google_compute_region_network_endpoint_group.neg.id
  }

  # No session affinity - the whole point!
  session_affinity = "NONE"
}

resource "google_compute_url_map" "urlmap" {
  name            = "sse-notification-urlmap"
  project         = var.project_id
  default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "proxy" {
  name    = "sse-notification-proxy"
  project = var.project_id
  url_map = google_compute_url_map.urlmap.id
}

resource "google_compute_global_forwarding_rule" "frontend" {
  name       = "sse-notification-frontend"
  project    = var.project_id
  target     = google_compute_target_http_proxy.proxy.id
  port_range = "80"
}

# ═══════════════════════════════════════════════════════════════
# Outputs
# ═══════════════════════════════════════════════════════════════

output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.sse_app.uri
}

output "load_balancer_ip" {
  description = "Global Load Balancer IP"
  value       = google_compute_global_forwarding_rule.frontend.ip_address
}

output "redis_host" {
  description = "Redis host"
  value       = google_redis_instance.redis.host
}

output "redis_port" {
  description = "Redis port"
  value       = google_redis_instance.redis.port
}

output "artifact_registry" {
  description = "Artifact Registry URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/sse-notification"
}

output "database_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.postgres.connection_name
}

output "database_private_ip" {
  description = "Cloud SQL private IP"
  value       = google_sql_database_instance.postgres.private_ip_address
}

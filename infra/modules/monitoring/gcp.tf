#######################################################################
# GCP Cloud Monitoring Implementation
# Implements the monitoring interface for Google Cloud Platform
#######################################################################

# ═══════════════════════════════════════════════════════════════
# GCP-Specific Variables
# ═══════════════════════════════════════════════════════════════

variable "gcp_enabled" {
  description = "Enable GCP Cloud Monitoring"
  type        = bool
  default     = false
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_cloud_run_service" {
  description = "Cloud Run service name"
  type        = string
  default     = ""
}

variable "gcp_cloud_sql_instance" {
  description = "Cloud SQL instance name"
  type        = string
  default     = ""
}

variable "gcp_redis_instance" {
  description = "Memorystore Redis instance name"
  type        = string
  default     = ""
}

# ═══════════════════════════════════════════════════════════════
# Metric Mapping (Interface -> GCP Cloud Monitoring)
# ═══════════════════════════════════════════════════════════════

locals {
  gcp_metric_mapping = {
    cpu = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/container/cpu/utilizations"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\""
    }
    memory = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/container/memory/utilizations"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\""
    }
    errors = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/request_count"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\" AND metric.labels.response_code_class = \"5xx\""
    }
    latency = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/request_latencies"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\""
    }
    requests = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/request_count"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\""
    }
    connections = {
      resource_type = "cloud_run_revision"
      metric_type   = "run.googleapis.com/container/network/received_bytes_count"
      filter_extra  = "resource.labels.service_name = \"${var.gcp_cloud_run_service}\""
    }
    db_cpu = {
      resource_type = "cloudsql_database"
      metric_type   = "cloudsql.googleapis.com/database/cpu/utilization"
      filter_extra  = "resource.labels.database_id = \"${var.gcp_project_id}:${var.gcp_cloud_sql_instance}\""
    }
    db_connections = {
      resource_type = "cloudsql_database"
      metric_type   = "cloudsql.googleapis.com/database/postgresql/num_backends"
      filter_extra  = "resource.labels.database_id = \"${var.gcp_project_id}:${var.gcp_cloud_sql_instance}\""
    }
    redis_memory = {
      resource_type = "redis_instance"
      metric_type   = "redis.googleapis.com/stats/memory/usage_ratio"
      filter_extra  = "resource.labels.instance_id = \"${var.gcp_redis_instance}\""
    }
  }

  gcp_operator_mapping = {
    gt  = "COMPARISON_GT"
    lt  = "COMPARISON_LT"
    gte = "COMPARISON_GT"  # GCP doesn't have GTE, use GT with adjusted threshold
    lte = "COMPARISON_LT"  # GCP doesn't have LTE, use LT with adjusted threshold
  }
}

# ═══════════════════════════════════════════════════════════════
# Notification Channel
# ═══════════════════════════════════════════════════════════════

resource "google_monitoring_notification_channel" "email" {
  count        = var.gcp_enabled ? 1 : 0
  display_name = "${var.project_name} - ${var.environment} Alerts"
  type         = "email"
  project      = var.gcp_project_id

  labels = {
    email_address = var.alert_email
  }
}

# ═══════════════════════════════════════════════════════════════
# Alert Policies (Dynamic based on interface)
# ═══════════════════════════════════════════════════════════════

resource "google_monitoring_alert_policy" "alerts" {
  for_each = var.gcp_enabled ? { for alert in var.alerts : alert.name => alert } : {}

  display_name = "${var.project_name} - ${each.value.description}"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = each.value.description

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"${local.gcp_metric_mapping[each.value.metric].resource_type}\"",
        "metric.type = \"${local.gcp_metric_mapping[each.value.metric].metric_type}\"",
        local.gcp_metric_mapping[each.value.metric].filter_extra
      ])

      duration        = "${each.value.period}s"
      comparison      = local.gcp_operator_mapping[each.value.operator]
      threshold_value = each.value.metric == "cpu" || each.value.metric == "memory" ? each.value.threshold / 100 : each.value.threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = each.value.metric == "errors" ? "ALIGN_RATE" : "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email[0].name]

  alert_strategy {
    auto_close = "604800s"  # 7 days
  }

  user_labels = {
    environment = var.environment
    severity    = each.value.severity
  }
}

# ═══════════════════════════════════════════════════════════════
# GCP Dashboard
# ═══════════════════════════════════════════════════════════════

resource "google_monitoring_dashboard" "main" {
  count          = var.gcp_enabled && var.dashboard_config.enabled ? 1 : 0
  project        = var.gcp_project_id
  dashboard_json = jsonencode({
    displayName = "${var.project_name} - ${var.environment}"
    gridLayout = {
      columns = 2
      widgets = concat(
        [
          {
            title = "Overview"
            text = {
              content = "# ${var.project_name}\nEnvironment: ${var.environment}"
              format  = "MARKDOWN"
            }
          }
        ],
        [
          for widget in var.dashboard_config.widgets : {
            title = widget.title
            xyChart = {
              dataSets = [
                for metric in widget.metrics : {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = join(" AND ", [
                        "resource.type = \"${local.gcp_metric_mapping[metric].resource_type}\"",
                        "metric.type = \"${local.gcp_metric_mapping[metric].metric_type}\""
                      ])
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                } if contains(keys(local.gcp_metric_mapping), metric)
              ]
            }
          }
        ]
      )
    }
  })
}

# ═══════════════════════════════════════════════════════════════
# GCP Outputs
# ═══════════════════════════════════════════════════════════════

output "gcp_notification_channel_id" {
  description = "GCP notification channel ID"
  value       = var.gcp_enabled ? google_monitoring_notification_channel.email[0].name : null
}

output "gcp_dashboard_url" {
  description = "GCP Cloud Monitoring dashboard URL"
  value       = var.gcp_enabled && var.dashboard_config.enabled ? "https://console.cloud.google.com/monitoring/dashboards/builder/${google_monitoring_dashboard.main[0].id}?project=${var.gcp_project_id}" : null
}

output "gcp_alert_policy_ids" {
  description = "GCP alert policy IDs"
  value       = var.gcp_enabled ? [for policy in google_monitoring_alert_policy.alerts : policy.name] : []
}

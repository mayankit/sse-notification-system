#######################################################################
# Monitoring Module Interface
# This defines the common interface for monitoring across all clouds
# Each cloud provider implements this interface with native services
#######################################################################

# ═══════════════════════════════════════════════════════════════
# Input Variables (Common Interface)
# ═══════════════════════════════════════════════════════════════

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "alerts@example.com"
}

# Alert Configuration (provider-agnostic)
variable "alerts" {
  description = "Alert definitions using a cloud-agnostic format"
  type = list(object({
    name        = string
    description = string
    metric      = string  # Standardized metric name (cpu, memory, errors, latency)
    threshold   = number
    operator    = string  # gt, lt, gte, lte
    period      = number  # Evaluation period in seconds
    severity    = string  # critical, warning, info
  }))
  default = [
    {
      name        = "high-cpu"
      description = "CPU utilization exceeded threshold"
      metric      = "cpu"
      threshold   = 80
      operator    = "gt"
      period      = 300
      severity    = "warning"
    },
    {
      name        = "high-memory"
      description = "Memory utilization exceeded threshold"
      metric      = "memory"
      threshold   = 80
      operator    = "gt"
      period      = 300
      severity    = "warning"
    },
    {
      name        = "high-error-rate"
      description = "Error rate exceeded threshold"
      metric      = "errors"
      threshold   = 5
      operator    = "gt"
      period      = 300
      severity    = "critical"
    },
    {
      name        = "high-latency"
      description = "Response latency exceeded threshold"
      metric      = "latency"
      threshold   = 1000  # milliseconds
      operator    = "gt"
      period      = 300
      severity    = "warning"
    }
  ]
}

# Dashboard Configuration (provider-agnostic)
variable "dashboard_config" {
  description = "Dashboard configuration"
  type = object({
    enabled = bool
    widgets = list(object({
      title   = string
      type    = string  # graph, gauge, counter, status
      metrics = list(string)
      width   = number
      height  = number
    }))
  })
  default = {
    enabled = true
    widgets = [
      {
        title   = "CPU & Memory Utilization"
        type    = "graph"
        metrics = ["cpu", "memory"]
        width   = 12
        height  = 6
      },
      {
        title   = "Request Rate & Latency"
        type    = "graph"
        metrics = ["requests", "latency"]
        width   = 12
        height  = 6
      },
      {
        title   = "Error Rate"
        type    = "graph"
        metrics = ["errors"]
        width   = 12
        height  = 6
      },
      {
        title   = "Active Connections"
        type    = "gauge"
        metrics = ["connections"]
        width   = 12
        height  = 6
      }
    ]
  }
}

# ═══════════════════════════════════════════════════════════════
# Output Interface (Common outputs all implementations must provide)
# ═══════════════════════════════════════════════════════════════

# These outputs are defined in provider-specific files:
# - notification_channel_id: ID of the notification channel/topic
# - dashboard_url: URL to the monitoring dashboard
# - alert_ids: List of alert/alarm IDs created

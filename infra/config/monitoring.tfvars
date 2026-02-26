#######################################################################
# Common Monitoring Configuration
# Cloud-agnostic configuration that works across AWS, GCP, and Azure
#######################################################################

# Project identification
project_name = "sse-notification"
environment  = "production"

# Alert notification email
alert_email = "alerts@example.com"

# ═══════════════════════════════════════════════════════════════
# Alert Definitions (Cloud-Agnostic)
# These alerts are automatically translated to each cloud's native format
# ═══════════════════════════════════════════════════════════════

alerts = [
  # Compute Alerts
  {
    name        = "high-cpu"
    description = "CPU utilization exceeded 80%"
    metric      = "cpu"
    threshold   = 80
    operator    = "gt"
    period      = 300
    severity    = "warning"
  },
  {
    name        = "critical-cpu"
    description = "CPU utilization exceeded 95%"
    metric      = "cpu"
    threshold   = 95
    operator    = "gt"
    period      = 180
    severity    = "critical"
  },
  {
    name        = "high-memory"
    description = "Memory utilization exceeded 80%"
    metric      = "memory"
    threshold   = 80
    operator    = "gt"
    period      = 300
    severity    = "warning"
  },
  {
    name        = "critical-memory"
    description = "Memory utilization exceeded 95%"
    metric      = "memory"
    threshold   = 95
    operator    = "gt"
    period      = 180
    severity    = "critical"
  },

  # Application Alerts
  {
    name        = "high-error-rate"
    description = "5xx error rate exceeded threshold"
    metric      = "errors"
    threshold   = 10
    operator    = "gt"
    period      = 300
    severity    = "critical"
  },
  {
    name        = "high-latency"
    description = "Response latency exceeded 1 second"
    metric      = "latency"
    threshold   = 1000
    operator    = "gt"
    period      = 300
    severity    = "warning"
  },

  # Database Alerts
  {
    name        = "db-high-cpu"
    description = "Database CPU utilization exceeded 80%"
    metric      = "db_cpu"
    threshold   = 80
    operator    = "gt"
    period      = 300
    severity    = "warning"
  },
  {
    name        = "db-high-connections"
    description = "Database connections exceeded threshold"
    metric      = "db_connections"
    threshold   = 100
    operator    = "gt"
    period      = 300
    severity    = "warning"
  }
]

# ═══════════════════════════════════════════════════════════════
# Dashboard Configuration
# ═══════════════════════════════════════════════════════════════

dashboard_config = {
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
    },
    {
      title   = "Database Performance"
      type    = "graph"
      metrics = ["db_cpu", "db_connections"]
      width   = 12
      height  = 6
    }
  ]
}

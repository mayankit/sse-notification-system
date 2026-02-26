#######################################################################
# Azure Monitor Implementation
# Implements the monitoring interface for Microsoft Azure
#######################################################################

# ═══════════════════════════════════════════════════════════════
# Azure-Specific Variables
# ═══════════════════════════════════════════════════════════════

variable "azure_enabled" {
  description = "Enable Azure Monitor"
  type        = bool
  default     = false
}

variable "azure_resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = ""
}

variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "East US"
}

variable "azure_container_app_id" {
  description = "Container App resource ID"
  type        = string
  default     = ""
}

variable "azure_postgres_id" {
  description = "PostgreSQL Flexible Server resource ID"
  type        = string
  default     = ""
}

variable "azure_redis_id" {
  description = "Azure Cache for Redis resource ID"
  type        = string
  default     = ""
}

variable "azure_log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Container Apps"
  type        = string
  default     = ""
}

# ═══════════════════════════════════════════════════════════════
# Metric Mapping (Interface -> Azure Monitor)
# ═══════════════════════════════════════════════════════════════

locals {
  azure_metric_mapping = {
    cpu = {
      resource_id = var.azure_container_app_id
      metric_name = "UsageNanoCores"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Average"
    }
    memory = {
      resource_id = var.azure_container_app_id
      metric_name = "WorkingSetBytes"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Average"
    }
    errors = {
      resource_id = var.azure_container_app_id
      metric_name = "Requests"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Total"
      # Note: Filter by response code in actual implementation
    }
    latency = {
      resource_id = var.azure_container_app_id
      metric_name = "RequestDuration"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Average"
    }
    requests = {
      resource_id = var.azure_container_app_id
      metric_name = "Requests"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Total"
    }
    connections = {
      resource_id = var.azure_container_app_id
      metric_name = "Replicas"
      namespace   = "microsoft.app/containerapps"
      aggregation = "Average"
    }
    db_cpu = {
      resource_id = var.azure_postgres_id
      metric_name = "cpu_percent"
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      aggregation = "Average"
    }
    db_connections = {
      resource_id = var.azure_postgres_id
      metric_name = "active_connections"
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      aggregation = "Average"
    }
    redis_memory = {
      resource_id = var.azure_redis_id
      metric_name = "usedmemorypercentage"
      namespace   = "Microsoft.Cache/redis"
      aggregation = "Average"
    }
  }

  azure_operator_mapping = {
    gt  = "GreaterThan"
    lt  = "LessThan"
    gte = "GreaterThanOrEqual"
    lte = "LessThanOrEqual"
  }

  azure_severity_mapping = {
    critical = 0
    warning  = 2
    info     = 3
  }
}

# ═══════════════════════════════════════════════════════════════
# Action Group for Notifications
# ═══════════════════════════════════════════════════════════════

resource "azurerm_monitor_action_group" "alerts" {
  count               = var.azure_enabled ? 1 : 0
  name                = "${var.project_name}-${var.environment}-alerts"
  resource_group_name = var.azure_resource_group_name
  short_name          = substr("${var.project_name}", 0, 12)

  email_receiver {
    name                    = "primary"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Metric Alerts (Dynamic based on interface)
# ═══════════════════════════════════════════════════════════════

resource "azurerm_monitor_metric_alert" "alerts" {
  for_each = var.azure_enabled ? { for alert in var.alerts : alert.name => alert } : {}

  name                = "${var.project_name}-${var.environment}-${each.value.name}"
  resource_group_name = var.azure_resource_group_name
  scopes              = [local.azure_metric_mapping[each.value.metric].resource_id]
  description         = each.value.description
  severity            = local.azure_severity_mapping[each.value.severity]
  frequency           = "PT1M"
  window_size         = "PT${ceil(each.value.period / 60)}M"

  criteria {
    metric_namespace = local.azure_metric_mapping[each.value.metric].namespace
    metric_name      = local.azure_metric_mapping[each.value.metric].metric_name
    aggregation      = local.azure_metric_mapping[each.value.metric].aggregation
    operator         = local.azure_operator_mapping[each.value.operator]
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }

  tags = {
    Environment = var.environment
    Severity    = each.value.severity
  }
}

# ═══════════════════════════════════════════════════════════════
# Azure Dashboard
# ═══════════════════════════════════════════════════════════════

resource "azurerm_portal_dashboard" "main" {
  count               = var.azure_enabled && var.dashboard_config.enabled ? 1 : 0
  name                = "${var.project_name}-${var.environment}-dashboard"
  resource_group_name = var.azure_resource_group_name
  location            = var.azure_location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = merge(
          {
            "0" = {
              position = { x = 0, y = 0, rowSpan = 1, colSpan = 6 }
              metadata = {
                type = "Extension/HubsExtension/PartType/MarkdownPart"
                settings = {
                  content = {
                    settings = {
                      content = "# ${var.project_name}\n## Environment: ${var.environment}"
                    }
                  }
                }
              }
            }
          },
          {
            for idx, widget in var.dashboard_config.widgets :
            tostring(idx + 1) => {
              position = {
                x       = (idx % 2) * 6
                y       = 1 + floor(idx / 2) * 4
                rowSpan = 4
                colSpan = 6
              }
              metadata = {
                type = "Extension/HubsExtension/PartType/MonitorChartPart"
                settings = {
                  content = {
                    options = {
                      chart = {
                        title = widget.title
                        metrics = [
                          for metric in widget.metrics : {
                            resourceMetadata = {
                              id = local.azure_metric_mapping[metric].resource_id
                            }
                            name            = local.azure_metric_mapping[metric].metric_name
                            aggregationType = 4  # Average
                            namespace       = local.azure_metric_mapping[metric].namespace
                          } if contains(keys(local.azure_metric_mapping), metric)
                        ]
                      }
                    }
                  }
                }
              }
            }
          }
        )
      }
    }
    metadata = {
      model = {}
    }
  })

  tags = {
    Environment = var.environment
  }
}

# ═══════════════════════════════════════════════════════════════
# Azure Outputs
# ═══════════════════════════════════════════════════════════════

output "azure_action_group_id" {
  description = "Azure Monitor action group ID"
  value       = var.azure_enabled ? azurerm_monitor_action_group.alerts[0].id : null
}

output "azure_dashboard_url" {
  description = "Azure Portal dashboard URL"
  value       = var.azure_enabled && var.dashboard_config.enabled ? "https://portal.azure.com/#@/dashboard/arm${azurerm_portal_dashboard.main[0].id}" : null
}

output "azure_alert_ids" {
  description = "Azure Monitor metric alert IDs"
  value       = var.azure_enabled ? [for alert in azurerm_monitor_metric_alert.alerts : alert.id] : []
}

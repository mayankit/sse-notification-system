#######################################################################
# Unified Monitoring Outputs
# Aggregates outputs from all cloud providers into a common interface
#######################################################################

# ═══════════════════════════════════════════════════════════════
# Unified Outputs (Cloud-Agnostic)
# ═══════════════════════════════════════════════════════════════

output "notification_channel_id" {
  description = "Notification channel ID (provider-specific)"
  value = coalesce(
    var.aws_enabled ? aws_sns_topic.alerts[0].arn : null,
    var.gcp_enabled ? google_monitoring_notification_channel.email[0].name : null,
    var.azure_enabled ? azurerm_monitor_action_group.alerts[0].id : null,
    "no-provider-enabled"
  )
}

output "dashboard_url" {
  description = "Monitoring dashboard URL"
  value = coalesce(
    var.aws_enabled && var.dashboard_config.enabled ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-${var.environment}" : null,
    var.gcp_enabled && var.dashboard_config.enabled ? "https://console.cloud.google.com/monitoring/dashboards" : null,
    var.azure_enabled && var.dashboard_config.enabled ? "https://portal.azure.com/#blade/HubsExtension/BrowseDashboardBlade" : null,
    "no-dashboard-configured"
  )
}

output "active_provider" {
  description = "Currently active cloud provider for monitoring"
  value = var.aws_enabled ? "aws" : (var.gcp_enabled ? "gcp" : (var.azure_enabled ? "azure" : "none"))
}

output "alerts_configured" {
  description = "Number of alerts configured"
  value       = length(var.alerts)
}

output "monitoring_summary" {
  description = "Summary of monitoring configuration"
  value = {
    provider      = var.aws_enabled ? "aws" : (var.gcp_enabled ? "gcp" : (var.azure_enabled ? "azure" : "none"))
    environment   = var.environment
    alerts_count  = length(var.alerts)
    dashboard     = var.dashboard_config.enabled
    alert_email   = var.alert_email
  }
}

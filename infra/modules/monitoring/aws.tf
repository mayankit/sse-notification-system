#######################################################################
# AWS CloudWatch Implementation
# Implements the monitoring interface for AWS
#######################################################################

# ═══════════════════════════════════════════════════════════════
# AWS-Specific Variables
# ═══════════════════════════════════════════════════════════════

variable "aws_enabled" {
  description = "Enable AWS CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_ecs_cluster_name" {
  description = "ECS cluster name for metrics"
  type        = string
  default     = ""
}

variable "aws_ecs_service_name" {
  description = "ECS service name for metrics"
  type        = string
  default     = ""
}

variable "aws_alb_arn_suffix" {
  description = "ALB ARN suffix for metrics"
  type        = string
  default     = ""
}

variable "aws_target_group_arn_suffix" {
  description = "Target group ARN suffix for metrics"
  type        = string
  default     = ""
}

variable "aws_rds_instance_id" {
  description = "RDS instance identifier for metrics"
  type        = string
  default     = ""
}

# ═══════════════════════════════════════════════════════════════
# Metric Mapping (Interface -> AWS CloudWatch)
# ═══════════════════════════════════════════════════════════════

locals {
  aws_metric_mapping = {
    cpu = {
      namespace   = "AWS/ECS"
      metric_name = "CPUUtilization"
      dimensions = {
        ClusterName = var.aws_ecs_cluster_name
        ServiceName = var.aws_ecs_service_name
      }
    }
    memory = {
      namespace   = "AWS/ECS"
      metric_name = "MemoryUtilization"
      dimensions = {
        ClusterName = var.aws_ecs_cluster_name
        ServiceName = var.aws_ecs_service_name
      }
    }
    errors = {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions = {
        LoadBalancer = var.aws_alb_arn_suffix
      }
    }
    latency = {
      namespace   = "AWS/ApplicationELB"
      metric_name = "TargetResponseTime"
      dimensions = {
        LoadBalancer = var.aws_alb_arn_suffix
      }
    }
    requests = {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions = {
        LoadBalancer = var.aws_alb_arn_suffix
      }
    }
    connections = {
      namespace   = "AWS/ApplicationELB"
      metric_name = "ActiveConnectionCount"
      dimensions = {
        LoadBalancer = var.aws_alb_arn_suffix
      }
    }
    db_cpu = {
      namespace   = "AWS/RDS"
      metric_name = "CPUUtilization"
      dimensions = {
        DBInstanceIdentifier = var.aws_rds_instance_id
      }
    }
    db_connections = {
      namespace   = "AWS/RDS"
      metric_name = "DatabaseConnections"
      dimensions = {
        DBInstanceIdentifier = var.aws_rds_instance_id
      }
    }
  }

  aws_operator_mapping = {
    gt  = "GreaterThanThreshold"
    lt  = "LessThanThreshold"
    gte = "GreaterThanOrEqualToThreshold"
    lte = "LessThanOrEqualToThreshold"
  }
}

# ═══════════════════════════════════════════════════════════════
# SNS Topic for Notifications
# ═══════════════════════════════════════════════════════════════

resource "aws_sns_topic" "alerts" {
  count = var.aws_enabled ? 1 : 0
  name  = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.aws_enabled ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ═══════════════════════════════════════════════════════════════
# CloudWatch Alarms (Dynamic based on interface)
# ═══════════════════════════════════════════════════════════════

resource "aws_cloudwatch_metric_alarm" "alerts" {
  for_each = var.aws_enabled ? { for alert in var.alerts : alert.name => alert } : {}

  alarm_name          = "${var.project_name}-${var.environment}-${each.value.name}"
  alarm_description   = each.value.description
  comparison_operator = local.aws_operator_mapping[each.value.operator]
  evaluation_periods  = ceil(each.value.period / 60)
  threshold           = each.value.threshold

  namespace   = local.aws_metric_mapping[each.value.metric].namespace
  metric_name = local.aws_metric_mapping[each.value.metric].metric_name
  dimensions  = local.aws_metric_mapping[each.value.metric].dimensions

  period    = 60
  statistic = each.value.metric == "errors" ? "Sum" : "Average"

  alarm_actions = [aws_sns_topic.alerts[0].arn]
  ok_actions    = [aws_sns_topic.alerts[0].arn]

  tags = {
    Name        = "${var.project_name}-${each.value.name}"
    Environment = var.environment
    Severity    = each.value.severity
  }
}

# ═══════════════════════════════════════════════════════════════
# CloudWatch Dashboard
# ═══════════════════════════════════════════════════════════════

resource "aws_cloudwatch_dashboard" "main" {
  count          = var.aws_enabled && var.dashboard_config.enabled ? 1 : 0
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 1
          properties = {
            markdown = "# ${var.project_name} - ${var.environment}\nReal-time monitoring dashboard"
          }
        }
      ],
      [
        for idx, widget in var.dashboard_config.widgets : {
          type   = "metric"
          x      = (idx % 2) * 12
          y      = 1 + floor(idx / 2) * 6
          width  = widget.width
          height = widget.height
          properties = {
            title   = widget.title
            region  = var.aws_region
            metrics = [
              for metric in widget.metrics : [
                local.aws_metric_mapping[metric].namespace,
                local.aws_metric_mapping[metric].metric_name,
                [for k, v in local.aws_metric_mapping[metric].dimensions : k][0],
                [for k, v in local.aws_metric_mapping[metric].dimensions : v][0]
              ] if contains(keys(local.aws_metric_mapping), metric)
            ]
            period = 60
            stat   = "Average"
          }
        }
      ]
    )
  })
}

# ═══════════════════════════════════════════════════════════════
# AWS Outputs
# ═══════════════════════════════════════════════════════════════

output "aws_notification_channel_arn" {
  description = "AWS SNS topic ARN for alerts"
  value       = var.aws_enabled ? aws_sns_topic.alerts[0].arn : null
}

output "aws_dashboard_url" {
  description = "AWS CloudWatch dashboard URL"
  value       = var.aws_enabled && var.dashboard_config.enabled ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-${var.environment}" : null
}

output "aws_alert_arns" {
  description = "AWS CloudWatch alarm ARNs"
  value       = var.aws_enabled ? [for alarm in aws_cloudwatch_metric_alarm.alerts : alarm.arn] : []
}

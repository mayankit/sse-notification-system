#######################################################################
# ChatPulse - AWS Infrastructure (Terraform)
# Uses the common interface modules for consistent cloud deployment
#######################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
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

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ═══════════════════════════════════════════════════════════════
# Instance Class Mapping (Interface -> AWS)
# ═══════════════════════════════════════════════════════════════

locals {
  db_instance_class_map = {
    small  = "db.t3.micro"
    medium = "db.t3.medium"
    large  = "db.r5.large"
  }

  redis_instance_class_map = {
    small  = "cache.t3.micro"
    medium = "cache.t3.medium"
    large  = "cache.r5.large"
  }

  # Convert CPU millicores to Fargate units (256, 512, 1024, 2048, 4096)
  fargate_cpu_map = {
    256  = 256
    512  = 512
    1000 = 1024
    1024 = 1024
    2000 = 2048
    2048 = 2048
    4000 = 4096
    4096 = 4096
  }

  fargate_cpu = lookup(local.fargate_cpu_map, var.container_config.cpu, 1024)
}

# ═══════════════════════════════════════════════════════════════
# Random Suffixes for Unique Names
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
# VPC Configuration
# ═══════════════════════════════════════════════════════════════

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ═══════════════════════════════════════════════════════════════
# Security Groups
# ═══════════════════════════════════════════════════════════════

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.container_config.port
    to_port         = var.container_config.port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }
}

# ═══════════════════════════════════════════════════════════════
# Secrets Manager (Implements Secret Interface)
# ═══════════════════════════════════════════════════════════════

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project_name}/${var.environment}/db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "sseapp"
    password = random_password.db_password.result
  })
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "${var.project_name}/${var.environment}/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

# ═══════════════════════════════════════════════════════════════
# ElastiCache Redis (Implements Cache Interface)
# ═══════════════════════════════════════════════════════════════

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = var.redis_config.version
  node_type            = local.redis_instance_class_map[var.redis_config.instance_class]
  num_cache_nodes      = 1
  port                 = 6379
  security_group_ids   = [aws_security_group.redis.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis.name

  parameter_group_name = "default.redis7"
}

# ═══════════════════════════════════════════════════════════════
# RDS PostgreSQL (Implements Database Interface)
# ═══════════════════════════════════════════════════════════════

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = var.database_config.engine_version
  instance_class = local.db_instance_class_map[var.database_config.instance_class]

  allocated_storage     = var.database_config.storage_gb
  max_allocated_storage = var.database_config.max_storage_gb
  storage_type          = "gp3"

  db_name  = var.database_config.name
  username = "sseapp"
  password = random_password.db_password.result

  multi_az               = var.database_config.multi_az
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = var.database_config.backup_retention
  deletion_protection     = var.database_config.deletion_protection
  skip_final_snapshot     = !var.database_config.deletion_protection
}

# ═══════════════════════════════════════════════════════════════
# ECR Repository
# ═══════════════════════════════════════════════════════════════

resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ═══════════════════════════════════════════════════════════════
# ECS Cluster and Service (Implements Compute Interface)
# ═══════════════════════════════════════════════════════════════

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        aws_secretsmanager_secret.db_credentials.arn,
        aws_secretsmanager_secret.jwt_secret.arn
      ]
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.fargate_cpu
  memory                   = var.container_config.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name  = "app"
    image = "${aws_ecr_repository.app.repository_url}:latest"

    portMappings = [{
      containerPort = var.container_config.port
      protocol      = "tcp"
    }]

    environment = concat(
      [for k, v in var.app_env_vars : { name = k, value = v }],
      [
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}" },
        { name = "REDIS_TLS", value = tostring(var.redis_config.tls_enabled) },
        { name = "DB_HOST", value = aws_db_instance.postgres.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.postgres.port) },
        { name = "DB_NAME", value = var.database_config.name }
      ]
    )

    secrets = [
      { name = "DB_USERNAME", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::" },
      { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt_secret.arn }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_config.port}${var.container_config.health_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ═══════════════════════════════════════════════════════════════
# Application Load Balancer
# ═══════════════════════════════════════════════════════════════

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  idle_timeout = var.container_config.timeout
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.container_config.port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = var.container_config.health_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  # No sticky sessions - the whole point!
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ═══════════════════════════════════════════════════════════════
# ECS Service
# ═══════════════════════════════════════════════════════════════

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.container_config.min_instances
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_config.port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]
}

# ═══════════════════════════════════════════════════════════════
# Auto Scaling
# ═══════════════════════════════════════════════════════════════

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.container_config.max_instances
  min_capacity       = var.container_config.min_instances
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.scaling_config.cpu_target_percent
    scale_in_cooldown  = var.scaling_config.scale_in_cooldown
    scale_out_cooldown = var.scaling_config.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${var.project_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.scaling_config.memory_target_percent
    scale_in_cooldown  = var.scaling_config.scale_in_cooldown
    scale_out_cooldown = var.scaling_config.scale_out_cooldown
  }
}

# ═══════════════════════════════════════════════════════════════
# Monitoring Module
# ═══════════════════════════════════════════════════════════════

module "monitoring" {
  source = "../../modules/monitoring"

  # Common interface
  project_name = var.project_name
  environment  = var.environment
  alert_email  = var.alert_email
  alerts       = var.alerts
  dashboard_config = var.dashboard_config

  # AWS-specific
  aws_enabled              = true
  aws_region               = var.aws_region
  aws_ecs_cluster_name     = aws_ecs_cluster.main.name
  aws_ecs_service_name     = aws_ecs_service.app.name
  aws_alb_arn_suffix       = aws_lb.main.arn_suffix
  aws_target_group_arn_suffix = aws_lb_target_group.app.arn_suffix
  aws_rds_instance_id      = aws_db_instance.postgres.identifier

  # Disable other providers
  gcp_enabled   = false
  azure_enabled = false

  providers = {
    aws     = aws
    google  = google
    azurerm = azurerm
  }
}

# Dummy providers for module (required but not used)
provider "google" {
  project = "dummy"
  region  = "us-central1"
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
  value       = "http://${aws_lb.main.dns_name}"
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = "${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}"
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "ecr_repository" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "monitoring" {
  description = "Monitoring configuration"
  value       = module.monitoring.monitoring_summary
}

output "dashboard_url" {
  description = "Monitoring dashboard URL"
  value       = module.monitoring.dashboard_url
}

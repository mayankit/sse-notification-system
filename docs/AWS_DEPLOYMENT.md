# AWS Deployment Guide

Deploy the SSE Notification System to AWS using CDK (Cloud Development Kit) with a single command.

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                      AWS Cloud                       │
                    │                                                      │
    Internet        │   ┌─────────────────────────────────────────────┐   │
        │           │   │              VPC (3 AZs)                     │   │
        │           │   │                                              │   │
        ▼           │   │   ┌───────────────────────────────────┐     │   │
┌───────────────┐   │   │   │        Public Subnets              │     │   │
│    Users      │───┼───┼──▶│   ┌─────────────────────────┐     │     │   │
└───────────────┘   │   │   │   │  Application Load       │     │     │   │
                    │   │   │   │  Balancer (ALB)         │     │     │   │
                    │   │   │   └───────────┬─────────────┘     │     │   │
                    │   │   └───────────────┼───────────────────┘     │   │
                    │   │                   │                          │   │
                    │   │   ┌───────────────▼───────────────────┐     │   │
                    │   │   │        Private Subnets             │     │   │
                    │   │   │                                    │     │   │
                    │   │   │   ┌─────────┐ ┌─────────┐ ┌─────┐ │     │   │
                    │   │   │   │ ECS     │ │ ECS     │ │ ECS │ │     │   │
                    │   │   │   │ Task 1  │ │ Task 2  │ │ ... │ │     │   │
                    │   │   │   └────┬────┘ └────┬────┘ └──┬──┘ │     │   │
                    │   │   │        │           │          │    │     │   │
                    │   │   └────────┼───────────┼──────────┼────┘     │   │
                    │   │            │           │          │          │   │
                    │   │   ┌────────▼───────────▼──────────▼────┐     │   │
                    │   │   │        Isolated Subnets             │     │   │
                    │   │   │                                     │     │   │
                    │   │   │   ┌─────────────────────────────┐  │     │   │
                    │   │   │   │    ElastiCache Redis        │  │     │   │
                    │   │   │   │    (cache.t3.medium)        │  │     │   │
                    │   │   │   └─────────────────────────────┘  │     │   │
                    │   │   │                                     │     │   │
                    │   │   │   ┌─────────────────────────────┐  │     │   │
                    │   │   │   │    RDS PostgreSQL           │  │     │   │
                    │   │   │   │    (db.t3.micro)            │  │     │   │
                    │   │   │   └─────────────────────────────┘  │     │   │
                    │   │   │                                     │     │   │
                    │   │   └─────────────────────────────────────┘     │   │
                    │   │                                              │   │
                    │   └──────────────────────────────────────────────┘   │
                    │                                                      │
                    └──────────────────────────────────────────────────────┘
```

## Components

| Component | AWS Service | Purpose |
|-----------|-------------|---------|
| Load Balancer | ALB | Distributes traffic, no sticky sessions |
| Compute | ECS Fargate | Serverless containers |
| Database | RDS PostgreSQL | User authentication & storage |
| Redis | ElastiCache | Pub/sub, sessions, queues |
| Networking | VPC | Isolated network with 3 AZs |
| Secrets | Secrets Manager | Store DB credentials, JWT secret |
| Logs | CloudWatch Logs | Centralized logging |
| Scaling | ECS Auto Scaling | CPU/Memory based scaling |

## Quick Deploy (One Command)

```bash
cd infra/aws
chmod +x deploy.sh
./deploy.sh deploy
```

## Prerequisites

### 1. Install AWS CLI

**macOS:**
```bash
brew install awscli
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows:**
```powershell
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter your Access Key ID
# Enter your Secret Access Key
# Enter default region (e.g., us-east-1)
# Enter output format (json)
```

Or use environment variables:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

### 3. Install Node.js

```bash
# macOS
brew install node@20

# Linux
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 4. Install Docker

Required for building the container image. See [Local Setup Guide](./LOCAL_SETUP.md).

## Deployment Options

### Basic Deployment

```bash
./deploy.sh deploy
```

### Custom Configuration

```bash
# Deploy to different region
AWS_REGION=eu-west-1 ./deploy.sh deploy

# Deploy with more instances
DESIRED_COUNT=5 ./deploy.sh deploy

# Combine options
AWS_REGION=us-west-2 DESIRED_COUNT=10 ENVIRONMENT=staging ./deploy.sh deploy
```

### Available Commands

```bash
./deploy.sh deploy     # Deploy the stack
./deploy.sh destroy    # Destroy the stack
./deploy.sh status     # Show stack status
./deploy.sh diff       # Preview changes
./deploy.sh synth      # Generate CloudFormation template
./deploy.sh bootstrap  # Bootstrap CDK (first-time only)
```

## Manual Deployment

If you prefer step-by-step deployment:

```bash
cd infra/aws

# Install dependencies
npm install

# Bootstrap CDK (first-time only)
npx cdk bootstrap aws://ACCOUNT_ID/REGION

# Preview changes
npx cdk diff

# Deploy
npx cdk deploy --all --require-approval never
```

## Post-Deployment

### Get Application URL

```bash
aws cloudformation describe-stacks \
  --stack-name SSENotificationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text
```

### Verify Health

```bash
# Get the ALB URL
ALB_URL=$(aws cloudformation describe-stacks \
  --stack-name SSENotificationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

# Check health
curl $ALB_URL/health
```

### View Logs

```bash
# Stream logs
aws logs tail /ecs/SSENotificationStack --follow

# View recent logs
aws logs tail /ecs/SSENotificationStack --since 1h
```

### Scale Service

```bash
aws ecs update-service \
  --cluster SSENotificationStack-cluster \
  --service SSENotificationStack-service \
  --desired-count 5
```

## Cost Estimation

| Resource | Configuration | Est. Monthly Cost |
|----------|--------------|-------------------|
| ECS Fargate | 3 tasks x 0.25 vCPU, 0.5 GB | ~$30 |
| ElastiCache | cache.t3.medium | ~$45 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| ALB | Standard | ~$20 |
| NAT Gateway | 1 gateway | ~$35 |
| Data Transfer | 100 GB | ~$10 |
| Secrets Manager | 3 secrets | ~$2 |
| **Total** | | **~$157/month** |

*Costs vary by region and usage. Use AWS Pricing Calculator for accurate estimates.*

## Scaling to 10M Users

For high-scale deployment, modify `lib/sse-notification-stack.ts`:

```typescript
// Increase ECS task size
const taskDefinition = new ecs.FargateTaskDefinition(this, 'SSETaskDef', {
  memoryLimitMiB: 2048,  // 2 GB
  cpu: 1024,              // 1 vCPU
});

// Use Redis Cluster
const redisCluster = new elasticache.CfnReplicationGroup(this, 'RedisCluster', {
  replicationGroupDescription: 'Redis cluster for SSE',
  engine: 'redis',
  cacheNodeType: 'cache.r6g.xlarge',
  numNodeGroups: 3,           // 3 shards
  replicasPerNodeGroup: 2,    // 2 replicas per shard
  automaticFailoverEnabled: true,
  multiAzEnabled: true,
});

// Use larger RDS instance with Multi-AZ
const database = new rds.DatabaseInstance(this, 'PostgresDB', {
  instanceType: ec2.InstanceType.of(
    ec2.InstanceClass.R6G,
    ec2.InstanceSize.LARGE
  ),
  multiAz: true,
  deletionProtection: true,
});

// Increase auto-scaling limits
const scaling = service.autoScaleTaskCount({
  minCapacity: 10,
  maxCapacity: 1000,
});
```

## Security Best Practices

1. **Enable HTTPS**: Add ACM certificate and configure ALB listener
2. **Use Secrets Manager**: Already configured for Redis credentials
3. **VPC Isolation**: Redis in isolated subnets, no public access
4. **Security Groups**: Minimal required ports only
5. **IAM Roles**: Least privilege for ECS tasks

### Adding HTTPS

```typescript
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';

// Import existing certificate or create new one
const certificate = acm.Certificate.fromCertificateArn(
  this, 'Certificate',
  'arn:aws:acm:us-east-1:123456789:certificate/xxx'
);

// Add HTTPS listener
alb.addListener('HTTPSListener', {
  port: 443,
  certificates: [certificate],
  defaultTargetGroups: [targetGroup],
});

// Redirect HTTP to HTTPS
alb.addRedirect({
  sourcePort: 80,
  sourceProtocol: elbv2.ApplicationProtocol.HTTP,
  targetPort: 443,
  targetProtocol: elbv2.ApplicationProtocol.HTTPS,
});
```

## Troubleshooting

### Deployment Failed

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name SSENotificationStack \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### ECS Tasks Not Starting

```bash
# Check task status
aws ecs list-tasks --cluster SSENotificationStack-cluster

# Describe task
aws ecs describe-tasks \
  --cluster SSENotificationStack-cluster \
  --tasks TASK_ARN
```

### Redis Connection Failed

```bash
# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*Redis*"
```

## Cleanup

```bash
./deploy.sh destroy
```

This will remove all AWS resources created by the stack.

## Next Steps

- [GCP Deployment Guide](./GCP_DEPLOYMENT.md)
- [Azure Deployment Guide](./AZURE_DEPLOYMENT.md)

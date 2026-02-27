import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecrAssets from 'aws-cdk-lib/aws-ecr-assets';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';
import * as path from 'path';

interface SSENotificationStackProps extends cdk.StackProps {
  environment: string;
  desiredCount: number;
}

export class SSENotificationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: SSENotificationStackProps) {
    super(scope, id, props);

    const { environment, desiredCount } = props;

    // ═══════════════════════════════════════════════════════════════
    // VPC Configuration
    // ═══════════════════════════════════════════════════════════════
    const vpc = new ec2.Vpc(this, 'SSEVpc', {
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // ═══════════════════════════════════════════════════════════════
    // Security Groups
    // ═══════════════════════════════════════════════════════════════
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP'
    );
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS'
    );

    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'ECSSecurityGroup', {
      vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });
    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(3000),
      'Allow traffic from ALB'
    );

    const redisSecurityGroup = new ec2.SecurityGroup(this, 'RedisSecurityGroup', {
      vpc,
      description: 'Security group for ElastiCache Redis',
      allowAllOutbound: false,
    });
    redisSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcp(6379),
      'Allow Redis from ECS'
    );

    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RDSSecurityGroup', {
      vpc,
      description: 'Security group for RDS PostgreSQL',
      allowAllOutbound: false,
    });
    rdsSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcp(5432),
      'Allow PostgreSQL from ECS'
    );

    // ═══════════════════════════════════════════════════════════════
    // ElastiCache Redis Cluster
    // ═══════════════════════════════════════════════════════════════
    const redisSubnetGroup = new elasticache.CfnSubnetGroup(this, 'RedisSubnetGroup', {
      description: 'Subnet group for Redis cluster',
      subnetIds: vpc.selectSubnets({
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      }).subnetIds,
      cacheSubnetGroupName: `${id}-redis-subnet-group`.toLowerCase(),
    });

    const redisCluster = new elasticache.CfnCacheCluster(this, 'RedisCluster', {
      engine: 'redis',
      cacheNodeType: 'cache.t3.medium',
      numCacheNodes: 1,
      clusterName: `${id}-redis`.toLowerCase(),
      vpcSecurityGroupIds: [redisSecurityGroup.securityGroupId],
      cacheSubnetGroupName: redisSubnetGroup.ref,
      engineVersion: '7.0',
      port: 6379,
      preferredMaintenanceWindow: 'sun:05:00-sun:06:00',
      autoMinorVersionUpgrade: true,
    });
    redisCluster.addDependency(redisSubnetGroup);

    // Store Redis endpoint in Secrets Manager
    const redisSecret = new secretsmanager.Secret(this, 'RedisSecret', {
      secretName: `${id}/redis-url`,
      description: 'Redis connection URL for ChatPulse',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          host: redisCluster.attrRedisEndpointAddress,
          port: redisCluster.attrRedisEndpointPort,
        }),
        generateStringKey: 'dummy', // Required but not used
      },
    });

    // ═══════════════════════════════════════════════════════════════
    // RDS PostgreSQL Database
    // ═══════════════════════════════════════════════════════════════
    const dbCredentials = new secretsmanager.Secret(this, 'DBCredentials', {
      secretName: `${id}/db-credentials`,
      description: 'PostgreSQL database credentials',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          username: 'sseapp',
        }),
        generateStringKey: 'password',
        excludePunctuation: true,
        passwordLength: 32,
      },
    });

    const dbSubnetGroup = new rds.SubnetGroup(this, 'DBSubnetGroup', {
      description: 'Subnet group for PostgreSQL database',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    const database = new rds.DatabaseInstance(this, 'PostgresDB', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16_2,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MICRO
      ),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      subnetGroup: dbSubnetGroup,
      securityGroups: [rdsSecurityGroup],
      databaseName: 'sseapp',
      credentials: rds.Credentials.fromSecret(dbCredentials),
      multiAz: false, // Set to true for production
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      deletionProtection: false, // Set to true for production
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Change to RETAIN for production
      backupRetention: cdk.Duration.days(7),
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
    });

    // JWT Secret
    const jwtSecret = new secretsmanager.Secret(this, 'JWTSecret', {
      secretName: `${id}/jwt-secret`,
      description: 'JWT signing secret for authentication',
      generateSecretString: {
        excludePunctuation: true,
        passwordLength: 64,
      },
    });

    // ═══════════════════════════════════════════════════════════════
    // ECS Cluster
    // ═══════════════════════════════════════════════════════════════
    const cluster = new ecs.Cluster(this, 'SSECluster', {
      vpc,
      clusterName: `${id}-cluster`,
      containerInsights: true,
    });

    // ═══════════════════════════════════════════════════════════════
    // Docker Image
    // ═══════════════════════════════════════════════════════════════
    const dockerImage = new ecrAssets.DockerImageAsset(this, 'SSEAppImage', {
      directory: path.join(__dirname, '../../../'),
      file: 'Dockerfile',
      exclude: ['infra', 'node_modules', '.git'],
    });

    // ═══════════════════════════════════════════════════════════════
    // Task Definition
    // ═══════════════════════════════════════════════════════════════
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'SSETaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      runtimePlatform: {
        cpuArchitecture: ecs.CpuArchitecture.ARM64,
        operatingSystemFamily: ecs.OperatingSystemFamily.LINUX,
      },
    });

    // Grant secrets access
    redisSecret.grantRead(taskDefinition.taskRole);
    dbCredentials.grantRead(taskDefinition.taskRole);
    jwtSecret.grantRead(taskDefinition.taskRole);

    // Log group
    const logGroup = new logs.LogGroup(this, 'SSELogGroup', {
      logGroupName: `/ecs/${id}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Container definition
    const container = taskDefinition.addContainer('sse-app', {
      image: ecs.ContainerImage.fromDockerImageAsset(dockerImage),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'sse-app',
        logGroup,
      }),
      environment: {
        PORT: '3000',
        REDIS_URL: `redis://${redisCluster.attrRedisEndpointAddress}:${redisCluster.attrRedisEndpointPort}`,
        REDIS_TLS: 'false',
        HEARTBEAT_INTERVAL: '30000',
        MAX_CONNECTIONS_PER_SERVER: '50000',
        INBOX_TTL_SECONDS: '604800',
        EVENT_STREAM_MAXLEN: '500',
        EVENT_STREAM_TTL: '3600',
        RATE_LIMIT_MAX: '100',
        RATE_LIMIT_WINDOW_SECONDS: '60',
        JWT_EXPIRES_IN: '7d',
        DB_HOST: database.dbInstanceEndpointAddress,
        DB_PORT: database.dbInstanceEndpointPort,
        DB_NAME: 'sseapp',
      },
      secrets: {
        DB_USERNAME: ecs.Secret.fromSecretsManager(dbCredentials, 'username'),
        DB_PASSWORD: ecs.Secret.fromSecretsManager(dbCredentials, 'password'),
        JWT_SECRET: ecs.Secret.fromSecretsManager(jwtSecret),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    container.addPortMappings({
      containerPort: 3000,
      protocol: ecs.Protocol.TCP,
    });

    // ═══════════════════════════════════════════════════════════════
    // Application Load Balancer
    // ═══════════════════════════════════════════════════════════════
    const alb = new elbv2.ApplicationLoadBalancer(this, 'SSELoadBalancer', {
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      loadBalancerName: `${id}-alb`,
    });

    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'SSETargetGroup', {
      vpc,
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      // Important for SSE: disable stickiness
      stickinessCookieDuration: undefined,
    });

    // Listener with extended idle timeout for SSE
    const listener = alb.addListener('SSEListener', {
      port: 80,
      defaultTargetGroups: [targetGroup],
    });

    // Set idle timeout to 1 hour for SSE connections
    alb.setAttribute('idle_timeout.timeout_seconds', '3600');

    // ═══════════════════════════════════════════════════════════════
    // ECS Service
    // ═══════════════════════════════════════════════════════════════
    const service = new ecs.FargateService(this, 'SSEService', {
      cluster,
      taskDefinition,
      desiredCount,
      securityGroups: [ecsSecurityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      serviceName: `${id}-service`,
      circuitBreaker: {
        rollback: true,
      },
      deploymentController: {
        type: ecs.DeploymentControllerType.ECS,
      },
      minHealthyPercent: 50,
      maxHealthyPercent: 200,
    });

    // Attach to target group
    service.attachToApplicationTargetGroup(targetGroup);

    // Auto-scaling
    const scaling = service.autoScaleTaskCount({
      minCapacity: desiredCount,
      maxCapacity: desiredCount * 10,
    });

    scaling.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(60),
      scaleOutCooldown: cdk.Duration.seconds(60),
    });

    scaling.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(60),
      scaleOutCooldown: cdk.Duration.seconds(60),
    });

    // ═══════════════════════════════════════════════════════════════
    // CloudWatch Monitoring & Alarms
    // ═══════════════════════════════════════════════════════════════

    // SNS Topic for alerts
    const alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `${id}-alerts`,
      displayName: 'ChatPulse Alerts',
    });

    // CPU Utilization Alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'CPUAlarm', {
      alarmName: `${id}-cpu-high`,
      alarmDescription: 'CPU utilization exceeded 80%',
      metric: service.metricCpuUtilization(),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
    cpuAlarm.addAlarmAction({ bind: () => ({ alarmActionArn: alertTopic.topicArn }) });

    // Memory Utilization Alarm
    const memoryAlarm = new cloudwatch.Alarm(this, 'MemoryAlarm', {
      alarmName: `${id}-memory-high`,
      alarmDescription: 'Memory utilization exceeded 80%',
      metric: service.metricMemoryUtilization(),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
    memoryAlarm.addAlarmAction({ bind: () => ({ alarmActionArn: alertTopic.topicArn }) });

    // ALB 5xx Error Alarm
    const alb5xxAlarm = new cloudwatch.Alarm(this, 'ALB5xxAlarm', {
      alarmName: `${id}-5xx-errors`,
      alarmDescription: 'ALB 5xx errors exceeded threshold',
      metric: alb.metrics.httpCodeElb(elbv2.HttpCodeElb.ELB_5XX_COUNT, {
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
    alb5xxAlarm.addAlarmAction({ bind: () => ({ alarmActionArn: alertTopic.topicArn }) });

    // Healthy Host Count Alarm
    const healthyHostAlarm = new cloudwatch.Alarm(this, 'HealthyHostAlarm', {
      alarmName: `${id}-unhealthy-hosts`,
      alarmDescription: 'Healthy host count dropped below minimum',
      metric: targetGroup.metrics.healthyHostCount(),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    });
    healthyHostAlarm.addAlarmAction({ bind: () => ({ alarmActionArn: alertTopic.topicArn }) });

    // RDS CPU Alarm
    const rdsAlarm = new cloudwatch.Alarm(this, 'RDSCPUAlarm', {
      alarmName: `${id}-rds-cpu-high`,
      alarmDescription: 'RDS CPU utilization exceeded 80%',
      metric: database.metricCPUUtilization(),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
    rdsAlarm.addAlarmAction({ bind: () => ({ alarmActionArn: alertTopic.topicArn }) });

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'SSEDashboard', {
      dashboardName: `${id}-dashboard`,
    });

    dashboard.addWidgets(
      new cloudwatch.TextWidget({
        markdown: '# ChatPulse\nReal-time monitoring dashboard',
        width: 24,
        height: 1,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'ECS CPU & Memory Utilization',
        left: [service.metricCpuUtilization()],
        right: [service.metricMemoryUtilization()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'ALB Request Count & Latency',
        left: [alb.metrics.requestCount()],
        right: [alb.metrics.targetResponseTime()],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'ALB HTTP Responses',
        left: [
          alb.metrics.httpCodeTarget(elbv2.HttpCodeTarget.TARGET_2XX_COUNT, { label: '2xx' }),
          alb.metrics.httpCodeTarget(elbv2.HttpCodeTarget.TARGET_4XX_COUNT, { label: '4xx' }),
          alb.metrics.httpCodeTarget(elbv2.HttpCodeTarget.TARGET_5XX_COUNT, { label: '5xx' }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Active Connections & Healthy Hosts',
        left: [alb.metrics.activeConnectionCount()],
        right: [targetGroup.metrics.healthyHostCount()],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'RDS CPU & Connections',
        left: [database.metricCPUUtilization()],
        right: [database.metricDatabaseConnections()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'RDS Storage & IOPS',
        left: [database.metricFreeStorageSpace()],
        right: [database.metricReadIOPS(), database.metricWriteIOPS()],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.AlarmStatusWidget({
        title: 'Alarm Status',
        alarms: [cpuAlarm, memoryAlarm, alb5xxAlarm, healthyHostAlarm, rdsAlarm],
        width: 24,
        height: 3,
      })
    );

    // ═══════════════════════════════════════════════════════════════
    // Outputs
    // ═══════════════════════════════════════════════════════════════
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `${id}-alb-dns`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerURL', {
      value: `http://${alb.loadBalancerDnsName}`,
      description: 'Application URL',
      exportName: `${id}-url`,
    });

    new cdk.CfnOutput(this, 'RedisEndpoint', {
      value: `${redisCluster.attrRedisEndpointAddress}:${redisCluster.attrRedisEndpointPort}`,
      description: 'ElastiCache Redis endpoint',
      exportName: `${id}-redis-endpoint`,
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster name',
      exportName: `${id}-cluster-name`,
    });

    new cdk.CfnOutput(this, 'ECSServiceName', {
      value: service.serviceName,
      description: 'ECS Service name',
      exportName: `${id}-service-name`,
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: `${database.dbInstanceEndpointAddress}:${database.dbInstanceEndpointPort}`,
      description: 'RDS PostgreSQL endpoint',
      exportName: `${id}-db-endpoint`,
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: dbCredentials.secretArn,
      description: 'Database credentials secret ARN',
      exportName: `${id}-db-secret-arn`,
    });

    new cdk.CfnOutput(this, 'JWTSecretArn', {
      value: jwtSecret.secretArn,
      description: 'JWT secret ARN',
      exportName: `${id}-jwt-secret-arn`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboard', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${id}-dashboard`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${id}-dashboard-url`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS Alert Topic ARN (subscribe for alerts)',
      exportName: `${id}-alert-topic`,
    });
  }
}

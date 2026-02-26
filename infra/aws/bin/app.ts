#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SSENotificationStack } from '../lib/sse-notification-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const environment = app.node.tryGetContext('environment') || 'production';
const region = app.node.tryGetContext('region') || 'us-east-1';
const desiredCount = app.node.tryGetContext('desiredCount') || 3;

new SSENotificationStack(app, 'SSENotificationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: region,
  },
  environment,
  desiredCount,
  description: 'SSE Notification System - Production-grade real-time notifications',
});

app.synth();

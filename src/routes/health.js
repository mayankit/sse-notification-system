const express = require('express')
const { redis } = require('../config/redis')
const { pool } = require('../config/database')
const { SERVER_ID, MAX_CONNECTIONS_PER_SERVER } = require('../config/index')
const connectionManager = require('../connections/manager')

const router = express.Router()
let isShuttingDown = false

// Metrics counters
const metrics = {
  messagesReceived: 0,
  messagesSent: 0,
  messagesQueued: 0,
  connectionsTotal: 0,
  disconnectionsTotal: 0,
  authSuccessTotal: 0,
  authFailureTotal: 0,
  errorsTotal: 0
}

const incrementMetric = (name, value = 1) => {
  if (metrics[name] !== undefined) {
    metrics[name] += value
  }
}

const setShuttingDown = (value) => {
  isShuttingDown = value
}

router.get('/health', async (req, res) => {
  let redisStatus = 'ok'
  let dbStatus = 'ok'

  try {
    await redis.ping()
  } catch (err) {
    redisStatus = 'error'
  }

  try {
    await pool.query('SELECT 1')
  } catch (err) {
    dbStatus = 'error'
  }

  const status = redisStatus === 'ok' && dbStatus === 'ok' && !isShuttingDown ? 'ok' : 'degraded'

  res.status(200).json({
    status,
    serverId: SERVER_ID,
    connectedUsers: connectionManager.size(),
    maxConnections: MAX_CONNECTIONS_PER_SERVER,
    redisStatus,
    dbStatus,
    uptime: Math.floor(process.uptime()),
    shuttingDown: isShuttingDown,
    memoryMB: Math.round(process.memoryUsage().heapUsed / 1024 / 1024)
  })
})

// Prometheus metrics endpoint
router.get('/metrics', async (req, res) => {
  const memUsage = process.memoryUsage()
  const connectedUsers = connectionManager.size()

  let redisConnected = 1
  let dbConnected = 1

  try {
    await redis.ping()
  } catch {
    redisConnected = 0
  }

  try {
    await pool.query('SELECT 1')
  } catch {
    dbConnected = 0
  }

  const lines = [
    '# HELP sse_connected_users Number of currently connected SSE users',
    '# TYPE sse_connected_users gauge',
    `sse_connected_users{server="${SERVER_ID}"} ${connectedUsers}`,
    '',
    '# HELP sse_max_connections Maximum allowed connections',
    '# TYPE sse_max_connections gauge',
    `sse_max_connections{server="${SERVER_ID}"} ${MAX_CONNECTIONS_PER_SERVER}`,
    '',
    '# HELP sse_messages_received_total Total messages received',
    '# TYPE sse_messages_received_total counter',
    `sse_messages_received_total{server="${SERVER_ID}"} ${metrics.messagesReceived}`,
    '',
    '# HELP sse_messages_sent_total Total messages sent (delivered)',
    '# TYPE sse_messages_sent_total counter',
    `sse_messages_sent_total{server="${SERVER_ID}"} ${metrics.messagesSent}`,
    '',
    '# HELP sse_messages_queued_total Total messages queued (offline)',
    '# TYPE sse_messages_queued_total counter',
    `sse_messages_queued_total{server="${SERVER_ID}"} ${metrics.messagesQueued}`,
    '',
    '# HELP sse_connections_total Total SSE connections established',
    '# TYPE sse_connections_total counter',
    `sse_connections_total{server="${SERVER_ID}"} ${metrics.connectionsTotal}`,
    '',
    '# HELP sse_disconnections_total Total SSE disconnections',
    '# TYPE sse_disconnections_total counter',
    `sse_disconnections_total{server="${SERVER_ID}"} ${metrics.disconnectionsTotal}`,
    '',
    '# HELP sse_auth_success_total Total successful authentications',
    '# TYPE sse_auth_success_total counter',
    `sse_auth_success_total{server="${SERVER_ID}"} ${metrics.authSuccessTotal}`,
    '',
    '# HELP sse_auth_failure_total Total failed authentications',
    '# TYPE sse_auth_failure_total counter',
    `sse_auth_failure_total{server="${SERVER_ID}"} ${metrics.authFailureTotal}`,
    '',
    '# HELP sse_errors_total Total errors',
    '# TYPE sse_errors_total counter',
    `sse_errors_total{server="${SERVER_ID}"} ${metrics.errorsTotal}`,
    '',
    '# HELP sse_uptime_seconds Server uptime in seconds',
    '# TYPE sse_uptime_seconds gauge',
    `sse_uptime_seconds{server="${SERVER_ID}"} ${Math.floor(process.uptime())}`,
    '',
    '# HELP sse_memory_heap_bytes Heap memory used in bytes',
    '# TYPE sse_memory_heap_bytes gauge',
    `sse_memory_heap_bytes{server="${SERVER_ID}"} ${memUsage.heapUsed}`,
    '',
    '# HELP sse_memory_rss_bytes RSS memory in bytes',
    '# TYPE sse_memory_rss_bytes gauge',
    `sse_memory_rss_bytes{server="${SERVER_ID}"} ${memUsage.rss}`,
    '',
    '# HELP sse_redis_connected Redis connection status',
    '# TYPE sse_redis_connected gauge',
    `sse_redis_connected{server="${SERVER_ID}"} ${redisConnected}`,
    '',
    '# HELP sse_db_connected Database connection status',
    '# TYPE sse_db_connected gauge',
    `sse_db_connected{server="${SERVER_ID}"} ${dbConnected}`,
    '',
    '# HELP sse_shutting_down Server shutdown status',
    '# TYPE sse_shutting_down gauge',
    `sse_shutting_down{server="${SERVER_ID}"} ${isShuttingDown ? 1 : 0}`,
    ''
  ]

  res.set('Content-Type', 'text/plain; charset=utf-8')
  res.send(lines.join('\n'))
})

module.exports = { router, setShuttingDown, incrementMetric, metrics }

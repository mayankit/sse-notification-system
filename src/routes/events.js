const express = require('express')
const { SERVER_ID, MAX_CONNECTIONS_PER_SERVER } = require('../config/index')
const connectionManager = require('../connections/manager')
const pubsub = require('../services/pubsub')
const inbox = require('../services/inbox')
const eventStream = require('../services/eventStream')
const heartbeat = require('../services/heartbeat')
const { verifyToken, extractToken } = require('../utils/jwt')
const { incrementMetric } = require('./health')

const router = express.Router()
let isShuttingDown = false

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [events] ${msg}`)

const setShuttingDown = (value) => {
  isShuttingDown = value
}

router.get('/events', async (req, res) => {
  // Extract and verify JWT token
  const token = extractToken(req)
  if (!token) {
    log('WARN', 'SSE connection rejected - no token')
    return res.status(401).json({ error: 'unauthorized', message: 'Authentication required' })
  }

  const decoded = verifyToken(token)
  if (!decoded) {
    log('WARN', 'SSE connection rejected - invalid token')
    return res.status(401).json({ error: 'unauthorized', message: 'Invalid or expired token' })
  }

  const userId = decoded.userId

  if (isShuttingDown) {
    log('WARN', `rejecting connection for ${userId} - server draining`)
    return res.status(503).json({ error: 'server_draining', retryAfter: 5 })
  }

  if (connectionManager.size() >= MAX_CONNECTIONS_PER_SERVER) {
    log('WARN', `rejecting connection for ${userId} - capacity exceeded`)
    return res.status(503).set('Retry-After', '5').json({ error: 'capacity_exceeded' })
  }

  if (connectionManager.has(userId)) {
    log('INFO', `duplicate connection for ${userId}, closing existing`)
    await connectionManager.writeToClient(userId, 'reconnect', {
      reason: 'duplicate_connection'
    })
    heartbeat.stop(userId)
    await pubsub.unsubscribe(userId)
    await connectionManager.unregister(userId)
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  })
  res.flushHeaders()

  await connectionManager.register(userId, res)
  await pubsub.subscribe(userId)

  const lastEventId = req.headers['last-event-id']
  if (lastEventId) {
    log('INFO', `replaying events for ${userId} from ${lastEventId}`)
    await eventStream.replay(userId, lastEventId)
  }

  let count = 0
  const pendingCount = await inbox.count(userId)
  if (pendingCount > 0) {
    count = pendingCount
    await connectionManager.writeToClient(userId, 'queued_flush', {
      phase: 'start',
      count
    })
    const messages = await inbox.flush(userId)
    for (const msg of messages) {
      await connectionManager.writeToClient(userId, 'message', {
        ...msg,
        queued: true
      })
    }
    await connectionManager.writeToClient(userId, 'queued_flush', {
      phase: 'end'
    })
  }

  await connectionManager.writeToClient(userId, 'connected', {
    userId,
    serverId: SERVER_ID,
    unread: count,
    at: new Date().toISOString()
  })

  incrementMetric('connectionsTotal')
  heartbeat.start(userId)

  req.on('close', async () => {
    log('INFO', `connection closed for ${userId}`)
    incrementMetric('disconnectionsTotal')
    heartbeat.stop(userId)
    await connectionManager.unregister(userId)
    await pubsub.unsubscribe(userId)
  })
})

module.exports = { router, setShuttingDown }

const express = require('express')
const { redis } = require('../config/redis')
const { SERVER_ID, MAX_CONNECTIONS_PER_SERVER } = require('../config/index')
const connectionManager = require('../connections/manager')

const router = express.Router()
let isShuttingDown = false

const setShuttingDown = (value) => {
  isShuttingDown = value
}

router.get('/health', async (req, res) => {
  let redisStatus = 'ok'

  try {
    await redis.ping()
  } catch (err) {
    redisStatus = 'error'
  }

  const status = redisStatus === 'ok' && !isShuttingDown ? 'ok' : 'degraded'

  res.status(200).json({
    status,
    serverId: SERVER_ID,
    connectedUsers: connectionManager.size(),
    maxConnections: MAX_CONNECTIONS_PER_SERVER,
    redisStatus,
    uptime: Math.floor(process.uptime()),
    shuttingDown: isShuttingDown,
    memoryMB: Math.round(process.memoryUsage().heapUsed / 1024 / 1024)
  })
})

module.exports = { router, setShuttingDown }

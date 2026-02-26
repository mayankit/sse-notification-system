const { redis } = require('../config/redis')
const { SERVER_ID, HEARTBEAT_INTERVAL } = require('../config/index')
const connectionManager = require('../connections/manager')

const heartbeatIntervals = new Map()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [heartbeat] ${msg}`)

const start = (userId) => {
  if (heartbeatIntervals.has(userId)) {
    return
  }

  const interval = setInterval(async () => {
    try {
      await connectionManager.writeToClient(userId, 'heartbeat', {
        timestamp: new Date().toISOString(),
        serverId: SERVER_ID
      })
      await redis.set(`server:${SERVER_ID}:status`, 'active', 'EX', 60)
    } catch (err) {
      log('ERROR', `heartbeat failed for ${userId}: ${err.message}`)
    }
  }, HEARTBEAT_INTERVAL)

  heartbeatIntervals.set(userId, interval)
  log('INFO', `started heartbeat for ${userId}`)
}

const stop = (userId) => {
  const interval = heartbeatIntervals.get(userId)
  if (interval) {
    clearInterval(interval)
    heartbeatIntervals.delete(userId)
    log('INFO', `stopped heartbeat for ${userId}`)
  }
}

module.exports = {
  start,
  stop
}

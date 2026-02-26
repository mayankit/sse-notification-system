const express = require('express')
const path = require('path')
const { redis } = require('./config/redis')
const { initSchema } = require('./config/database')
const { SERVER_ID, PORT } = require('./config/index')
const connectionManager = require('./connections/manager')
const { router: eventsRouter, setShuttingDown: setEventsShuttingDown } = require('./routes/events')
const sendRouter = require('./routes/send')
const { router: healthRouter, setShuttingDown: setHealthShuttingDown } = require('./routes/health')
const usersRouter = require('./routes/users')
const authRouter = require('./routes/auth')
const { optionalAuth } = require('./middleware/auth')

const app = express()
let isShuttingDown = false

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [server] ${msg}`)

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// Middleware
app.use(express.json())
app.use(express.static(path.join(__dirname, '../public')))

// Apply optional auth to all routes (for /auth/me)
app.use(optionalAuth)

// Routes
app.use(authRouter)        // /auth/signup, /auth/login, /auth/me
app.use(eventsRouter)      // /events (SSE)
app.use(sendRouter)        // /send
app.use(healthRouter)      // /health
app.use(usersRouter)       // /users

const shutdown = async () => {
  if (isShuttingDown) return
  isShuttingDown = true

  log('INFO', 'initiating graceful shutdown')

  setEventsShuttingDown(true)
  setHealthShuttingDown(true)

  const userIds = connectionManager.allUserIds()
  for (const userId of userIds) {
    await connectionManager.writeToClient(userId, 'reconnect', {
      reason: 'server_drain',
      retryAfter: 2
    })
  }

  log('INFO', 'waiting for clients to reconnect')
  await sleep(5000)

  const remainingUserIds = connectionManager.allUserIds()
  for (const userId of remainingUserIds) {
    try {
      await redis.del(`user:${userId}:session`)
    } catch (err) {
      log('ERROR', `failed to clean session for ${userId}: ${err.message}`)
    }
  }

  try {
    await redis.del(`server:${SERVER_ID}:status`)
  } catch (err) {
    log('ERROR', `failed to clean server status: ${err.message}`)
  }

  log('INFO', 'closing HTTP server')
  httpServer.close(() => {
    log('INFO', 'shutdown complete')
    process.exit(0)
  })

  setTimeout(() => {
    log('WARN', 'forced shutdown after timeout')
    process.exit(1)
  }, 10000)
}

process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)

const startServer = async () => {
  // Initialize database schema
  try {
    await initSchema()
    log('INFO', 'database schema initialized')
  } catch (err) {
    log('ERROR', `failed to initialize database: ${err.message}`)
    // Continue anyway - schema might already exist
  }

  // Register server in Redis
  try {
    await redis.set(`server:${SERVER_ID}:status`, 'active', 'EX', 60)
    log('INFO', 'server status registered in Redis')
  } catch (err) {
    log('ERROR', `failed to register server status: ${err.message}`)
  }

  httpServer = app.listen(PORT, () => {
    log('INFO', `server started on port ${PORT}`)
  })
}

let httpServer
startServer()

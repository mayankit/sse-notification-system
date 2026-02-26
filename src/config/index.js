require('dotenv').config()

// Build DATABASE_URL from individual env vars if not provided directly
const buildDatabaseUrl = () => {
  if (process.env.DATABASE_URL) {
    return process.env.DATABASE_URL
  }

  // Support individual DB_* environment variables (for AWS/cloud deployments)
  const host = process.env.DB_HOST || 'localhost'
  const port = process.env.DB_PORT || '5432'
  const name = process.env.DB_NAME || 'sseapp'
  const user = process.env.DB_USERNAME || 'postgres'
  const pass = process.env.DB_PASSWORD || 'postgres'

  return `postgresql://${user}:${pass}@${host}:${port}/${name}`
}

module.exports = {
  // Server
  SERVER_ID: process.env.SERVER_ID || 'server_1',
  PORT: parseInt(process.env.PORT, 10) || 3000,

  // Redis
  REDIS_URL: process.env.REDIS_URL || 'redis://localhost:6379',
  REDIS_TLS: process.env.REDIS_TLS === 'true',

  // PostgreSQL
  DATABASE_URL: buildDatabaseUrl(),

  // JWT
  JWT_SECRET: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production',
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '7d',

  // SSE Configuration
  HEARTBEAT_INTERVAL: parseInt(process.env.HEARTBEAT_INTERVAL, 10) || 30000,
  MAX_CONNECTIONS_PER_SERVER: parseInt(process.env.MAX_CONNECTIONS_PER_SERVER, 10) || 50000,

  // Message Queue
  INBOX_TTL_SECONDS: parseInt(process.env.INBOX_TTL_SECONDS, 10) || 604800,
  EVENT_STREAM_MAXLEN: parseInt(process.env.EVENT_STREAM_MAXLEN, 10) || 500,
  EVENT_STREAM_TTL: parseInt(process.env.EVENT_STREAM_TTL, 10) || 3600,

  // Rate Limiting
  RATE_LIMIT_MAX: parseInt(process.env.RATE_LIMIT_MAX, 10) || 100,
  RATE_LIMIT_WINDOW_SECONDS: parseInt(process.env.RATE_LIMIT_WINDOW_SECONDS, 10) || 60
}

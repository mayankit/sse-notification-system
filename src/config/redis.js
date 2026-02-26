const Redis = require('ioredis')
const { SERVER_ID, REDIS_URL, REDIS_TLS } = require('./index')

const log = (msg) => console.log(`${msg} [${SERVER_ID}]`)

const buildConfig = () => {
  const config = {
    retryStrategy: (times) => Math.min(times * 100, 3000),
    enableReadyCheck: true,
    maxRetriesPerRequest: 3,
    lazyConnect: false
  }
  if (REDIS_TLS) {
    config.tls = { rejectUnauthorized: false }
  }
  return config
}

const createClient = (name) => {
  const client = new Redis(REDIS_URL, buildConfig())
  client.on('connect', () => log(`[INFO] [redis] ${name} connected`))
  client.on('reconnecting', () => log(`[WARN] [redis] ${name} reconnecting`))
  client.on('error', (e) => log(`[ERROR] [redis] ${name} error: ${e.message}`))
  return client
}

module.exports = {
  redis: createClient('regular'),
  publisher: createClient('publisher'),
  subscriber: createClient('subscriber')
}

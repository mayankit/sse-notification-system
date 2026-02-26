const { redis } = require('../config/redis')
const { SERVER_ID, INBOX_TTL_SECONDS } = require('../config/index')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [inbox] ${msg}`)

const push = async (userId, msg) => {
  const key = `inbox:${userId}`
  try {
    await redis.lpush(key, JSON.stringify(msg))
    await redis.expire(key, INBOX_TTL_SECONDS)
    log('INFO', `pushed message to inbox for ${userId}`)
  } catch (err) {
    log('ERROR', `failed to push to inbox for ${userId}: ${err.message}`)
  }
}

const flush = async (userId) => {
  const key = `inbox:${userId}`
  try {
    const messages = await redis.lrange(key, 0, -1)
    await redis.del(key)
    log('INFO', `flushed ${messages.length} messages for ${userId}`)
    return messages.map((msg) => JSON.parse(msg)).reverse()
  } catch (err) {
    log('ERROR', `failed to flush inbox for ${userId}: ${err.message}`)
    return []
  }
}

const count = async (userId) => {
  const key = `inbox:${userId}`
  try {
    const len = await redis.llen(key)
    return len
  } catch (err) {
    log('ERROR', `failed to count inbox for ${userId}: ${err.message}`)
    return 0
  }
}

module.exports = {
  push,
  flush,
  count
}

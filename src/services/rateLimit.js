const { redis } = require('../config/redis')
const { SERVER_ID, RATE_LIMIT_MAX, RATE_LIMIT_WINDOW_SECONDS } = require('../config/index')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [rateLimit] ${msg}`)

const check = async (userId) => {
  const windowMinute = Math.floor(Date.now() / 60000)
  const key = `ratelimit:${userId}:${windowMinute}`

  try {
    const current = await redis.incr(key)
    if (current === 1) {
      await redis.expire(key, RATE_LIMIT_WINDOW_SECONDS)
    }

    const remaining = Math.max(0, RATE_LIMIT_MAX - current)
    const retryAfter = RATE_LIMIT_WINDOW_SECONDS - (Math.floor(Date.now() / 1000) % RATE_LIMIT_WINDOW_SECONDS)

    if (current > RATE_LIMIT_MAX) {
      log('WARN', `rate limit exceeded for ${userId}`)
      return { allowed: false, remaining: 0, retryAfter }
    }

    return { allowed: true, remaining, retryAfter }
  } catch (err) {
    log('ERROR', `failed to check rate limit for ${userId}: ${err.message}`)
    return { allowed: true, remaining: RATE_LIMIT_MAX, retryAfter: 0 }
  }
}

module.exports = {
  check
}

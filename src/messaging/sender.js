const { redis } = require('../config/redis')
const { SERVER_ID } = require('../config/index')
const rateLimit = require('../services/rateLimit')
const eventStream = require('../services/eventStream')
const pubsub = require('../services/pubsub')
const inbox = require('../services/inbox')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [sender] ${msg}`)

const send = async (fromUserId, toUserId, message) => {
  const rateLimitResult = await rateLimit.check(fromUserId)
  if (!rateLimitResult.allowed) {
    return {
      success: false,
      error: 'rate_limit_exceeded',
      retryAfter: rateLimitResult.retryAfter
    }
  }

  try {
    const eventId = await redis.incr('event:id:counter')

    const payload = {
      id: eventId,
      fromUserId,
      toUserId,
      message,
      at: new Date().toISOString(),
      queued: false
    }

    await eventStream.append(toUserId, 'message', payload)

    const session = await redis.hgetall(`user:${toUserId}:session`)

    if (session && session.serverId) {
      await pubsub.publish(toUserId, payload)
      log('INFO', `delivered message ${eventId} from ${fromUserId} to ${toUserId} via ${session.serverId}`)
      return {
        success: true,
        status: 'delivered',
        online: true,
        eventId,
        deliveredTo: session.serverId
      }
    } else {
      payload.queued = true
      await inbox.push(toUserId, payload)
      log('INFO', `queued message ${eventId} from ${fromUserId} to ${toUserId}`)
      return {
        success: true,
        status: 'queued',
        online: false,
        eventId
      }
    }
  } catch (err) {
    log('ERROR', `failed to send message from ${fromUserId} to ${toUserId}: ${err.message}`)
    return {
      success: false,
      error: 'internal_error',
      message: err.message
    }
  }
}

module.exports = {
  send
}

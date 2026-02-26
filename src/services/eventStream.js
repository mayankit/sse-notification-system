const { redis } = require('../config/redis')
const { SERVER_ID, EVENT_STREAM_MAXLEN, EVENT_STREAM_TTL } = require('../config/index')
const connectionManager = require('../connections/manager')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [eventStream] ${msg}`)

const append = async (userId, eventName, data) => {
  const key = `stream:${userId}`
  try {
    const id = await redis.xadd(
      key,
      'MAXLEN',
      '~',
      EVENT_STREAM_MAXLEN,
      '*',
      'event',
      eventName,
      'data',
      JSON.stringify(data)
    )
    await redis.expire(key, EVENT_STREAM_TTL)
    log('INFO', `appended event ${eventName} to stream for ${userId}, id: ${id}`)
    return id
  } catch (err) {
    log('ERROR', `failed to append to stream for ${userId}: ${err.message}`)
    return null
  }
}

const replay = async (userId, lastEventId) => {
  const key = `stream:${userId}`
  try {
    const startId = incrementStreamId(lastEventId)
    const entries = await redis.xrange(key, startId, '+')
    log('INFO', `replaying ${entries.length} events for ${userId} from ${lastEventId}`)

    for (const [id, fields] of entries) {
      const eventName = fields[1]
      const data = JSON.parse(fields[3])
      await connectionManager.writeToClient(userId, eventName, data, id, { replayed: true })
    }

    return entries.length
  } catch (err) {
    log('ERROR', `failed to replay stream for ${userId}: ${err.message}`)
    return 0
  }
}

const incrementStreamId = (id) => {
  if (!id || id === '0') return '0'
  const [timestamp, sequence] = id.split('-')
  const nextSequence = parseInt(sequence, 10) + 1
  return `${timestamp}-${nextSequence}`
}

module.exports = {
  append,
  replay
}

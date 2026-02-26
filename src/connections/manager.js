const { redis } = require('../config/redis')
const { SERVER_ID } = require('../config/index')

const localClients = new Map()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [manager] ${msg}`)

const register = async (userId, res) => {
  localClients.set(userId, res)
  try {
    await redis.hset(`user:${userId}:session`, {
      serverId: SERVER_ID,
      connectedAt: new Date().toISOString()
    })
    await redis.expire(`user:${userId}:session`, 86400)
    log('INFO', `registered user ${userId}`)
  } catch (err) {
    log('ERROR', `failed to register user ${userId}: ${err.message}`)
  }
}

const unregister = async (userId) => {
  const res = localClients.get(userId)
  if (res && !res.writableEnded) {
    res.end()
  }
  localClients.delete(userId)
  try {
    await redis.del(`user:${userId}:session`)
    log('INFO', `unregistered user ${userId}`)
  } catch (err) {
    log('ERROR', `failed to unregister user ${userId}: ${err.message}`)
  }
}

const writeToClient = async (userId, eventName, data, eventId = null, options = {}) => {
  const res = localClients.get(userId)
  if (!res) {
    log('WARN', `no local client for user ${userId}`)
    return false
  }

  if (res.writableEnded) {
    log('WARN', `connection ended for user ${userId}`)
    localClients.delete(userId)
    return false
  }

  const payload = { ...data }
  if (options.replayed) {
    payload.replayed = true
  }

  const message = `event: ${eventName}\ndata: ${JSON.stringify(payload)}${eventId ? `\nid: ${eventId}` : ''}\n\n`

  return new Promise((resolve) => {
    const canWrite = res.write(message)

    if (!canWrite) {
      res.once('drain', async () => {
        if (eventId) {
          try {
            await redis.hset(`user:${userId}:session`, 'lastEventId', eventId)
          } catch (err) {
            log('ERROR', `failed to update lastEventId for ${userId}: ${err.message}`)
          }
        }
        resolve(true)
      })
    } else {
      if (eventId) {
        redis.hset(`user:${userId}:session`, 'lastEventId', eventId).catch((err) => {
          log('ERROR', `failed to update lastEventId for ${userId}: ${err.message}`)
        })
      }
      resolve(true)
    }
  })
}

const has = (userId) => localClients.has(userId)

const size = () => localClients.size

const allUserIds = () => Array.from(localClients.keys())

module.exports = {
  register,
  unregister,
  writeToClient,
  has,
  size,
  allUserIds
}

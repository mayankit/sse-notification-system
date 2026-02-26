const { publisher, subscriber } = require('../config/redis')
const { SERVER_ID } = require('../config/index')
const connectionManager = require('../connections/manager')

const activeSubscriptions = new Set()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [pubsub] ${msg}`)

subscriber.on('message', async (channel, message) => {
  const userId = channel.replace('user:', '')
  try {
    const payload = JSON.parse(message)
    log('INFO', `received message for ${userId}`)
    await connectionManager.writeToClient(userId, 'message', payload, payload.id)
  } catch (err) {
    log('ERROR', `failed to process message for ${userId}: ${err.message}`)
  }
})

const subscribe = async (userId) => {
  const channel = `user:${userId}`
  if (activeSubscriptions.has(channel)) {
    log('INFO', `already subscribed to ${channel}`)
    return
  }
  try {
    await subscriber.subscribe(channel)
    activeSubscriptions.add(channel)
    log('INFO', `subscribed to ${channel}`)
  } catch (err) {
    log('ERROR', `failed to subscribe to ${channel}: ${err.message}`)
  }
}

const unsubscribe = async (userId) => {
  const channel = `user:${userId}`
  if (!activeSubscriptions.has(channel)) {
    return
  }
  try {
    await subscriber.unsubscribe(channel)
    activeSubscriptions.delete(channel)
    log('INFO', `unsubscribed from ${channel}`)
  } catch (err) {
    log('ERROR', `failed to unsubscribe from ${channel}: ${err.message}`)
  }
}

const publish = async (userId, payload) => {
  const channel = `user:${userId}`
  try {
    await publisher.publish(channel, JSON.stringify(payload))
    log('INFO', `published to ${channel}`)
  } catch (err) {
    log('ERROR', `failed to publish to ${channel}: ${err.message}`)
  }
}

module.exports = {
  subscribe,
  unsubscribe,
  publish
}

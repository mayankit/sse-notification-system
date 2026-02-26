const express = require('express')
const { SERVER_ID } = require('../config/index')
const sender = require('../messaging/sender')
const { authenticate } = require('../middleware/auth')

const router = express.Router()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [send] ${msg}`)

// Validation middleware
const validateSend = (req, res, next) => {
  const { toUserId, message } = req.body
  const errors = {}

  if (!toUserId) {
    errors.toUserId = 'Recipient is required'
  }

  if (!message) {
    errors.message = 'Message is required'
  } else if (typeof message !== 'string') {
    errors.message = 'Message must be a string'
  } else if (message.length > 2000) {
    errors.message = 'Message must be at most 2000 characters'
  }

  // Cannot send to yourself
  if (toUserId && toUserId === req.userId) {
    errors.toUserId = 'Cannot send message to yourself'
  }

  if (Object.keys(errors).length > 0) {
    log('WARN', `validation failed: ${JSON.stringify(errors)}`)
    return res.status(400).json({ error: 'validation_failed', errors })
  }

  next()
}

router.post('/send', authenticate, validateSend, async (req, res) => {
  const { toUserId, message } = req.body
  const fromUserId = req.userId  // From JWT token

  log('INFO', `sending message from ${fromUserId} to ${toUserId}`)

  const result = await sender.send(fromUserId, toUserId, message)

  if (!result.success) {
    if (result.error === 'rate_limit_exceeded') {
      return res.status(429).json({
        error: 'rate_limit_exceeded',
        retryAfter: result.retryAfter
      })
    }
    return res.status(500).json({ error: result.error, message: result.message })
  }

  return res.status(200).json({
    status: result.status,
    online: result.online,
    eventId: result.eventId,
    deliveredTo: result.deliveredTo
  })
})

module.exports = router

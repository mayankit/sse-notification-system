const { SERVER_ID } = require('../config/index')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [validateSend] ${msg}`)

const MAX_MESSAGE_LENGTH = 2000

const validateSend = (req, res, next) => {
  const { toUserId, fromUserId, message } = req.body
  const errors = {}

  if (!toUserId) {
    errors.toUserId = 'toUserId is required'
  }

  if (!fromUserId) {
    errors.fromUserId = 'fromUserId is required'
  }

  if (!message) {
    errors.message = 'message is required'
  } else if (typeof message !== 'string') {
    errors.message = 'message must be a string'
  } else if (message.length > MAX_MESSAGE_LENGTH) {
    errors.message = `message must be at most ${MAX_MESSAGE_LENGTH} characters`
  }

  if (toUserId && fromUserId && toUserId === fromUserId) {
    errors.toUserId = 'cannot send message to yourself'
  }

  if (Object.keys(errors).length > 0) {
    log('WARN', `validation failed: ${JSON.stringify(errors)}`)
    return res.status(400).json({ error: 'validation_failed', errors })
  }

  next()
}

module.exports = validateSend

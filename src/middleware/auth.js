const { verifyToken, extractToken } = require('../utils/jwt')
const { SERVER_ID } = require('../config/index')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [auth] ${msg}`)

// JWT Authentication middleware
const authenticate = (req, res, next) => {
  const token = extractToken(req)

  if (!token) {
    log('WARN', 'missing authentication token')
    return res.status(401).json({ error: 'unauthorized', message: 'Authentication required' })
  }

  const decoded = verifyToken(token)
  if (!decoded) {
    log('WARN', 'invalid authentication token')
    return res.status(401).json({ error: 'unauthorized', message: 'Invalid or expired token' })
  }

  // Attach user info to request
  req.user = decoded
  req.userId = decoded.userId

  next()
}

// Optional authentication - doesn't fail if no token
const optionalAuth = (req, res, next) => {
  const token = extractToken(req)

  if (token) {
    const decoded = verifyToken(token)
    if (decoded) {
      req.user = decoded
      req.userId = decoded.userId
    }
  }

  next()
}

module.exports = {
  authenticate,
  optionalAuth
}

const jwt = require('jsonwebtoken')
const { JWT_SECRET, JWT_EXPIRES_IN } = require('../config/index')

// Generate JWT token
const generateToken = (user) => {
  const payload = {
    userId: user.id,
    username: user.username
  }

  return jwt.sign(payload, JWT_SECRET, {
    expiresIn: JWT_EXPIRES_IN
  })
}

// Verify JWT token
const verifyToken = (token) => {
  try {
    return jwt.verify(token, JWT_SECRET)
  } catch (err) {
    return null
  }
}

// Extract token from Authorization header or query param
const extractToken = (req) => {
  // Check Authorization header
  const authHeader = req.headers.authorization
  if (authHeader && authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7)
  }

  // Check query parameter (for SSE connections)
  if (req.query.token) {
    return req.query.token
  }

  // Check cookie
  if (req.cookies && req.cookies.token) {
    return req.cookies.token
  }

  return null
}

module.exports = {
  generateToken,
  verifyToken,
  extractToken
}

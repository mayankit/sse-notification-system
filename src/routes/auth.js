const express = require('express')
const User = require('../models/User')
const { generateToken } = require('../utils/jwt')
const { SERVER_ID } = require('../config/index')

const router = express.Router()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [auth] ${msg}`)

// Validation helpers
const validateEmail = (email) => {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return re.test(email)
}

const validateUsername = (username) => {
  const re = /^[a-zA-Z0-9_]{3,30}$/
  return re.test(username)
}

const validatePassword = (password) => {
  return password && password.length >= 6
}

// POST /auth/signup
router.post('/auth/signup', async (req, res) => {
  const { username, email, password, displayName } = req.body
  const errors = {}

  // Validate inputs
  if (!username) {
    errors.username = 'Username is required'
  } else if (!validateUsername(username)) {
    errors.username = 'Username must be 3-30 characters, letters, numbers, underscore only'
  }

  if (!email) {
    errors.email = 'Email is required'
  } else if (!validateEmail(email)) {
    errors.email = 'Invalid email format'
  }

  if (!password) {
    errors.password = 'Password is required'
  } else if (!validatePassword(password)) {
    errors.password = 'Password must be at least 6 characters'
  }

  if (Object.keys(errors).length > 0) {
    return res.status(400).json({ error: 'validation_failed', errors })
  }

  try {
    const user = await User.create({
      username,
      email,
      password,
      displayName: displayName || username
    })

    const token = generateToken(user)

    log('INFO', `user registered: ${username}`)

    res.status(201).json({
      message: 'User created successfully',
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        displayName: user.display_name,
        avatar: user.avatar
      },
      token
    })
  } catch (err) {
    log('ERROR', `signup failed: ${err.message}`)

    if (err.message === 'Username already exists') {
      return res.status(409).json({ error: 'username_taken', message: err.message })
    }
    if (err.message === 'Email already exists') {
      return res.status(409).json({ error: 'email_taken', message: err.message })
    }

    res.status(500).json({ error: 'signup_failed', message: 'Failed to create user' })
  }
})

// POST /auth/login
router.post('/auth/login', async (req, res) => {
  const { username, password } = req.body

  if (!username || !password) {
    return res.status(400).json({
      error: 'validation_failed',
      message: 'Username and password are required'
    })
  }

  try {
    // Find user by username or email
    let user = await User.findByUsername(username)
    if (!user && validateEmail(username)) {
      user = await User.findByEmail(username)
    }

    if (!user) {
      log('WARN', `login failed: user not found - ${username}`)
      return res.status(401).json({ error: 'invalid_credentials', message: 'Invalid username or password' })
    }

    const isValid = await User.verifyPassword(password, user.password_hash)
    if (!isValid) {
      log('WARN', `login failed: invalid password - ${username}`)
      return res.status(401).json({ error: 'invalid_credentials', message: 'Invalid username or password' })
    }

    await User.updateLastLogin(user.id)

    const token = generateToken(user)

    log('INFO', `user logged in: ${username}`)

    res.json({
      message: 'Login successful',
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        displayName: user.display_name,
        avatar: user.avatar
      },
      token
    })
  } catch (err) {
    log('ERROR', `login failed: ${err.message}`)
    res.status(500).json({ error: 'login_failed', message: 'Failed to login' })
  }
})

// GET /auth/me - Get current user
router.get('/auth/me', async (req, res) => {
  // This route requires authentication middleware
  if (!req.user) {
    return res.status(401).json({ error: 'unauthorized', message: 'Not authenticated' })
  }

  try {
    const user = await User.findById(req.user.userId)
    if (!user) {
      return res.status(404).json({ error: 'not_found', message: 'User not found' })
    }

    res.json({
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        displayName: user.display_name,
        avatar: user.avatar
      }
    })
  } catch (err) {
    log('ERROR', `get user failed: ${err.message}`)
    res.status(500).json({ error: 'server_error', message: 'Failed to get user' })
  }
})

module.exports = router

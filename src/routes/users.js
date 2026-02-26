const express = require('express')
const { redis } = require('../config/redis')
const User = require('../models/User')
const { authenticate } = require('../middleware/auth')
const { SERVER_ID } = require('../config/index')

const router = express.Router()

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [users] ${msg}`)

// GET /users - Get all users with online status
router.get('/users', authenticate, async (req, res) => {
  const currentUserId = req.userId

  try {
    // Get all users from database
    const allUsers = await User.findAll()

    // Get online status from Redis for each user
    const usersWithStatus = await Promise.all(
      allUsers.map(async (user) => {
        const session = await redis.hgetall(`user:${user.id}:session`)
        const isOnline = session && session.serverId ? true : false

        return {
          id: user.id,
          username: user.username,
          displayName: user.display_name,
          avatar: user.avatar,
          online: isOnline,
          serverId: session?.serverId || null,
          connectedAt: session?.connectedAt || null,
          isCurrentUser: user.id === currentUserId
        }
      })
    )

    // Separate current user, online, and offline
    const currentUser = usersWithStatus.find(u => u.isCurrentUser)
    const online = usersWithStatus.filter(u => u.online && !u.isCurrentUser)
    const offline = usersWithStatus.filter(u => !u.online && !u.isCurrentUser)

    // Sort by display name
    online.sort((a, b) => a.displayName.localeCompare(b.displayName))
    offline.sort((a, b) => a.displayName.localeCompare(b.displayName))

    res.json({
      currentUser: currentUser || null,
      online,
      offline,
      total: allUsers.length,
      onlineCount: online.length + (currentUser?.online ? 1 : 0)
    })
  } catch (err) {
    log('ERROR', `failed to get users: ${err.message}`)
    res.status(500).json({ error: 'failed to get users' })
  }
})

// GET /users/search - Search users
router.get('/users/search', authenticate, async (req, res) => {
  const { q } = req.query

  if (!q || q.length < 2) {
    return res.status(400).json({ error: 'Search query must be at least 2 characters' })
  }

  try {
    const users = await User.search(q)

    // Get online status
    const usersWithStatus = await Promise.all(
      users.map(async (user) => {
        const session = await redis.hgetall(`user:${user.id}:session`)
        return {
          id: user.id,
          username: user.username,
          displayName: user.display_name,
          avatar: user.avatar,
          online: session && session.serverId ? true : false
        }
      })
    )

    res.json({ users: usersWithStatus })
  } catch (err) {
    log('ERROR', `failed to search users: ${err.message}`)
    res.status(500).json({ error: 'failed to search users' })
  }
})

// GET /users/:id - Get single user
router.get('/users/:id', authenticate, async (req, res) => {
  try {
    const user = await User.findById(req.params.id)

    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    const session = await redis.hgetall(`user:${user.id}:session`)

    res.json({
      id: user.id,
      username: user.username,
      displayName: user.display_name,
      avatar: user.avatar,
      online: session && session.serverId ? true : false,
      serverId: session?.serverId || null
    })
  } catch (err) {
    log('ERROR', `failed to get user: ${err.message}`)
    res.status(500).json({ error: 'failed to get user' })
  }
})

module.exports = router

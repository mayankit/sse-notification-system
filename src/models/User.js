const bcrypt = require('bcryptjs')
const { query } = require('../config/database')
const { SERVER_ID } = require('../config/index')

const log = (level, msg) => console.log(`[${level}] [${SERVER_ID}] [User] ${msg}`)

const SALT_ROUNDS = 10

// Generate avatar from name
const generateAvatar = (name) => {
  return name.charAt(0).toUpperCase()
}

// Create a new user
const create = async ({ username, email, password, displayName }) => {
  try {
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS)
    const avatar = generateAvatar(displayName || username)

    const result = await query(
      `INSERT INTO users (username, email, password_hash, display_name, avatar)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, username, email, display_name, avatar, created_at`,
      [username.toLowerCase(), email.toLowerCase(), passwordHash, displayName || username, avatar]
    )

    log('INFO', `user created: ${username}`)
    return result.rows[0]
  } catch (err) {
    if (err.code === '23505') {
      // Unique violation
      if (err.constraint === 'users_username_key') {
        throw new Error('Username already exists')
      }
      if (err.constraint === 'users_email_key') {
        throw new Error('Email already exists')
      }
    }
    throw err
  }
}

// Find user by ID
const findById = async (id) => {
  const result = await query(
    `SELECT id, username, email, display_name, avatar, created_at, last_login
     FROM users WHERE id = $1`,
    [id]
  )
  return result.rows[0] || null
}

// Find user by username
const findByUsername = async (username) => {
  const result = await query(
    `SELECT id, username, email, password_hash, display_name, avatar, created_at, last_login
     FROM users WHERE username = $1`,
    [username.toLowerCase()]
  )
  return result.rows[0] || null
}

// Find user by email
const findByEmail = async (email) => {
  const result = await query(
    `SELECT id, username, email, password_hash, display_name, avatar, created_at, last_login
     FROM users WHERE email = $1`,
    [email.toLowerCase()]
  )
  return result.rows[0] || null
}

// Verify password
const verifyPassword = async (plainPassword, hashedPassword) => {
  return bcrypt.compare(plainPassword, hashedPassword)
}

// Update last login
const updateLastLogin = async (id) => {
  await query(
    `UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1`,
    [id]
  )
}

// Get all users (for user list)
const findAll = async () => {
  const result = await query(
    `SELECT id, username, display_name, avatar, created_at
     FROM users ORDER BY display_name ASC`
  )
  return result.rows
}

// Search users by username or display name
const search = async (searchTerm, limit = 20) => {
  const result = await query(
    `SELECT id, username, display_name, avatar
     FROM users
     WHERE username ILIKE $1 OR display_name ILIKE $1
     ORDER BY display_name ASC
     LIMIT $2`,
    [`%${searchTerm}%`, limit]
  )
  return result.rows
}

// Update user profile
const update = async (id, { displayName, avatar }) => {
  const result = await query(
    `UPDATE users
     SET display_name = COALESCE($2, display_name),
         avatar = COALESCE($3, avatar),
         updated_at = CURRENT_TIMESTAMP
     WHERE id = $1
     RETURNING id, username, email, display_name, avatar`,
    [id, displayName, avatar]
  )
  return result.rows[0]
}

// Change password
const changePassword = async (id, newPassword) => {
  const passwordHash = await bcrypt.hash(newPassword, SALT_ROUNDS)
  await query(
    `UPDATE users SET password_hash = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
    [id, passwordHash]
  )
}

module.exports = {
  create,
  findById,
  findByUsername,
  findByEmail,
  verifyPassword,
  updateLastLogin,
  findAll,
  search,
  update,
  changePassword
}

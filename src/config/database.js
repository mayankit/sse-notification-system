const { Pool } = require('pg')
const { DATABASE_URL, SERVER_ID } = require('./index')

const log = (msg) => console.log(`${msg} [${SERVER_ID}]`)

// Parse DATABASE_URL and create pool
const pool = new Pool({
  connectionString: DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
})

pool.on('connect', () => {
  log('[INFO] [database] connected to PostgreSQL')
})

pool.on('error', (err) => {
  log(`[ERROR] [database] unexpected error: ${err.message}`)
})

// Query helper
const query = async (text, params) => {
  const start = Date.now()
  try {
    const result = await pool.query(text, params)
    const duration = Date.now() - start
    if (duration > 100) {
      log(`[WARN] [database] slow query (${duration}ms): ${text.substring(0, 50)}...`)
    }
    return result
  } catch (err) {
    log(`[ERROR] [database] query error: ${err.message}`)
    throw err
  }
}

// Initialize database schema
const initSchema = async () => {
  const schema = `
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      username VARCHAR(50) UNIQUE NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      display_name VARCHAR(100),
      avatar VARCHAR(10),
      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      last_login TIMESTAMP WITH TIME ZONE
    );

    CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
  `

  try {
    await query(schema)
    log('[INFO] [database] schema initialized')
  } catch (err) {
    log(`[ERROR] [database] schema initialization failed: ${err.message}`)
    throw err
  }
}

module.exports = {
  pool,
  query,
  initSchema
}

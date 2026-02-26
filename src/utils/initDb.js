const { initSchema, pool } = require('../config/database')

const init = async () => {
  console.log('Initializing database schema...')

  try {
    await initSchema()
    console.log('Database schema initialized successfully!')
  } catch (err) {
    console.error('Failed to initialize database:', err.message)
    process.exit(1)
  } finally {
    await pool.end()
  }
}

init()

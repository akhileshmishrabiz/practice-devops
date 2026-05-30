require('dotenv').config();

module.exports = {
  development: {
    username: process.env.USER_DB_USER || 'ecommerce_user',
    password: process.env.USER_DB_PASSWORD || 'secure_password_123',
    database: process.env.USER_DB_NAME || 'users',
    host: process.env.USER_DB_HOST || 'localhost',
    port: process.env.USER_DB_PORT || 5432,
    dialect: 'postgres',
    logging: false,
    pool: {
      max: 10,
      min: 0,
      acquire: 30000,
      idle: 10000
    }
  },
  production: {
    username: process.env.USER_DB_USER,
    password: process.env.USER_DB_PASSWORD,
    database: process.env.USER_DB_NAME,
    host: process.env.USER_DB_HOST,
    port: process.env.USER_DB_PORT,
    dialect: 'postgres',
    logging: false,
    pool: {
      max: 20,
      min: 5,
      acquire: 30000,
      idle: 10000
    }
  }
};

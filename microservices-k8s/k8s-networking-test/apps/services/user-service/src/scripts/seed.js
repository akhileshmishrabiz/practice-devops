require('dotenv').config();
const { sequelize, User } = require('../models');
const logger = require('../utils/logger');

const sampleUsers = [
  {
    email: 'john.doe@example.com',
    password: 'Password123!',
    firstName: 'John',
    lastName: 'Doe',
    phone: '+1-555-0101',
    address: '123 Main Street',
    city: 'New York',
    state: 'NY',
    country: 'USA',
    zipCode: '10001',
    isEmailVerified: true
  },
  {
    email: 'jane.smith@example.com',
    password: 'Password123!',
    firstName: 'Jane',
    lastName: 'Smith',
    phone: '+1-555-0102',
    address: '456 Oak Avenue',
    city: 'Los Angeles',
    state: 'CA',
    country: 'USA',
    zipCode: '90001',
    isEmailVerified: true
  },
  {
    email: 'bob.johnson@example.com',
    password: 'Password123!',
    firstName: 'Bob',
    lastName: 'Johnson',
    phone: '+1-555-0103',
    address: '789 Pine Road',
    city: 'Chicago',
    state: 'IL',
    country: 'USA',
    zipCode: '60601',
    isEmailVerified: true
  },
  {
    email: 'alice.williams@example.com',
    password: 'Password123!',
    firstName: 'Alice',
    lastName: 'Williams',
    phone: '+1-555-0104',
    address: '321 Elm Street',
    city: 'Houston',
    state: 'TX',
    country: 'USA',
    zipCode: '77001',
    isEmailVerified: false
  },
  {
    email: 'charlie.brown@example.com',
    password: 'Password123!',
    firstName: 'Charlie',
    lastName: 'Brown',
    phone: '+1-555-0105',
    address: '654 Maple Drive',
    city: 'Phoenix',
    state: 'AZ',
    country: 'USA',
    zipCode: '85001',
    isEmailVerified: true
  }
];

const seed = async () => {
  try {
    // Connect to database
    await sequelize.authenticate();
    logger.info('Database connection established');

    // Sync models
    await sequelize.sync({ force: true });
    logger.info('Database synchronized');

    // Create users
    for (const userData of sampleUsers) {
      await User.create(userData);
      logger.info(`User created: ${userData.email}`);
    }

    logger.info(`Successfully seeded ${sampleUsers.length} users`);
    console.log('\n✅ Database seeded successfully!');
    console.log('\nSample login credentials:');
    console.log('Email: john.doe@example.com');
    console.log('Password: Password123!\n');

    process.exit(0);
  } catch (error) {
    logger.error('Seed failed', { error: error.message });
    console.error('❌ Seed failed:', error.message);
    process.exit(1);
  }
};

seed();

const request = require('supertest');
const express = require('express');
const jwt = require('jsonwebtoken');

// Mock the database
jest.mock('../src/models', () => ({
  User: {
    findOne: jest.fn(),
    findByPk: jest.fn(),
    create: jest.fn()
  },
  sequelize: {
    authenticate: jest.fn().mockResolvedValue(true)
  }
}));

const { User, sequelize } = require('../src/models');
const authController = require('../src/controllers/authController');
const { authenticate } = require('../src/middleware/auth');

// Setup test app
const app = express();
app.use(express.json());

app.post('/api/v1/users/register', authController.register);
app.post('/api/v1/users/login', authController.login);
app.get('/api/v1/users/profile', authenticate, authController.getProfile);
app.get('/health', async (req, res) => {
  try {
    await sequelize.authenticate();
    res.json({ status: 'healthy', service: 'user-service' });
  } catch {
    res.status(503).json({ status: 'unhealthy' });
  }
});

describe('User Service Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('should return healthy status', async () => {
      const res = await request(app).get('/health');

      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe('healthy');
      expect(res.body.service).toBe('user-service');
    });
  });

  describe('POST /api/v1/users/register', () => {
    it('should register a new user successfully', async () => {
      const mockUser = {
        id: '123',
        email: 'test@example.com',
        firstName: 'Test',
        lastName: 'User',
        toJSON: () => ({
          id: '123',
          email: 'test@example.com',
          firstName: 'Test',
          lastName: 'User'
        })
      };

      User.findOne.mockResolvedValue(null);
      User.create.mockResolvedValue(mockUser);

      const res = await request(app)
        .post('/api/v1/users/register')
        .send({
          email: 'test@example.com',
          password: 'password123',
          firstName: 'Test',
          lastName: 'User'
        });

      expect(res.statusCode).toBe(201);
      expect(res.body.message).toBe('User registered successfully');
      expect(res.body.token).toBeDefined();
    });

    it('should return 409 if user already exists', async () => {
      User.findOne.mockResolvedValue({ id: '123', email: 'test@example.com' });

      const res = await request(app)
        .post('/api/v1/users/register')
        .send({
          email: 'test@example.com',
          password: 'password123',
          firstName: 'Test',
          lastName: 'User'
        });

      expect(res.statusCode).toBe(409);
      expect(res.body.error).toBe('User with this email already exists');
    });
  });

  describe('POST /api/v1/users/login', () => {
    it('should login user with valid credentials', async () => {
      const mockUser = {
        id: '123',
        email: 'test@example.com',
        isActive: true,
        comparePassword: jest.fn().mockResolvedValue(true),
        update: jest.fn().mockResolvedValue(true),
        toJSON: () => ({
          id: '123',
          email: 'test@example.com'
        })
      };

      User.findOne.mockResolvedValue(mockUser);

      const res = await request(app)
        .post('/api/v1/users/login')
        .send({
          email: 'test@example.com',
          password: 'password123'
        });

      expect(res.statusCode).toBe(200);
      expect(res.body.message).toBe('Login successful');
      expect(res.body.token).toBeDefined();
    });

    it('should return 401 for invalid email', async () => {
      User.findOne.mockResolvedValue(null);

      const res = await request(app)
        .post('/api/v1/users/login')
        .send({
          email: 'wrong@example.com',
          password: 'password123'
        });

      expect(res.statusCode).toBe(401);
      expect(res.body.error).toBe('Invalid email or password');
    });

    it('should return 401 for invalid password', async () => {
      const mockUser = {
        id: '123',
        email: 'test@example.com',
        isActive: true,
        comparePassword: jest.fn().mockResolvedValue(false)
      };

      User.findOne.mockResolvedValue(mockUser);

      const res = await request(app)
        .post('/api/v1/users/login')
        .send({
          email: 'test@example.com',
          password: 'wrongpassword'
        });

      expect(res.statusCode).toBe(401);
      expect(res.body.error).toBe('Invalid email or password');
    });
  });

  describe('GET /api/v1/users/profile', () => {
    it('should return 401 without token', async () => {
      const res = await request(app).get('/api/v1/users/profile');

      expect(res.statusCode).toBe(401);
    });

    it('should return profile with valid token', async () => {
      const mockUser = {
        id: '123',
        email: 'test@example.com',
        firstName: 'Test',
        toJSON: () => ({
          id: '123',
          email: 'test@example.com',
          firstName: 'Test'
        })
      };

      User.findByPk.mockResolvedValue(mockUser);

      const token = jwt.sign(
        { userId: '123', email: 'test@example.com' },
        process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-this-in-production'
      );

      const res = await request(app)
        .get('/api/v1/users/profile')
        .set('Authorization', `Bearer ${token}`);

      expect(res.statusCode).toBe(200);
      expect(res.body.email).toBe('test@example.com');
    });
  });
});

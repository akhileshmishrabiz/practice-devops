const request = require('supertest');
const express = require('express');
const jwt = require('jsonwebtoken');

// Mock Redis client
const mockRedisClient = {
  get: jest.fn(),
  setEx: jest.fn(),
  del: jest.fn(),
  ping: jest.fn().mockResolvedValue('PONG')
};

jest.mock('../src/config/redis', () => ({
  redisClient: mockRedisClient,
  connectRedis: jest.fn().mockResolvedValue(true)
}));

// Mock axios for product service calls
jest.mock('axios', () => ({
  get: jest.fn()
}));

const axios = require('axios');
const cartController = require('../src/controllers/cartController');
const { authenticate } = require('../src/middleware/auth');

// Setup test app
const app = express();
app.use(express.json());

// Auth middleware for tests
app.use('/api/v1/cart', authenticate);
app.get('/api/v1/cart', cartController.getCart);
app.post('/api/v1/cart/items', cartController.addItem);
app.put('/api/v1/cart/items/:productId', cartController.updateItem);
app.delete('/api/v1/cart/items/:productId', cartController.removeItem);
app.delete('/api/v1/cart', cartController.clearCart);
app.get('/health', async (req, res) => {
  try {
    await mockRedisClient.ping();
    res.json({ status: 'healthy', service: 'cart-service', redis: 'connected' });
  } catch {
    res.status(503).json({ status: 'unhealthy' });
  }
});

const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-this-in-production';
const validToken = jwt.sign({ userId: 'test-user-123', email: 'test@example.com' }, JWT_SECRET);

describe('Cart Service Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('should return healthy status', async () => {
      const res = await request(app).get('/health');

      expect(res.statusCode).toBe(200);
      expect(res.body.status).toBe('healthy');
      expect(res.body.redis).toBe('connected');
    });
  });

  describe('GET /api/v1/cart', () => {
    it('should return empty cart when no items', async () => {
      mockRedisClient.get.mockResolvedValue(null);

      const res = await request(app)
        .get('/api/v1/cart')
        .set('Authorization', `Bearer ${validToken}`);

      expect(res.statusCode).toBe(200);
      expect(res.body.items).toEqual([]);
      expect(res.body.total).toBe(0);
      expect(res.body.itemCount).toBe(0);
    });

    it('should return cart with items', async () => {
      const cartData = {
        items: [
          { productId: 1, name: 'Test Product', price: 99.99, quantity: 2 }
        ]
      };
      mockRedisClient.get.mockResolvedValue(JSON.stringify(cartData));

      const res = await request(app)
        .get('/api/v1/cart')
        .set('Authorization', `Bearer ${validToken}`);

      expect(res.statusCode).toBe(200);
      expect(res.body.items.length).toBe(1);
      expect(res.body.total).toBe(199.98);
      expect(res.body.itemCount).toBe(2);
    });

    it('should return 401 without token', async () => {
      const res = await request(app).get('/api/v1/cart');

      expect(res.statusCode).toBe(401);
    });
  });

  describe('POST /api/v1/cart/items', () => {
    it('should add item to empty cart', async () => {
      mockRedisClient.get.mockResolvedValue(null);
      mockRedisClient.setEx.mockResolvedValue('OK');

      axios.get.mockImplementation((url) => {
        if (url.includes('/stock/check')) {
          return Promise.resolve({ data: { available: true } });
        }
        return Promise.resolve({
          data: { id: 1, name: 'Test Product', price: 50.00, is_active: true }
        });
      });

      const res = await request(app)
        .post('/api/v1/cart/items')
        .set('Authorization', `Bearer ${validToken}`)
        .send({ productId: 1, quantity: 2 });

      expect(res.statusCode).toBe(201);
      expect(res.body.message).toBe('Item added to cart');
      expect(res.body.items.length).toBe(1);
    });

    it('should return 400 without product ID', async () => {
      const res = await request(app)
        .post('/api/v1/cart/items')
        .set('Authorization', `Bearer ${validToken}`)
        .send({ quantity: 2 });

      expect(res.statusCode).toBe(400);
      expect(res.body.error).toBe('Product ID is required');
    });

    it('should return 404 for non-existent product', async () => {
      axios.get.mockRejectedValue({ response: { status: 404 } });

      const res = await request(app)
        .post('/api/v1/cart/items')
        .set('Authorization', `Bearer ${validToken}`)
        .send({ productId: 999, quantity: 1 });

      expect(res.statusCode).toBe(404);
      expect(res.body.error).toBe('Product not found');
    });
  });

  describe('DELETE /api/v1/cart', () => {
    it('should clear the cart', async () => {
      mockRedisClient.del.mockResolvedValue(1);

      const res = await request(app)
        .delete('/api/v1/cart')
        .set('Authorization', `Bearer ${validToken}`);

      expect(res.statusCode).toBe(200);
      expect(res.body.message).toBe('Cart cleared');
      expect(res.body.items).toEqual([]);
      expect(mockRedisClient.del).toHaveBeenCalled();
    });
  });

  describe('DELETE /api/v1/cart/items/:productId', () => {
    it('should remove item from cart', async () => {
      const cartData = {
        items: [
          { productId: 1, name: 'Product 1', price: 50.00, quantity: 1 },
          { productId: 2, name: 'Product 2', price: 30.00, quantity: 1 }
        ]
      };
      mockRedisClient.get.mockResolvedValue(JSON.stringify(cartData));
      mockRedisClient.setEx.mockResolvedValue('OK');

      const res = await request(app)
        .delete('/api/v1/cart/items/1')
        .set('Authorization', `Bearer ${validToken}`);

      expect(res.statusCode).toBe(200);
      expect(res.body.items.length).toBe(1);
      expect(res.body.items[0].productId).toBe(2);
    });

    it('should return 404 if cart is empty', async () => {
      mockRedisClient.get.mockResolvedValue(null);

      const res = await request(app)
        .delete('/api/v1/cart/items/1')
        .set('Authorization', `Bearer ${validToken}`);

      expect(res.statusCode).toBe(404);
      expect(res.body.error).toBe('Cart is empty');
    });
  });
});

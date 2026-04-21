const { redisClient } = require('../config/redis');
const axios = require('axios');
const logger = require('../utils/logger');

const CART_EXPIRY = 7 * 24 * 60 * 60; // 7 days in seconds
const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL || 'http://localhost:8001';

/**
 * Generate cart key for Redis
 */
const getCartKey = (userId) => `cart:${userId}`;

/**
 * Fetch product details from Product Service
 */
const fetchProductDetails = async (productId) => {
  try {
    const response = await axios.get(`${PRODUCT_SERVICE_URL}/api/v1/products/${productId}`);
    return response.data;
  } catch (error) {
    if (error.response && error.response.status === 404) {
      return null;
    }
    logger.error('Failed to fetch product details', {
      productId,
      error: error.message
    });
    throw new Error('Failed to fetch product details');
  }
};

/**
 * Check product stock availability
 */
const checkProductStock = async (productId, quantity) => {
  try {
    const response = await axios.get(
      `${PRODUCT_SERVICE_URL}/api/v1/products/${productId}/stock/check?quantity=${quantity}`
    );
    return response.data.available;
  } catch (error) {
    logger.error('Failed to check product stock', {
      productId,
      quantity,
      error: error.message
    });
    return false;
  }
};

/**
 * Get cart items
 */
exports.getCart = async (req, res) => {
  try {
    const userId = req.user.userId;
    const cartKey = getCartKey(userId);

    // Get cart from Redis
    const cartData = await redisClient.get(cartKey);

    if (!cartData) {
      return res.json({
        items: [],
        total: 0,
        itemCount: 0
      });
    }

    const cart = JSON.parse(cartData);

    // Calculate totals
    const total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const itemCount = cart.items.reduce((sum, item) => sum + item.quantity, 0);

    res.json({
      items: cart.items,
      total: parseFloat(total.toFixed(2)),
      itemCount
    });
  } catch (error) {
    logger.error('Failed to get cart', { error: error.message });
    res.status(500).json({ error: 'Failed to retrieve cart' });
  }
};

/**
 * Add item to cart
 */
exports.addItem = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { productId, quantity = 1 } = req.body;

    if (!productId) {
      return res.status(400).json({ error: 'Product ID is required' });
    }

    if (quantity < 1) {
      return res.status(400).json({ error: 'Quantity must be at least 1' });
    }

    // Fetch product details
    const product = await fetchProductDetails(productId);
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Check if product is active
    if (!product.is_active) {
      return res.status(400).json({ error: 'Product is not available' });
    }

    // Check stock availability
    const stockAvailable = await checkProductStock(productId, quantity);
    if (!stockAvailable) {
      return res.status(400).json({ error: 'Insufficient stock' });
    }

    const cartKey = getCartKey(userId);

    // Get existing cart
    const cartData = await redisClient.get(cartKey);
    let cart = cartData ? JSON.parse(cartData) : { items: [] };

    // Check if item already exists in cart
    const existingItemIndex = cart.items.findIndex(
      item => item.productId === parseInt(productId)
    );

    if (existingItemIndex > -1) {
      // Update quantity
      cart.items[existingItemIndex].quantity += quantity;
    } else {
      // Add new item
      cart.items.push({
        productId: product.id,
        name: product.name,
        price: product.price,
        quantity,
        imageUrl: product.image_url || product.imageURL
      });
    }

    // Save cart to Redis with expiry
    await redisClient.setEx(cartKey, CART_EXPIRY, JSON.stringify(cart));

    logger.info('Item added to cart', { userId, productId, quantity });

    // Calculate totals
    const total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const itemCount = cart.items.reduce((sum, item) => sum + item.quantity, 0);

    res.status(201).json({
      message: 'Item added to cart',
      items: cart.items,
      total: parseFloat(total.toFixed(2)),
      itemCount
    });
  } catch (error) {
    logger.error('Failed to add item to cart', { error: error.message });
    res.status(500).json({ error: 'Failed to add item to cart' });
  }
};

/**
 * Update item quantity
 */
exports.updateItem = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { productId } = req.params;
    const { quantity } = req.body;

    if (quantity < 1) {
      return res.status(400).json({ error: 'Quantity must be at least 1' });
    }

    // Check stock availability
    const stockAvailable = await checkProductStock(productId, quantity);
    if (!stockAvailable) {
      return res.status(400).json({ error: 'Insufficient stock' });
    }

    const cartKey = getCartKey(userId);

    // Get cart
    const cartData = await redisClient.get(cartKey);
    if (!cartData) {
      return res.status(404).json({ error: 'Cart is empty' });
    }

    const cart = JSON.parse(cartData);

    // Find item
    const itemIndex = cart.items.findIndex(
      item => item.productId === parseInt(productId)
    );

    if (itemIndex === -1) {
      return res.status(404).json({ error: 'Item not found in cart' });
    }

    // Update quantity
    cart.items[itemIndex].quantity = quantity;

    // Save cart
    await redisClient.setEx(cartKey, CART_EXPIRY, JSON.stringify(cart));

    logger.info('Cart item updated', { userId, productId, quantity });

    // Calculate totals
    const total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const itemCount = cart.items.reduce((sum, item) => sum + item.quantity, 0);

    res.json({
      message: 'Cart updated',
      items: cart.items,
      total: parseFloat(total.toFixed(2)),
      itemCount
    });
  } catch (error) {
    logger.error('Failed to update cart item', { error: error.message });
    res.status(500).json({ error: 'Failed to update cart item' });
  }
};

/**
 * Remove item from cart
 */
exports.removeItem = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { productId } = req.params;

    const cartKey = getCartKey(userId);

    // Get cart
    const cartData = await redisClient.get(cartKey);
    if (!cartData) {
      return res.status(404).json({ error: 'Cart is empty' });
    }

    const cart = JSON.parse(cartData);

    // Filter out the item
    const initialLength = cart.items.length;
    cart.items = cart.items.filter(item => item.productId !== parseInt(productId));

    if (cart.items.length === initialLength) {
      return res.status(404).json({ error: 'Item not found in cart' });
    }

    // Save cart or delete if empty
    if (cart.items.length === 0) {
      await redisClient.del(cartKey);
    } else {
      await redisClient.setEx(cartKey, CART_EXPIRY, JSON.stringify(cart));
    }

    logger.info('Item removed from cart', { userId, productId });

    // Calculate totals
    const total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const itemCount = cart.items.reduce((sum, item) => sum + item.quantity, 0);

    res.json({
      message: 'Item removed from cart',
      items: cart.items,
      total: parseFloat(total.toFixed(2)),
      itemCount
    });
  } catch (error) {
    logger.error('Failed to remove cart item', { error: error.message });
    res.status(500).json({ error: 'Failed to remove cart item' });
  }
};

/**
 * Clear cart
 */
exports.clearCart = async (req, res) => {
  try {
    const userId = req.user.userId;
    const cartKey = getCartKey(userId);

    await redisClient.del(cartKey);

    logger.info('Cart cleared', { userId });

    res.json({
      message: 'Cart cleared',
      items: [],
      total: 0,
      itemCount: 0
    });
  } catch (error) {
    logger.error('Failed to clear cart', { error: error.message });
    res.status(500).json({ error: 'Failed to clear cart' });
  }
};

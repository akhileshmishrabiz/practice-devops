const express = require('express');
const router = express.Router();
const cartController = require('../controllers/cartController');
const { authenticate } = require('../middleware/auth');

// All cart routes require authentication
router.use('/cart', authenticate);

// Cart routes
router.get('/cart', cartController.getCart);
router.post('/cart/items', cartController.addItem);
router.put('/cart/items/:productId', cartController.updateItem);
router.delete('/cart/items/:productId', cartController.removeItem);
router.delete('/cart', cartController.clearCart);

module.exports = router;

const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const { authenticate } = require('../middleware/auth');
const {
  registerValidation,
  loginValidation,
  updateProfileValidation,
  changePasswordValidation,
  validate
} = require('../middleware/validation');

// Public routes
router.post(
  '/users/register',
  registerValidation,
  validate,
  authController.register
);

router.post(
  '/users/login',
  loginValidation,
  validate,
  authController.login
);

// Protected routes (require authentication)
router.get(
  '/users/profile',
  authenticate,
  authController.getProfile
);

router.put(
  '/users/profile',
  authenticate,
  updateProfileValidation,
  validate,
  authController.updateProfile
);

router.put(
  '/users/change-password',
  authenticate,
  changePasswordValidation,
  validate,
  authController.changePassword
);

module.exports = router;

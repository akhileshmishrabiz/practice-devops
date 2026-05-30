import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || '/api';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Add token to requests if available
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Products API
export const getProducts = (params) => api.get('/products', { params });
export const getProduct = (id) => api.get(`/products/${id}`);

// Auth API
export const register = (userData) => api.post('/users/register', userData);
export const login = (credentials) => api.post('/users/login', credentials);
export const getProfile = () => api.get('/users/profile');

// Cart API
export const getCart = () => api.get('/cart');
export const addToCart = (item) => api.post('/cart/items', item);
export const updateCartItem = (productId, quantity) =>
  api.put(`/cart/items/${productId}`, { quantity });
export const removeFromCart = (productId) => api.delete(`/cart/items/${productId}`);
export const clearCart = () => api.delete('/cart');

// Orders API
export const createOrder = (orderData) => api.post('/orders', orderData);
export const getOrders = () => api.get('/orders');
export const getOrder = (id) => api.get(`/orders/${id}`);

// Health/Status API
export const getServiceHealth = async (serviceName) => {
  try {
    const response = await api.get(`/health/${serviceName}`, { timeout: 5000 });
    return { service: serviceName, status: 'healthy', data: response.data };
  } catch (err) {
    return { service: serviceName, status: 'unhealthy', error: err.message };
  }
};

export const getAllServicesHealth = async () => {
  const services = [
    'product-service',
    'user-service',
    'cart-service',
    'order-service',
    'payment-service',
    'notification-service',
  ];
  const results = await Promise.allSettled(
    services.map((s) => getServiceHealth(s))
  );
  return results.map((r) => (r.status === 'fulfilled' ? r.value : { service: 'unknown', status: 'unhealthy' }));
};

export default api;

import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getOrders } from '../services/api';
import { useAuth } from '../context/AuthContext';
import './OrdersPage.css';

const OrdersPage = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) {
      navigate('/login');
      return;
    }
    fetchOrders();
  }, [user]);

  const fetchOrders = async () => {
    try {
      const response = await getOrders();
      setOrders(response.data.orders || []);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <div className="container"><div className="loading">Loading orders...</div></div>;

  return (
    <div className="container">
      <div className="orders-page">
        <h1>My Orders</h1>

        {orders.length === 0 ? (
          <div className="no-orders">
            <p>You haven't placed any orders yet</p>
            <button className="btn-primary" onClick={() => navigate('/')}>
              Start Shopping
            </button>
          </div>
        ) : (
          <div className="orders-list">
            {orders.map((order) => (
              <div key={order.id} className="order-card">
                <div className="order-header">
                  <div>
                    <h3>Order #{order.id}</h3>
                    <p className="order-date">
                      {new Date(order.created_at).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'long',
                        day: 'numeric'
                      })}
                    </p>
                  </div>
                  <div className="order-status">
                    <span className={`status-badge ${order.status}`}>
                      {order.status}
                    </span>
                  </div>
                </div>

                <div className="order-details">
                  <div className="order-info">
                    <p><strong>Shipping Address:</strong></p>
                    <p>{order.shipping_address}</p>
                    <p>{order.city}, {order.state} {order.zip_code}</p>
                    <p>{order.country}</p>
                  </div>

                  <div className="order-items">
                    <p><strong>Items:</strong></p>
                    {order.items && order.items.map((item, idx) => (
                      <div key={idx} className="order-item">
                        <span>{item.product_name || item.name} x {item.quantity}</span>
                        <span>${((item.unit_price || item.price) * item.quantity).toFixed(2)}</span>
                      </div>
                    ))}
                  </div>

                  <div className="order-total">
                    <strong>Total: ${order.total_amount?.toFixed(2)}</strong>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default OrdersPage;

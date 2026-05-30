import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { getProduct, addToCart } from '../services/api';
import { useAuth } from '../context/AuthContext';
import './ProductDetailsPage.css';

const ProductDetailsPage = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [quantity, setQuantity] = useState(1);
  const [adding, setAdding] = useState(false);
  const [message, setMessage] = useState(null);

  useEffect(() => {
    fetchProduct();
  }, [id]);

  const fetchProduct = async () => {
    try {
      const response = await getProduct(id);
      setProduct(response.data);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddToCart = async () => {
    if (!user) {
      navigate('/login');
      return;
    }

    try {
      setAdding(true);
      await addToCart({ productId: parseInt(id), quantity });
      setMessage({ type: 'success', text: 'Added to cart!' });
      setTimeout(() => setMessage(null), 3000);
    } catch (err) {
      setMessage({ type: 'error', text: 'Failed to add to cart' });
    } finally {
      setAdding(false);
    }
  };

  if (loading) return <div className="container"><div className="loading">Loading...</div></div>;
  if (!product) return <div className="container"><div className="error">Product not found</div></div>;

  return (
    <div className="container">
      <div className="product-details">
        <div className="product-image-large">
          {product.image_url ? (
            <img src={product.image_url} alt={product.name} />
          ) : (
            <div className="placeholder-image-large">📦</div>
          )}
        </div>

        <div className="product-details-info">
          <h1>{product.name}</h1>
          <div className="product-category">{product.category}</div>
          <div className="product-price-large">${product.price?.toFixed(2)}</div>

          <p className="product-description-full">{product.description}</p>

          <div className="stock-info">
            {product.stock > 0 ? (
              <span className="in-stock">✓ In Stock ({product.stock} available)</span>
            ) : (
              <span className="out-of-stock">✗ Out of Stock</span>
            )}
          </div>

          {product.stock > 0 && (
            <div className="add-to-cart-section">
              <div className="quantity-selector">
                <label>Quantity:</label>
                <input
                  type="number"
                  min="1"
                  max={product.stock}
                  value={quantity}
                  onChange={(e) => setQuantity(Math.max(1, parseInt(e.target.value) || 1))}
                />
              </div>

              <button
                className="btn-success btn-large"
                onClick={handleAddToCart}
                disabled={adding}
              >
                {adding ? 'Adding...' : '🛒 Add to Cart'}
              </button>

              {message && (
                <div className={`message ${message.type}`}>
                  {message.text}
                </div>
              )}
            </div>
          )}

          <button className="btn-secondary" onClick={() => navigate(-1)}>
            ← Back to Products
          </button>
        </div>
      </div>
    </div>
  );
};

export default ProductDetailsPage;

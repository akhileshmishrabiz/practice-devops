import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getProducts } from '../services/api';
import './HomePage.css';

const HomePage = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');

  useEffect(() => {
    fetchProducts();
  }, [search, category]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const params = {};
      if (search) params.search = search;
      if (category) params.category = category;

      const response = await getProducts(params);
      setProducts(response.data.products || []);
      setError(null);
    } catch (err) {
      console.error('Failed to load products:', err);
      let errorMsg = 'Failed to load products. ';
      if (err.message === 'Network Error') {
        errorMsg += 'Cannot connect to backend API. Make sure services are running.';
      } else if (err.response) {
        errorMsg += err.response.data?.error || err.response.statusText;
      } else {
        errorMsg += err.message;
      }
      setError(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const categories = ['All', 'Electronics', 'Clothing', 'Footwear', 'Accessories', 'Gaming', 'Home & Kitchen'];

  return (
    <div className="container">
      <div className="home-page">
        <h1 className="page-title">Browse Products</h1>

        <div className="filters">
          <input
            type="text"
            placeholder="Search products..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="search-input"
          />

          <div className="category-filter">
            {categories.map((cat) => (
              <button
                key={cat}
                className={`category-btn ${category === (cat === 'All' ? '' : cat) ? 'active' : ''}`}
                onClick={() => setCategory(cat === 'All' ? '' : cat)}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="loading">Loading products...</div>
        ) : error ? (
          <div className="error">{error}</div>
        ) : products.length === 0 ? (
          <div className="no-products">
            <p>No products found.</p>
            <p>Try running: <code>./seed-data.sh</code> to add sample products</p>
          </div>
        ) : (
          <div className="products-grid">
            {products.map((product) => (
              <div key={product.id} className="product-card">
                <div className="product-image">
                  {product.image_url ? (
                    <img src={product.image_url} alt={product.name} />
                  ) : (
                    <div className="placeholder-image">📦</div>
                  )}
                </div>
                <div className="product-info">
                  <h3 className="product-name">{product.name}</h3>
                  <p className="product-description">
                    {product.description?.substring(0, 100)}
                    {product.description?.length > 100 ? '...' : ''}
                  </p>
                  <div className="product-footer">
                    <span className="product-price">${product.price?.toFixed(2)}</span>
                    <span className="product-stock">
                      {product.stock > 0 ? `${product.stock} in stock` : 'Out of stock'}
                    </span>
                  </div>
                  <Link to={`/product/${product.id}`}>
                    <button className="btn-primary btn-full">View Details</button>
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default HomePage;

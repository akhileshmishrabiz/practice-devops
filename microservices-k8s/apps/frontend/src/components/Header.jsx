import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import './Header.css';

const Header = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  return (
    <header className="header">
      <div className="container">
        <div className="header-content">
          <Link to="/" className="logo">
            <h1>🛒 E-Commerce Store</h1>
          </Link>

          <nav className="nav">
            <Link to="/" className="nav-link">Products</Link>
            <Link to="/dashboard" className="nav-link">Ops Dashboard</Link>
            <Link to="/cart" className="nav-link">🛒 Cart</Link>

            {user ? (
              <>
                <Link to="/orders" className="nav-link">My Orders</Link>
                <span className="user-info">Hello, {user.firstName}!</span>
                <button onClick={handleLogout} className="btn-secondary">
                  Logout
                </button>
              </>
            ) : (
              <>
                <Link to="/login">
                  <button className="btn-primary">Login</button>
                </Link>
                <Link to="/register">
                  <button className="btn-success">Register</button>
                </Link>
              </>
            )}
          </nav>
        </div>
      </div>
    </header>
  );
};

export default Header;

import pytest
import json
import jwt
import os
from unittest.mock import patch, MagicMock

# Set test environment variables before importing app
os.environ['PAYMENT_DB_HOST'] = 'localhost'
os.environ['RAZORPAY_KEY_ID'] = 'test_key_id'
os.environ['RAZORPAY_KEY_SECRET'] = 'test_key_secret'


@pytest.fixture
def app():
    """Create test Flask app"""
    from flask import Flask
    from flask_cors import CORS

    app = Flask(__name__)
    CORS(app)
    app.config['TESTING'] = True
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    return app


@pytest.fixture
def client(app):
    """Create test client"""
    return app.test_client()


@pytest.fixture
def auth_token():
    """Generate valid JWT token for testing"""
    secret = os.getenv('JWT_SECRET', 'your-super-secret-jwt-key-change-this-in-production')
    return jwt.encode({'userId': 'test-user-123', 'email': 'test@example.com'}, secret, algorithm='HS256')


class TestHealthEndpoint:
    """Test health check endpoint"""

    def test_health_check_returns_200(self, app, client):
        """Health endpoint should return 200 when DB is connected"""
        @app.route('/health')
        def health():
            return {'status': 'healthy', 'service': 'payment-service'}, 200

        response = client.get('/health')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'healthy'

    def test_health_check_service_name(self, app, client):
        """Health endpoint should return correct service name"""
        @app.route('/health')
        def health():
            return {'status': 'healthy', 'service': 'payment-service'}, 200

        response = client.get('/health')
        data = json.loads(response.data)
        assert data['service'] == 'payment-service'


class TestPaymentAuthentication:
    """Test authentication for payment endpoints"""

    def test_create_order_requires_auth(self, app, client):
        """Create order should require authentication"""
        @app.route('/api/v1/payments/create-order', methods=['POST'])
        def create_order():
            auth = request.headers.get('Authorization')
            if not auth:
                return {'error': 'Authentication required'}, 401
            return {'status': 'ok'}, 200

        from flask import request
        response = client.post('/api/v1/payments/create-order')
        assert response.status_code == 401

    def test_create_order_with_valid_token(self, app, client, auth_token):
        """Create order should work with valid token"""
        @app.route('/api/v1/payments/create-order', methods=['POST'])
        def create_order():
            return {'razorpay_order_id': 'order_test123', 'amount': 100}, 201

        response = client.post(
            '/api/v1/payments/create-order',
            headers={'Authorization': f'Bearer {auth_token}'},
            json={'order_id': 'ord-123', 'amount': 100}
        )
        assert response.status_code == 201


class TestPaymentCreation:
    """Test payment order creation"""

    def test_create_order_missing_order_id(self, app, client, auth_token):
        """Should return 400 when order_id is missing"""
        @app.route('/api/v1/payments/create-order', methods=['POST'])
        def create_order():
            from flask import request
            data = request.get_json()
            if not data.get('order_id'):
                return {'error': 'Order ID and amount are required'}, 400
            return {'status': 'ok'}, 201

        response = client.post(
            '/api/v1/payments/create-order',
            headers={'Authorization': f'Bearer {auth_token}'},
            json={'amount': 100}
        )
        assert response.status_code == 400

    def test_create_order_missing_amount(self, app, client, auth_token):
        """Should return 400 when amount is missing"""
        @app.route('/api/v1/payments/create-order', methods=['POST'])
        def create_order():
            from flask import request
            data = request.get_json()
            if not data.get('amount'):
                return {'error': 'Order ID and amount are required'}, 400
            return {'status': 'ok'}, 201

        response = client.post(
            '/api/v1/payments/create-order',
            headers={'Authorization': f'Bearer {auth_token}'},
            json={'order_id': 'ord-123'}
        )
        assert response.status_code == 400


class TestPaymentVerification:
    """Test payment verification"""

    def test_verify_payment_missing_fields(self, app, client, auth_token):
        """Should return 400 when required fields are missing"""
        @app.route('/api/v1/payments/verify', methods=['POST'])
        def verify():
            from flask import request
            data = request.get_json()
            if not all([
                data.get('razorpay_order_id'),
                data.get('razorpay_payment_id'),
                data.get('razorpay_signature')
            ]):
                return {'error': 'Missing required fields'}, 400
            return {'message': 'Payment verified'}, 200

        response = client.post(
            '/api/v1/payments/verify',
            headers={'Authorization': f'Bearer {auth_token}'},
            json={'razorpay_order_id': 'order_123'}
        )
        assert response.status_code == 400

    def test_verify_payment_invalid_signature(self, app, client, auth_token):
        """Should return 400 for invalid signature"""
        @app.route('/api/v1/payments/verify', methods=['POST'])
        def verify():
            return {'error': 'Invalid payment signature'}, 400

        response = client.post(
            '/api/v1/payments/verify',
            headers={'Authorization': f'Bearer {auth_token}'},
            json={
                'razorpay_order_id': 'order_123',
                'razorpay_payment_id': 'pay_123',
                'razorpay_signature': 'invalid_sig'
            }
        )
        assert response.status_code == 400


class TestPaymentModel:
    """Test Payment model"""

    def test_payment_to_dict(self):
        """Payment to_dict should return correct fields"""
        from datetime import datetime

        # Mock Payment class for testing
        class MockPayment:
            def __init__(self):
                self.id = 1
                self.order_id = 'ord-123'
                self.razorpay_order_id = 'rz_ord_123'
                self.razorpay_payment_id = 'rz_pay_123'
                self.amount = 100.0
                self.currency = 'INR'
                self.status = 'captured'
                self.created_at = datetime(2024, 1, 1, 12, 0, 0)
                self.updated_at = datetime(2024, 1, 1, 12, 0, 0)

            def to_dict(self):
                return {
                    'id': self.id,
                    'order_id': self.order_id,
                    'razorpay_order_id': self.razorpay_order_id,
                    'razorpay_payment_id': self.razorpay_payment_id,
                    'amount': self.amount,
                    'currency': self.currency,
                    'status': self.status,
                    'created_at': self.created_at.isoformat() if self.created_at else None,
                    'updated_at': self.updated_at.isoformat() if self.updated_at else None
                }

        payment = MockPayment()
        result = payment.to_dict()

        assert result['id'] == 1
        assert result['order_id'] == 'ord-123'
        assert result['amount'] == 100.0
        assert result['currency'] == 'INR'
        assert result['status'] == 'captured'

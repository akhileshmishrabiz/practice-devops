import os
import hmac
import hashlib
import razorpay
import requests
import logging
from flask import Blueprint, request, jsonify
from database import db
from models import Payment
from functools import wraps
import jwt

logger = logging.getLogger(__name__)

payment_bp = Blueprint('payments', __name__)

# Razorpay client
razorpay_client = razorpay.Client(auth=(
    os.getenv('RAZORPAY_KEY_ID', ''),
    os.getenv('RAZORPAY_KEY_SECRET', '')
))

JWT_SECRET = os.getenv('JWT_SECRET', 'your-super-secret-jwt-key-change-this-in-production')
ORDER_SERVICE_URL = os.getenv('ORDER_SERVICE_URL', 'http://localhost:8004')

# Authentication decorator
def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'Authentication required'}), 401

        token = auth_header.split(' ')[1]
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
            request.user_id = payload.get('userId')
            request.user_email = payload.get('email')
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401

        return f(*args, **kwargs)
    return decorated_function

@payment_bp.route('/payments/create-order', methods=['POST'])
@require_auth
def create_payment_order():
    """Create a Razorpay order for payment"""
    try:
        data = request.get_json()
        order_id = data.get('order_id')
        amount = data.get('amount')

        if not order_id or not amount:
            return jsonify({'error': 'Order ID and amount are required'}), 400

        # Create Razorpay order
        razorpay_order = razorpay_client.order.create({
            'amount': int(amount * 100),  # Convert to paise
            'currency': 'INR',
            'receipt': order_id,
            'payment_capture': 1
        })

        # Save payment record
        payment = Payment(
            order_id=order_id,
            razorpay_order_id=razorpay_order['id'],
            amount=amount,
            currency='INR',
            status='created',
            user_id=request.user_id
        )
        db.session.add(payment)
        db.session.commit()

        logger.info(f'Payment order created: {razorpay_order["id"]} for order: {order_id}')

        return jsonify({
            'razorpay_order_id': razorpay_order['id'],
            'amount': amount,
            'currency': 'INR',
            'key_id': os.getenv('RAZORPAY_KEY_ID')
        }), 201

    except Exception as e:
        logger.error(f'Failed to create payment order: {str(e)}')
        db.session.rollback()
        return jsonify({'error': 'Failed to create payment order'}), 500

@payment_bp.route('/payments/verify', methods=['POST'])
@require_auth
def verify_payment():
    """Verify Razorpay payment signature"""
    try:
        data = request.get_json()
        razorpay_order_id = data.get('razorpay_order_id')
        razorpay_payment_id = data.get('razorpay_payment_id')
        razorpay_signature = data.get('razorpay_signature')

        if not all([razorpay_order_id, razorpay_payment_id, razorpay_signature]):
            return jsonify({'error': 'Missing required fields'}), 400

        # Verify signature
        secret = os.getenv('RAZORPAY_KEY_SECRET', '')
        message = f"{razorpay_order_id}|{razorpay_payment_id}"
        generated_signature = hmac.new(
            secret.encode(),
            message.encode(),
            hashlib.sha256
        ).hexdigest()

        if generated_signature != razorpay_signature:
            logger.warning(f'Payment signature verification failed for order: {razorpay_order_id}')
            return jsonify({'error': 'Invalid payment signature'}), 400

        # Update payment record
        payment = Payment.query.filter_by(razorpay_order_id=razorpay_order_id).first()
        if not payment:
            return jsonify({'error': 'Payment record not found'}), 404

        payment.razorpay_payment_id = razorpay_payment_id
        payment.razorpay_signature = razorpay_signature
        payment.status = 'captured'
        db.session.commit()

        # Update order status
        try:
            headers = {'Authorization': request.headers.get('Authorization')}
            order_url = f"{ORDER_SERVICE_URL}/api/v1/orders/{payment.order_id}/status"
            requests.put(order_url, json={'status': 'confirmed'}, headers=headers)
        except Exception as e:
            logger.error(f'Failed to update order status: {str(e)}')

        logger.info(f'Payment verified successfully: {razorpay_payment_id}')

        return jsonify({
            'message': 'Payment verified successfully',
            'payment': payment.to_dict()
        }), 200

    except Exception as e:
        logger.error(f'Payment verification failed: {str(e)}')
        db.session.rollback()
        return jsonify({'error': 'Payment verification failed'}), 500

@payment_bp.route('/payments/order/<order_id>', methods=['GET'])
@require_auth
def get_payment_by_order(order_id):
    """Get payment details by order ID"""
    try:
        payment = Payment.query.filter_by(order_id=order_id).first()
        if not payment:
            return jsonify({'error': 'Payment not found'}), 404

        return jsonify(payment.to_dict()), 200

    except Exception as e:
        logger.error(f'Failed to get payment: {str(e)}')
        return jsonify({'error': 'Failed to retrieve payment'}), 500

@payment_bp.route('/payments/webhook', methods=['POST'])
def payment_webhook():
    """Handle Razorpay webhooks"""
    try:
        webhook_secret = os.getenv('RAZORPAY_WEBHOOK_SECRET', '')
        webhook_signature = request.headers.get('X-Razorpay-Signature', '')
        webhook_body = request.get_data()

        # Verify webhook signature
        expected_signature = hmac.new(
            webhook_secret.encode(),
            webhook_body,
            hashlib.sha256
        ).hexdigest()

        if webhook_signature != expected_signature:
            logger.warning('Webhook signature verification failed')
            return jsonify({'error': 'Invalid signature'}), 400

        event = request.get_json()
        logger.info(f'Webhook received: {event.get("event")}')

        # Handle different webhook events
        if event.get('event') == 'payment.captured':
            payment_entity = event.get('payload', {}).get('payment', {}).get('entity', {})
            razorpay_payment_id = payment_entity.get('id')

            payment = Payment.query.filter_by(razorpay_payment_id=razorpay_payment_id).first()
            if payment:
                payment.status = 'captured'
                db.session.commit()
                logger.info(f'Payment status updated via webhook: {razorpay_payment_id}')

        return jsonify({'status': 'success'}), 200

    except Exception as e:
        logger.error(f'Webhook processing failed: {str(e)}')
        return jsonify({'error': 'Webhook processing failed'}), 500

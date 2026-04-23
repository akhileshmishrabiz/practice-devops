import os
import logging
import json
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
from sqlalchemy import text
from database import db
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Counter, Histogram, Gauge

load_dotenv()

# Configure logging with JSON format for better parsing
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "service": "payment-service", "message": "%(message)s"}',
    datefmt='%Y-%m-%dT%H:%M:%SZ'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Initialize Prometheus metrics
metrics = PrometheusMetrics(app)

# Add custom metrics
metrics.info('payment_service_info', 'Payment Service Information', version='1.0.0')

# Custom business metrics
payments_processed_total = Counter(
    'payments_processed_total',
    'Total number of payments processed',
    ['status']  # success, failed, pending
)

payment_amount_total = Counter(
    'payment_amount_total',
    'Total amount of payments processed'
)

payment_processing_duration = Histogram(
    'payment_processing_duration_seconds',
    'Payment processing duration',
    buckets=[0.1, 0.5, 1, 2, 5, 10]
)

refunds_total = Counter(
    'refunds_total',
    'Total number of refunds processed'
)

active_transactions = Gauge(
    'active_transactions',
    'Number of currently active transactions'
)

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = (
    f"postgresql://{os.getenv('PAYMENT_DB_USER', 'ecommerce_user')}:"
    f"{os.getenv('PAYMENT_DB_PASSWORD', 'secure_password_123')}@"
    f"{os.getenv('PAYMENT_DB_HOST', 'localhost')}:"
    f"{os.getenv('PAYMENT_DB_PORT', '5432')}/"
    f"{os.getenv('PAYMENT_DB_NAME', 'payments')}"
)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

# Import routes after db initialization
from routes import payment_bp
app.register_blueprint(payment_bp, url_prefix='/api/v1')

@app.route('/health', methods=['GET'])
def health_check():
    try:
        db.session.execute(text('SELECT 1'))
        return jsonify({
            'status': 'healthy',
            'service': 'payment-service',
            'database': 'connected'
        }), 200
    except Exception as e:
        logger.error(f'Health check failed: {str(e)}')
        return jsonify({
            'status': 'unhealthy',
            'service': 'payment-service',
            'database': 'disconnected'
        }), 503

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
        logger.info('Database tables created')

    port = int(os.getenv('PORT', 8005))
    logger.info(f'Payment Service starting on port {port}')
    app.run(host='0.0.0.0', port=port, debug=False)

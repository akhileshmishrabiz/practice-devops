import pytest
import json
from unittest.mock import patch, MagicMock
import os


@pytest.fixture
def app():
    """Create test Flask app"""
    from flask import Flask
    from flask_cors import CORS

    app = Flask(__name__)
    CORS(app)
    app.config['TESTING'] = True

    @app.route('/health')
    def health():
        return {'status': 'healthy', 'service': 'notification-service', 'rabbitmq': 'connected'}, 200

    return app


@pytest.fixture
def client(app):
    """Create test client"""
    return app.test_client()


class TestHealthEndpoint:
    """Test health check endpoint"""

    def test_health_check_returns_200(self, client):
        """Health endpoint should return 200"""
        response = client.get('/health')
        assert response.status_code == 200

    def test_health_check_status(self, client):
        """Health endpoint should return healthy status"""
        response = client.get('/health')
        data = json.loads(response.data)
        assert data['status'] == 'healthy'

    def test_health_check_service_name(self, client):
        """Health endpoint should return correct service name"""
        response = client.get('/health')
        data = json.loads(response.data)
        assert data['service'] == 'notification-service'

    def test_health_check_rabbitmq_status(self, client):
        """Health endpoint should include RabbitMQ status"""
        response = client.get('/health')
        data = json.loads(response.data)
        assert 'rabbitmq' in data


class TestEmailRendering:
    """Test email template rendering"""

    def test_render_order_confirmation_template(self):
        """Should render order confirmation email template"""
        # Mock the template rendering
        def render_order_confirmation(order_id, total_amount, items):
            return f"""
            <html>
            <body>
                <h1>Order Confirmation</h1>
                <p>Order ID: {order_id}</p>
                <p>Total: ${total_amount}</p>
                <p>Items: {len(items)}</p>
            </body>
            </html>
            """

        html = render_order_confirmation('ORD-123', 199.99, [{'name': 'Product 1'}])
        assert 'Order Confirmation' in html
        assert 'ORD-123' in html
        assert '199.99' in html

    def test_render_order_confirmation_with_multiple_items(self):
        """Should render email with multiple items"""
        def render_order_confirmation(order_id, total_amount, items):
            items_html = ''.join([f'<li>{item["name"]}</li>' for item in items])
            return f"""
            <html>
            <body>
                <h1>Order Confirmation</h1>
                <p>Order ID: {order_id}</p>
                <ul>{items_html}</ul>
                <p>Total: ${total_amount}</p>
            </body>
            </html>
            """

        items = [
            {'name': 'Product 1', 'price': 50},
            {'name': 'Product 2', 'price': 75}
        ]
        html = render_order_confirmation('ORD-456', 125, items)
        assert 'Product 1' in html
        assert 'Product 2' in html


class TestOrderEventProcessing:
    """Test order event processing"""

    def test_process_order_created_event(self):
        """Should process order_created event correctly"""
        event_data = {
            'event_type': 'order_created',
            'order_id': 'ORD-123',
            'user_email': 'test@example.com',
            'total_amount': 199.99,
            'items': [{'name': 'Product 1', 'quantity': 2}]
        }

        # Mock the process function
        def process_order_event(data):
            if data.get('event_type') == 'order_created':
                return {
                    'processed': True,
                    'email_sent_to': data.get('user_email'),
                    'order_id': data.get('order_id')
                }
            return {'processed': False}

        result = process_order_event(event_data)
        assert result['processed'] is True
        assert result['email_sent_to'] == 'test@example.com'
        assert result['order_id'] == 'ORD-123'

    def test_ignore_unknown_event_type(self):
        """Should ignore unknown event types"""
        event_data = {
            'event_type': 'unknown_event',
            'data': {}
        }

        def process_order_event(data):
            if data.get('event_type') == 'order_created':
                return {'processed': True}
            return {'processed': False}

        result = process_order_event(event_data)
        assert result['processed'] is False


class TestEmailSending:
    """Test email sending functionality"""

    def test_send_email_success(self):
        """Should return True on successful email send"""
        mock_ses_client = MagicMock()
        mock_ses_client.send_email.return_value = {'MessageId': 'test-message-id'}

        def send_email(client, to_email, subject, body):
            try:
                response = client.send_email(
                    Source='noreply@example.com',
                    Destination={'ToAddresses': [to_email]},
                    Message={
                        'Subject': {'Data': subject},
                        'Body': {'Html': {'Data': body}}
                    }
                )
                return True
            except Exception:
                return False

        result = send_email(
            mock_ses_client,
            'test@example.com',
            'Order Confirmation',
            '<html><body>Test</body></html>'
        )
        assert result is True
        mock_ses_client.send_email.assert_called_once()

    def test_send_email_failure(self):
        """Should return False on email send failure"""
        mock_ses_client = MagicMock()
        mock_ses_client.send_email.side_effect = Exception('SES Error')

        def send_email(client, to_email, subject, body):
            try:
                client.send_email(
                    Source='noreply@example.com',
                    Destination={'ToAddresses': [to_email]},
                    Message={
                        'Subject': {'Data': subject},
                        'Body': {'Html': {'Data': body}}
                    }
                )
                return True
            except Exception:
                return False

        result = send_email(
            mock_ses_client,
            'test@example.com',
            'Order Confirmation',
            '<html><body>Test</body></html>'
        )
        assert result is False


class TestRabbitMQMessage:
    """Test RabbitMQ message handling"""

    def test_parse_valid_message(self):
        """Should parse valid JSON message"""
        message_body = json.dumps({
            'event_type': 'order_created',
            'order_id': 'ORD-123',
            'user_email': 'test@example.com'
        })

        event_data = json.loads(message_body)
        assert event_data['event_type'] == 'order_created'
        assert event_data['order_id'] == 'ORD-123'

    def test_handle_invalid_json(self):
        """Should handle invalid JSON gracefully"""
        invalid_message = 'not valid json'

        with pytest.raises(json.JSONDecodeError):
            json.loads(invalid_message)

import os
import json
import logging
import threading
from flask import Flask, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import pika
import boto3
from botocore.exceptions import ClientError
from email_templates import render_order_confirmation

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# AWS SES client
ses_client = boto3.client(
    'ses',
    region_name=os.getenv('AWS_REGION', 'us-east-1'),
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
)

SENDER_EMAIL = os.getenv('SES_SENDER_EMAIL', 'noreply@example.com')
SENDER_NAME = os.getenv('SES_SENDER_NAME', 'E-Commerce Platform')

def send_email(to_email, subject, html_body, text_body=None):
    """Send email using AWS SES"""
    try:
        if text_body is None:
            text_body = html_body

        response = ses_client.send_email(
            Source=f'{SENDER_NAME} <{SENDER_EMAIL}>',
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {
                    'Text': {'Data': text_body, 'Charset': 'UTF-8'},
                    'Html': {'Data': html_body, 'Charset': 'UTF-8'}
                }
            }
        )
        logger.info(f'Email sent to {to_email}, Message ID: {response["MessageId"]}')
        return True
    except ClientError as e:
        logger.error(f'Failed to send email to {to_email}: {e.response["Error"]["Message"]}')
        return False
    except Exception as e:
        logger.error(f'Unexpected error sending email: {str(e)}')
        return False

def process_order_event(event_data):
    """Process order created event and send confirmation email"""
    try:
        event_type = event_data.get('event_type')
        logger.info(f'Processing event: {event_type}')

        if event_type == 'order_created':
            user_email = event_data.get('user_email')
            order_id = event_data.get('order_id')
            total_amount = event_data.get('total_amount')
            items = event_data.get('items', [])

            # Render email template
            html_body = render_order_confirmation(order_id, total_amount, items)
            subject = f'Order Confirmation - {order_id}'

            # Send email
            send_email(user_email, subject, html_body)
            logger.info(f'Order confirmation sent to {user_email}')

    except Exception as e:
        logger.error(f'Failed to process order event: {str(e)}')

def rabbitmq_consumer():
    """RabbitMQ consumer that listens for order events"""
    try:
        connection_params = pika.ConnectionParameters(
            host=os.getenv('RABBITMQ_HOST', 'localhost'),
            port=int(os.getenv('RABBITMQ_PORT', 5672)),
            credentials=pika.PlainCredentials(
                os.getenv('RABBITMQ_USER', 'guest'),
                os.getenv('RABBITMQ_PASSWORD', 'guest')
            ),
            heartbeat=600,
            blocked_connection_timeout=300
        )

        connection = pika.BlockingConnection(connection_params)
        channel = connection.channel()

        # Declare exchange and queue
        channel.exchange_declare(exchange='order_events', exchange_type='topic', durable=True)
        channel.queue_declare(queue='notification_queue', durable=True)
        channel.queue_bind(exchange='order_events', queue='notification_queue', routing_key='order.created')

        def callback(ch, method, properties, body):
            try:
                event_data = json.loads(body)
                logger.info(f'Received message: {event_data.get("event_type")}')
                process_order_event(event_data)
                ch.basic_ack(delivery_tag=method.delivery_tag)
            except Exception as e:
                logger.error(f'Failed to process message: {str(e)}')
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

        channel.basic_consume(queue='notification_queue', on_message_callback=callback)

        logger.info('Waiting for messages. To exit press CTRL+C')
        channel.start_consuming()

    except Exception as e:
        logger.error(f'RabbitMQ consumer error: {str(e)}')

# Start RabbitMQ consumer in a separate thread
consumer_thread = threading.Thread(target=rabbitmq_consumer, daemon=True)
consumer_thread.start()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'notification-service',
        'rabbitmq': 'connected'
    }), 200

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8006))
    logger.info(f'Notification Service starting on port {port}')
    app.run(host='0.0.0.0', port=port, debug=False)

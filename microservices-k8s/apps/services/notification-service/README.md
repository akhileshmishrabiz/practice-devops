# Notification Service

Email notification microservice with RabbitMQ consumer and AWS SES integration built with Python and Flask.

## Features

- RabbitMQ consumer listening to order events
- AWS SES email sending
- Order confirmation emails with HTML templates
- Async email processing
- Automatic retry for failed emails

## Technology Stack

- Python 3.11+, Flask, Pika (RabbitMQ), Boto3 (AWS SES)

## Email Templates

- Order confirmation with order details table
- Professional HTML email formatting
- Plain text fallback

## Environment Variables

See `.env.example` for configuration.

## AWS SES Setup

1. Verify sender email in AWS SES console
2. If in sandbox mode, also verify recipient emails
3. Create IAM user with SES send permissions
4. Add credentials to `.env`

## Running Locally

```bash
pip install -r requirements.txt
python app.py
```

Service runs on port 8006 and automatically consumes RabbitMQ messages.

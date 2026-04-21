# Payment Service

Payment processing microservice with Razorpay integration built with Python and Flask.

## Features

- Create Razorpay payment orders
- Verify payment signatures
- Handle Razorpay webhooks
- Update order status after successful payment
- PostgreSQL for payment records
- JWT authentication

## Technology Stack

- Python 3.11+, Flask, SQLAlchemy, PostgreSQL, Razorpay SDK

## API Endpoints

- `POST /api/v1/payments/create-order` - Create Razorpay order
- `POST /api/v1/payments/verify` - Verify payment
- `GET /api/v1/payments/order/:orderId` - Get payment details
- `POST /api/v1/payments/webhook` - Razorpay webhook handler
- `GET /health` - Health check

## Razorpay Test Card

- Card: 4111 1111 1111 1111
- Expiry: Any future date
- CVV: Any 3 digits

## Environment Variables

See `.env.example` for configuration.

## Running Locally

```bash
pip install -r requirements.txt
python app.py
```

Service runs on port 8005.

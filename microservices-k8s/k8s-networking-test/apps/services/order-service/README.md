# Order Service

Order management microservice built with Go and Gin framework. Handles order creation, status management, and publishes events to RabbitMQ.

## Features

- Create orders from cart items
- Order status management (pending → payment_pending → confirmed → processing → shipped → delivered)
- Get order details and history
- Integration with Cart Service
- RabbitMQ event publishing
- JWT authentication
- PostgreSQL database

## Technology Stack

- Go 1.21+, Gin framework, GORM, PostgreSQL, RabbitMQ

## API Endpoints

- `POST /api/v1/orders` - Create order from cart
- `GET /api/v1/orders/:id` - Get order details
- `GET /api/v1/orders` - Get user order history
- `PUT /api/v1/orders/:id/status` - Update order status
- `GET /health` - Health check

## Environment Variables

See `.env.example` for configuration.

## Running Locally

```bash
go mod download
go run main.go
```

Service runs on port 8004.

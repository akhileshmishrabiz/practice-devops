# Cart Service

A RESTful API service for shopping cart management built with Node.js, Express, and Redis.

## Features

- Add items to cart with product validation
- Update item quantities
- Remove items from cart
- Get cart details with product information
- Clear entire cart
- Redis-based storage for high performance
- Automatic cart expiry (7 days)
- Stock availability checking
- Integration with Product Service
- JWT authentication
- Structured JSON logging

## Technology Stack

- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **Database**: Redis 7
- **HTTP Client**: Axios
- **Authentication**: JWT
- **Logging**: Winston

## API Endpoints

### Health Check
- `GET /health` - Service health check

### Cart Management (All routes require authentication)

#### Get Cart
```
GET /api/v1/cart
Headers:
  Authorization: Bearer {token}

Response:
{
  "items": [
    {
      "productId": 1,
      "name": "Product Name",
      "price": 99.99,
      "quantity": 2,
      "imageUrl": "https://..."
    }
  ],
  "total": 199.98,
  "itemCount": 2
}
```

#### Add Item to Cart
```
POST /api/v1/cart/items
Headers:
  Authorization: Bearer {token}
Body:
{
  "productId": 1,
  "quantity": 2
}

Response:
{
  "message": "Item added to cart",
  "items": [...],
  "total": 199.98,
  "itemCount": 2
}
```

#### Update Item Quantity
```
PUT /api/v1/cart/items/:productId
Headers:
  Authorization: Bearer {token}
Body:
{
  "quantity": 3
}

Response:
{
  "message": "Cart updated",
  "items": [...],
  "total": 299.97,
  "itemCount": 3
}
```

#### Remove Item from Cart
```
DELETE /api/v1/cart/items/:productId
Headers:
  Authorization: Bearer {token}

Response:
{
  "message": "Item removed from cart",
  "items": [...],
  "total": 0,
  "itemCount": 0
}
```

#### Clear Cart
```
DELETE /api/v1/cart
Headers:
  Authorization: Bearer {token}

Response:
{
  "message": "Cart cleared",
  "items": [],
  "total": 0,
  "itemCount": 0
}
```

## Environment Variables

Create a `.env` file in the service root:

```env
# Server
PORT=8003
NODE_ENV=development

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# Product Service
PRODUCT_SERVICE_URL=http://localhost:8001

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production

# Logging
LOG_LEVEL=info
```

## Local Development Setup

### Prerequisites
- Node.js 18 or higher
- Redis 7 or higher
- Product Service running on port 8001
- npm or yarn

### Installation

1. **Navigate to the service directory**
```bash
cd services/cart-service
```

2. **Install dependencies**
```bash
npm install
```

3. **Setup Redis**
```bash
# Install Redis (macOS)
brew install redis

# Start Redis
redis-server

# Or using Docker
docker run -d -p 6379:6379 redis:7-alpine
```

4. **Configure environment variables**
```bash
cp .env.example .env
# Edit .env with your configuration
```

5. **Run the service**
```bash
# Development mode with auto-reload
npm run dev

# Production mode
npm start
```

The service will start on `http://localhost:8003`

### Running with Docker

```bash
# Build image
docker build -t cart-service .

# Run container
docker run -p 8003:8003 \
  -e REDIS_HOST=host.docker.internal \
  -e PRODUCT_SERVICE_URL=http://host.docker.internal:8001 \
  -e JWT_SECRET=your-jwt-secret \
  cart-service
```

## Data Structure

### Redis Cart Storage

Carts are stored in Redis with the following structure:

**Key Format**: `cart:{userId}`

**Value (JSON)**:
```json
{
  "items": [
    {
      "productId": 1,
      "name": "Product Name",
      "price": 99.99,
      "quantity": 2,
      "imageUrl": "https://example.com/image.jpg"
    }
  ]
}
```

**TTL**: 7 days (604,800 seconds)

## Business Logic

### Adding Items to Cart

1. Validate product ID
2. Fetch product details from Product Service
3. Check if product is active
4. Verify stock availability
5. Add/update item in cart
6. Save to Redis with 7-day expiry

### Stock Validation

Before adding or updating items, the service checks stock availability with the Product Service to ensure:
- Product exists
- Product is active
- Sufficient stock is available

### Cart Expiry

- Carts automatically expire after 7 days of inactivity
- Each cart operation resets the expiry timer
- Expired carts are automatically removed by Redis

## Integration with Other Services

### Product Service
- Fetches product details (name, price, image)
- Validates product existence and status
- Checks stock availability

**Endpoints Used**:
- `GET /api/v1/products/:id` - Get product details
- `GET /api/v1/products/:id/stock/check?quantity=N` - Check stock

## Error Handling

The service returns appropriate HTTP status codes:

- `200 OK` - Successful requests
- `201 Created` - Item added to cart
- `400 Bad Request` - Invalid input or insufficient stock
- `401 Unauthorized` - Authentication required or failed
- `404 Not Found` - Cart empty or item not found
- `500 Internal Server Error` - Server errors

Error responses:
```json
{
  "error": "Error message here"
}
```

## Testing

### Manual Testing with cURL

**Get JWT token first** (from User Service):
```bash
TOKEN=$(curl -X POST http://localhost:8002/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john.doe@example.com","password":"Password123!"}' \
  | jq -r '.token')
```

**Add item to cart:**
```bash
curl -X POST http://localhost:8003/api/v1/cart/items \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "productId": 1,
    "quantity": 2
  }'
```

**Get cart:**
```bash
curl http://localhost:8003/api/v1/cart \
  -H "Authorization: Bearer $TOKEN"
```

**Update item quantity:**
```bash
curl -X PUT http://localhost:8003/api/v1/cart/items/1 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"quantity": 5}'
```

**Remove item:**
```bash
curl -X DELETE http://localhost:8003/api/v1/cart/items/1 \
  -H "Authorization: Bearer $TOKEN"
```

**Clear cart:**
```bash
curl -X DELETE http://localhost:8003/api/v1/cart \
  -H "Authorization: Bearer $TOKEN"
```

## Redis Commands

### View cart data in Redis

```bash
# Connect to Redis CLI
redis-cli

# Get all cart keys
KEYS cart:*

# View specific cart
GET cart:{userId}

# Check TTL
TTL cart:{userId}

# Delete cart (for testing)
DEL cart:{userId}
```

## Logging

The service uses Winston for structured JSON logging:

```json
{
  "level": "info",
  "message": "Item added to cart",
  "timestamp": "2024-01-15 10:30:00",
  "userId": "uuid",
  "productId": 1,
  "quantity": 2,
  "service": "cart-service"
}
```

## Security Features

1. **JWT Authentication**: All endpoints require valid JWT token
2. **Product Validation**: Validates products exist and are active
3. **Stock Checking**: Prevents adding out-of-stock items
4. **User Isolation**: Users can only access their own cart

## Performance Considerations

1. **Redis Storage**: Fast in-memory data storage
2. **Connection Pooling**: Efficient Redis connection management
3. **Auto Expiry**: Automatic cleanup of old carts
4. **Minimal Database Calls**: Product details cached in cart

## Production Considerations

1. **Redis Persistence**: Configure Redis persistence (RDB/AOF)
2. **Redis Clustering**: Use Redis Cluster for high availability
3. **Connection Retry**: Automatic reconnection to Redis
4. **Error Handling**: Graceful degradation on service failures
5. **Monitoring**: Monitor Redis memory usage and eviction
6. **Rate Limiting**: Implement rate limiting to prevent abuse

## Future Enhancements

- [ ] Guest cart support (session-based)
- [ ] Cart merge on login
- [ ] Save for later functionality
- [ ] Cart sharing via link
- [ ] Product recommendations in cart
- [ ] Discount/coupon code support
- [ ] Cart abandonment tracking
- [ ] Unit and integration tests
- [ ] GraphQL API
- [ ] Real-time cart updates via WebSocket

## Troubleshooting

### Redis Connection Issues

If you see Redis connection errors:
1. Verify Redis is running: `redis-cli ping`
2. Check Redis host and port in `.env`
3. Verify firewall rules
4. Check Redis logs

### Product Service Integration Issues

If product validation fails:
1. Ensure Product Service is running
2. Check PRODUCT_SERVICE_URL in `.env`
3. Verify network connectivity
4. Check Product Service logs

### Authentication Issues

If you get authentication errors:
1. Ensure JWT_SECRET matches User Service
2. Check token hasn't expired
3. Verify token format: `Bearer {token}`
4. Ensure User Service is accessible

## License

MIT

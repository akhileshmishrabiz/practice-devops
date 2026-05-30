# Product Catalog Service

A RESTful API service for managing product catalog, inventory, and product search built with Go and the Gin framework.

## Features

- Complete CRUD operations for products
- Product search by name and description
- Category-based filtering
- Price range filtering
- Stock management (add, subtract, set)
- Stock availability checking
- Pagination and sorting
- Health check endpoint
- Structured JSON logging
- PostgreSQL database with GORM
- Docker support

## Technology Stack

- **Language**: Go 1.21+
- **Framework**: Gin
- **ORM**: GORM
- **Database**: PostgreSQL 15
- **Logging**: Logrus

## API Endpoints

### Health Check
- `GET /health` - Service health check

### Products

#### List Products
```
GET /api/v1/products
Query Parameters:
  - category: Filter by category
  - is_active: Filter by active status (true/false)
  - min_price: Minimum price filter
  - max_price: Maximum price filter
  - sort_by: Field to sort by (default: created_at)
  - sort_order: asc or desc (default: desc)
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20)
```

#### Get Product by ID
```
GET /api/v1/products/:id
```

#### Create Product
```
POST /api/v1/products
Body:
{
  "name": "Product Name",
  "description": "Product description",
  "price": 99.99,
  "stock": 100,
  "category": "Electronics",
  "image_url": "https://example.com/image.jpg",
  "images": ["https://example.com/image1.jpg", "https://example.com/image2.jpg"],
  "sku": "PROD-001"
}
```

#### Update Product
```
PUT /api/v1/products/:id
Body: (all fields optional)
{
  "name": "Updated Name",
  "price": 89.99,
  "stock": 150,
  "is_active": true
}
```

#### Delete Product
```
DELETE /api/v1/products/:id
```

#### Search Products
```
GET /api/v1/products/search?q=keyword
```

#### Get Products by Category
```
GET /api/v1/products/category/:category
```

#### Get All Categories
```
GET /api/v1/products/categories
```

#### Update Stock
```
PUT /api/v1/products/:id/stock
Body:
{
  "quantity": 10,
  "action": "add|subtract|set"
}
```

#### Check Stock
```
GET /api/v1/products/:id/stock/check?quantity=5
```

## Environment Variables

Create a `.env` file in the service root:

```env
# Server
PORT=8001
GO_ENV=development

# Database
PRODUCT_DB_HOST=localhost
PRODUCT_DB_PORT=5432
PRODUCT_DB_USER=ecommerce_user
PRODUCT_DB_PASSWORD=secure_password_123
PRODUCT_DB_NAME=products

# Logging
LOG_LEVEL=info
```

## Local Development Setup

### Prerequisites
- Go 1.21 or higher
- PostgreSQL 15 or higher
- Make (optional)

### Installation

1. **Clone the repository**
```bash
cd services/product-service
```

2. **Install dependencies**
```bash
go mod download
```

3. **Setup PostgreSQL database**
```bash
createdb products
```

4. **Configure environment variables**
```bash
cp .env.example .env
# Edit .env with your database credentials
```

5. **Run the service**
```bash
go run main.go
```

The service will start on `http://localhost:8001`

### Running with Docker

```bash
# Build image
docker build -t product-service .

# Run container
docker run -p 8001:8001 \
  -e PRODUCT_DB_HOST=host.docker.internal \
  -e PRODUCT_DB_USER=ecommerce_user \
  -e PRODUCT_DB_PASSWORD=secure_password_123 \
  product-service
```

## Database Schema

### Products Table

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PRIMARY KEY | Auto-incrementing ID |
| name | VARCHAR(255) | Product name |
| description | TEXT | Product description |
| price | DECIMAL(10,2) | Product price |
| stock | INTEGER | Available quantity |
| category | VARCHAR(100) | Product category |
| image_url | VARCHAR(500) | Main product image |
| images | TEXT[] | Array of image URLs |
| sku | VARCHAR(100) UNIQUE | Stock keeping unit |
| is_active | BOOLEAN | Active status |
| created_at | TIMESTAMP | Creation timestamp |
| updated_at | TIMESTAMP | Last update timestamp |
| deleted_at | TIMESTAMP | Soft delete timestamp |

### Indexes
- `idx_products_category` on `category`
- `idx_products_price` on `price`
- `idx_products_name` on `name`
- `idx_products_is_active` on `is_active`
- `idx_products_sku` on `sku` (unique)

## Sample Data

Run the seed script to populate the database with sample products:

```bash
go run cmd/seed/main.go
```

This will create:
- 20+ sample products across different categories
- Various price ranges
- Different stock levels

## Testing

### Manual Testing with cURL

**Create a product:**
```bash
curl -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Wireless Mouse",
    "description": "Ergonomic wireless mouse with 2.4GHz connectivity",
    "price": 29.99,
    "stock": 50,
    "category": "Electronics",
    "sku": "MOUSE-001"
  }'
```

**Get all products:**
```bash
curl http://localhost:8001/api/v1/products
```

**Search products:**
```bash
curl http://localhost:8001/api/v1/products/search?q=mouse
```

**Update stock:**
```bash
curl -X PUT http://localhost:8001/api/v1/products/1/stock \
  -H "Content-Type: application/json" \
  -d '{
    "quantity": 10,
    "action": "subtract"
  }'
```

## Error Handling

The service returns appropriate HTTP status codes:

- `200 OK` - Successful GET, PUT requests
- `201 Created` - Successful POST requests
- `400 Bad Request` - Invalid request data
- `404 Not Found` - Resource not found
- `409 Conflict` - Duplicate SKU
- `500 Internal Server Error` - Server errors

Error responses follow this format:
```json
{
  "error": "Error message here"
}
```

## Logging

The service uses structured JSON logging with the following fields:
- `level`: Log level (info, warn, error)
- `msg`: Log message
- `time`: Timestamp
- Additional contextual fields

Example log entry:
```json
{
  "level": "info",
  "msg": "Product created successfully",
  "product_id": 1,
  "time": "2024-01-15T10:30:00Z"
}
```

## Production Considerations

1. **Database Connection Pooling**: Configured with max 100 connections
2. **Retry Logic**: Database connection retries up to 5 times
3. **Soft Deletes**: Products are soft-deleted, not permanently removed
4. **Indexes**: Optimized queries with appropriate indexes
5. **Health Checks**: Docker health check configured
6. **Logging**: JSON structured logs for easy parsing
7. **Validation**: Input validation on all endpoints
8. **CORS**: Configurable CORS settings

## Future Enhancements

- [ ] Full-text search with PostgreSQL
- [ ] Product reviews and ratings
- [ ] Image upload functionality
- [ ] Product variants (size, color)
- [ ] Bulk import/export
- [ ] Advanced filtering with multiple criteria
- [ ] Caching layer with Redis
- [ ] GraphQL API
- [ ] Unit and integration tests
- [ ] API rate limiting
- [ ] Product recommendations

## Troubleshooting

### Database Connection Issues

If you see database connection errors:
1. Verify PostgreSQL is running
2. Check database credentials in `.env`
3. Ensure database exists
4. Check network connectivity

### Port Already in Use

If port 8001 is already in use:
```bash
# Change PORT in .env file
PORT=8002
```

## License

MIT

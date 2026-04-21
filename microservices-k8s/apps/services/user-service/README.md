# User Service

A RESTful API service for user registration, authentication, and profile management built with Node.js and Express.

## Features

- User registration with email validation
- Secure password hashing with bcrypt
- JWT-based authentication
- User login and session management
- User profile management (get, update)
- Password change functionality
- Input validation and sanitization
- Structured JSON logging
- PostgreSQL database with Sequelize ORM
- Docker support

## Technology Stack

- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **ORM**: Sequelize
- **Database**: PostgreSQL 15
- **Authentication**: JWT (jsonwebtoken)
- **Password Hashing**: bcrypt
- **Validation**: express-validator
- **Logging**: Winston

## API Endpoints

### Health Check
- `GET /health` - Service health check

### Authentication

#### Register User
```
POST /api/v1/users/register
Body:
{
  "email": "user@example.com",
  "password": "Password123!",
  "firstName": "John",
  "lastName": "Doe",
  "phone": "+1-555-0101"
}

Response:
{
  "message": "User registered successfully",
  "user": { ... },
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

#### Login
```
POST /api/v1/users/login
Body:
{
  "email": "user@example.com",
  "password": "Password123!"
}

Response:
{
  "message": "Login successful",
  "user": { ... },
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

### Profile Management (Requires Authentication)

#### Get Profile
```
GET /api/v1/users/profile
Headers:
  Authorization: Bearer {token}

Response:
{
  "id": "uuid",
  "email": "user@example.com",
  "firstName": "John",
  "lastName": "Doe",
  ...
}
```

#### Update Profile
```
PUT /api/v1/users/profile
Headers:
  Authorization: Bearer {token}
Body: (all fields optional)
{
  "firstName": "John",
  "lastName": "Doe",
  "phone": "+1-555-0101",
  "address": "123 Main St",
  "city": "New York",
  "state": "NY",
  "country": "USA",
  "zipCode": "10001"
}

Response:
{
  "message": "Profile updated successfully",
  "user": { ... }
}
```

#### Change Password
```
PUT /api/v1/users/change-password
Headers:
  Authorization: Bearer {token}
Body:
{
  "currentPassword": "OldPassword123!",
  "newPassword": "NewPassword123!"
}

Response:
{
  "message": "Password changed successfully"
}
```

## Environment Variables

Create a `.env` file in the service root:

```env
# Server
PORT=8002
NODE_ENV=development

# Database
USER_DB_HOST=localhost
USER_DB_PORT=5432
USER_DB_USER=ecommerce_user
USER_DB_PASSWORD=secure_password_123
USER_DB_NAME=users

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production-min-32-chars
JWT_EXPIRY=24h

# Logging
LOG_LEVEL=info
```

## Local Development Setup

### Prerequisites
- Node.js 18 or higher
- PostgreSQL 15 or higher
- npm or yarn

### Installation

1. **Navigate to the service directory**
```bash
cd services/user-service
```

2. **Install dependencies**
```bash
npm install
```

3. **Setup PostgreSQL database**
```bash
createdb users
```

4. **Configure environment variables**
```bash
cp .env.example .env
# Edit .env with your database credentials
```

5. **Run the service**
```bash
# Development mode with auto-reload
npm run dev

# Production mode
npm start
```

The service will start on `http://localhost:8002`

### Seed Database

```bash
npm run seed
```

This will create 5 sample users. You can login with:
- Email: `john.doe@example.com`
- Password: `Password123!`

### Running with Docker

```bash
# Build image
docker build -t user-service .

# Run container
docker run -p 8002:8002 \
  -e USER_DB_HOST=host.docker.internal \
  -e USER_DB_USER=ecommerce_user \
  -e USER_DB_PASSWORD=secure_password_123 \
  -e JWT_SECRET=your-jwt-secret \
  user-service
```

## Database Schema

### Users Table

| Column | Type | Description |
|--------|------|-------------|
| id | UUID PRIMARY KEY | User unique identifier |
| email | VARCHAR(255) UNIQUE | User email address |
| password | VARCHAR(255) | Hashed password |
| first_name | VARCHAR(100) | User first name |
| last_name | VARCHAR(100) | User last name |
| phone | VARCHAR(20) | Phone number |
| address | TEXT | Street address |
| city | VARCHAR(100) | City |
| state | VARCHAR(100) | State/Province |
| country | VARCHAR(100) | Country |
| zip_code | VARCHAR(20) | Postal code |
| is_active | BOOLEAN | Account active status |
| is_email_verified | BOOLEAN | Email verification status |
| last_login | TIMESTAMP | Last login timestamp |
| created_at | TIMESTAMP | Creation timestamp |
| updated_at | TIMESTAMP | Last update timestamp |

### Indexes
- Unique index on `email`
- Index on `is_active`

## Password Requirements

Passwords must meet the following criteria:
- Minimum 8 characters long
- At least one uppercase letter
- At least one lowercase letter
- At least one number

## Authentication

### JWT Token

After successful login or registration, the API returns a JWT token. This token must be included in the `Authorization` header for protected routes:

```
Authorization: Bearer {your-token-here}
```

### Token Expiry

Tokens expire after 24 hours by default. The expiry time can be configured using the `JWT_EXPIRY` environment variable.

## Validation

All inputs are validated using express-validator:

- **Email**: Must be a valid email format
- **Password**: Must meet password requirements
- **Names**: 2-100 characters
- **Phone**: Valid phone number format
- **Zip Code**: 5-10 digits

Validation errors return a 400 status with details:

```json
{
  "error": "Validation failed",
  "details": [
    {
      "msg": "Password must be at least 8 characters long",
      "param": "password",
      "location": "body"
    }
  ]
}
```

## Error Handling

The service returns appropriate HTTP status codes:

- `200 OK` - Successful requests
- `201 Created` - User registration successful
- `400 Bad Request` - Validation errors
- `401 Unauthorized` - Authentication required or failed
- `403 Forbidden` - Account inactive
- `404 Not Found` - User not found
- `409 Conflict` - Email already exists
- `500 Internal Server Error` - Server errors

Error responses follow this format:
```json
{
  "error": "Error message here"
}
```

## Security Features

1. **Password Hashing**: Passwords hashed with bcrypt (10 rounds)
2. **JWT Authentication**: Secure token-based authentication
3. **Password Validation**: Strong password requirements
4. **Input Sanitization**: All inputs sanitized to prevent injection attacks
5. **Email Normalization**: Emails normalized to lowercase
6. **Password Exclusion**: Passwords never returned in API responses

## Logging

The service uses Winston for structured JSON logging:

```json
{
  "level": "info",
  "message": "User registered successfully",
  "timestamp": "2024-01-15 10:30:00",
  "userId": "uuid",
  "email": "user@example.com",
  "service": "user-service"
}
```

## Testing

### Manual Testing with cURL

**Register a user:**
```bash
curl -X POST http://localhost:8002/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "Password123!",
    "firstName": "Test",
    "lastName": "User",
    "phone": "+1-555-0100"
  }'
```

**Login:**
```bash
curl -X POST http://localhost:8002/api/v1/users/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "Password123!"
  }'
```

**Get profile (replace {TOKEN} with actual token):**
```bash
curl http://localhost:8002/api/v1/users/profile \
  -H "Authorization: Bearer {TOKEN}"
```

**Update profile:**
```bash
curl -X PUT http://localhost:8002/api/v1/users/profile \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "phone": "+1-555-9999",
    "city": "San Francisco"
  }'
```

## Production Considerations

1. **JWT Secret**: Use a strong, random JWT secret (min 32 characters)
2. **Database Connection Pool**: Configured with max 20 connections in production
3. **HTTPS**: Always use HTTPS in production
4. **Rate Limiting**: Implement rate limiting to prevent brute force attacks
5. **Email Verification**: Implement email verification for new users
6. **Password Reset**: Add password reset functionality
7. **Logging**: Configure log aggregation for production
8. **Environment Variables**: Use secrets management service

## Future Enhancements

- [ ] Email verification flow
- [ ] Password reset functionality
- [ ] OAuth integration (Google, Facebook)
- [ ] Two-factor authentication (2FA)
- [ ] Account lockout after failed login attempts
- [ ] User roles and permissions
- [ ] Profile picture upload
- [ ] Activity log
- [ ] Unit and integration tests
- [ ] API rate limiting
- [ ] Refresh tokens

## Troubleshooting

### Database Connection Issues

If you see database connection errors:
1. Verify PostgreSQL is running
2. Check database credentials in `.env`
3. Ensure database exists: `createdb users`
4. Check network connectivity

### JWT Errors

If you get JWT errors:
1. Ensure JWT_SECRET is set in `.env`
2. Check token hasn't expired
3. Verify token format: `Bearer {token}`

### Validation Errors

If registration fails with validation errors:
1. Ensure password meets requirements
2. Check email format is valid
3. Verify all required fields are provided

## License

MIT

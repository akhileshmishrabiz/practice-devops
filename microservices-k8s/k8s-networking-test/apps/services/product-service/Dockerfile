# Multi-stage build for optimized image size

# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Ensure go.sum is up to date
RUN go mod tidy

# Build the application with optimizations
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s" -o main .

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS and wget for health checks (if needed locally)
RUN apk --no-cache add ca-certificates wget

# Create non-root user for security
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/main .

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

USER appuser

# Expose port (configurable via PORT env var in app)
EXPOSE 8001

# Note: HEALTHCHECK removed - Use Kubernetes liveness/readiness probes
# Kubernetes probe example: httpGet on /health endpoint

# Run the application
CMD ["./main"]

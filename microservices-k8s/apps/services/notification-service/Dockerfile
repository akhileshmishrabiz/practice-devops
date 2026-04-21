FROM python:3.11-slim

WORKDIR /app

# Install curl for health checks (if needed locally)
RUN apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port (configurable via PORT env var in app)
EXPOSE 8006

# Note: HEALTHCHECK removed - Use Kubernetes liveness/readiness probes
# Kubernetes probe example: httpGet on /health endpoint
# For local testing, use: curl http://localhost:8006/health

CMD ["python", "app.py"]

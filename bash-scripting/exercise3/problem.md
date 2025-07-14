# Container Monitor Exercise

## Problem Statement

Your Docker containers are experiencing performance issues and occasional crashes, but you only discover problems after users complain. You need proactive monitoring that tracks CPU usage, memory consumption, health status, and response times in real-time. Manual container checking with `docker stats` is time-consuming and doesn't provide alerts when thresholds are exceeded.

## What This Script Does

- Monitors Docker container performance metrics (CPU, memory, health)
- Tests HTTP endpoint latency and availability
- Sends alerts when configurable thresholds are exceeded
- Provides quick access to container logs and restart functionality
- Offers both one-time checks and continuous monitoring modes

## Testing Instructions

### 1. Setup
```bash
# Start a test container (nginx example)
docker run -d --name test-app -p 8080:80 nginx

# Make the script executable
chmod +x container_monitor.sh
```

### 2. Basic Testing
```bash
# Test without arguments (should show usage)
./container_monitor.sh

# Test with non-existent container
./container_monitor.sh fake-container

# Test with valid container
./container_monitor.sh test-app
```

### 3. Interactive Testing
```bash
# Run interactive menu
./container_monitor.sh test-app

# Try each menu option:
# 1 - Check current metrics
# 2 - View recent logs
# 3 - Restart container
# 4 - Start continuous monitoring
```

### 4. Command Line Usage
```bash
# Quick health check
./container_monitor.sh test-app check

# View logs
./container_monitor.sh test-app logs

# Restart container
./container_monitor.sh test-app restart

# Start continuous monitoring
./container_monitor.sh test-app monitor
```

### 5. Stress Testing
```bash
# Create high CPU load to trigger alerts
docker exec test-app sh -c "yes > /dev/null &"

# Monitor and watch for CPU alerts
./container_monitor.sh test-app check
```

### 6. Expected Output

**Normal operation:**
```
🔍 Monitoring container: test-app
📊 CPU: 2.45% | MEM: 1.23% (12.3MiB / 1GiB) | Health: ✅ Healthy | Latency: 45ms
```

**Alert triggered:**
```
🚨 ALERT: High CPU usage: 85.67% - Mon Jul 14 10:30:45 UTC 2025
```

### 7. Troubleshooting

If health checks fail, ensure your container has a health endpoint:
```bash
# Add health check to your Dockerfile
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost/ || exit 1
```

If latency testing fails, verify the port and endpoint:
```bash
# Test manually
curl -w "%{time_total}" http://localhost:8080/
```

# Log Monitor Exercise

## Problem Statement

Your web application is experiencing intermittent server errors, and you need to be notified immediately when HTTP 500 errors occur. Manual log checking is inefficient and delays response time. You need an automated solution that monitors server logs in real-time and sends email alerts whenever a 500 error is detected, helping you respond quickly to critical issues.

## Sample Log File

Create a file named `server.log` with the following content:

```
192.168.1.100 - - [08/Jul/2025:10:15:23 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "Mozilla/5.0"
192.168.1.101 - - [08/Jul/2025:10:15:45 +0000] "POST /api/login HTTP/1.1" 200 567 "-" "Mozilla/5.0"
192.168.1.102 - - [08/Jul/2025:10:16:12 +0000] "GET /api/products HTTP/1.1" 500 0 "-" "Mozilla/5.0"
192.168.1.103 - - [08/Jul/2025:10:16:34 +0000] "GET /dashboard HTTP/1.1" 200 2345 "-" "Mozilla/5.0"
192.168.1.104 - - [08/Jul/2025:10:17:01 +0000] "POST /api/orders HTTP/1.1" 500 0 "-" "Mozilla/5.0"
192.168.1.105 - - [08/Jul/2025:10:17:23 +0000] "GET /api/stats HTTP/1.1" 200 891 "-" "Mozilla/5.0"
192.168.1.106 - - [08/Jul/2025:10:17:45 +0000] "DELETE /api/users/123 HTTP/1.1" 500 0 "-" "Mozilla/5.0"
192.168.1.107 - - [08/Jul/2025:10:18:12 +0000] "GET /health HTTP/1.1" 200 156 "-" "Mozilla/5.0"
```

## Testing Instructions

### 1. Setup
```bash
# Create the log file
cat > server.log << 'EOF'
192.168.1.100 - - [08/Jul/2025:10:15:23 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "Mozilla/5.0"
192.168.1.101 - - [08/Jul/2025:10:15:45 +0000] "POST /api/login HTTP/1.1" 200 567 "-" "Mozilla/5.0"
192.168.1.102 - - [08/Jul/2025:10:16:12 +0000] "GET /api/products HTTP/1.1" 500 0 "-" "Mozilla/5.0"
192.168.1.103 - - [08/Jul/2025:10:16:34 +0000] "GET /dashboard HTTP/1.1" 200 2345 "-" "Mozilla/5.0"
192.168.1.104 - - [08/Jul/2025:10:17:01 +0000] "POST /api/orders HTTP/1.1" 500 0 "-" "Mozilla/5.0"
192.168.1.105 - - [08/Jul/2025:10:17:23 +0000] "GET /api/stats HTTP/1.1" 200 891 "-" "Mozilla/5.0"
EOF

# Make the script executable
chmod +x log_monitor.sh
```

### 2. Basic Testing
```bash
# Test without arguments (should show usage)
./log_monitor.sh

# Test with non-existent file (should show error)
./log_monitor.sh nonexistent.log

# Test with valid file
./log_monitor.sh server.log
```

### 3. Real-time Testing
```bash
# In Terminal 1: Start the monitor
./log_monitor.sh server.log

# In Terminal 2: Add new log entries to trigger alerts
echo '192.168.1.108 - - [08/Jul/2025:10:18:45 +0000] "GET /api/broken HTTP/1.1" 500 0 "-" "Mozilla/5.0"' >> server.log

echo '192.168.1.109 - - [08/Jul/2025:10:19:12 +0000] "POST /api/crash HTTP/1.1" 500 0 "-" "Mozilla/5.0"' >> server.log

# Add a normal request (should not trigger alert)
echo '192.168.1.110 - - [08/Jul/2025:10:19:34 +0000] "GET /api/success HTTP/1.1" 200 1123 "-" "Mozilla/5.0"' >> server.log
```

### 4. Expected Output
When you run the script, you should see:
- Initial startup message
- Detection messages for existing 500 errors in the log
- Real-time alerts as new 500 errors are appended
- No alerts for 200 status codes

### 5. Troubleshooting
If the `mail` command isn't available, you can modify the script to use `echo` instead for testing:
```bash
# Replace the mail line in send_alert function with:
echo "EMAIL TO: $RECIPIENT_EMAIL - $message"
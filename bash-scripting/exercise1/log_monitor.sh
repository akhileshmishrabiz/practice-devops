#!/bin/bash

# Log Monitor Script with Email Alerts
# This script monitors web server logs in real-time and sends email alerts for HTTP 500 errors

# Check if user provided a log file path as argument
# $# = number of arguments passed to script
if [ $# -eq 0 ]; then
    # $0 = script name, display usage message
    echo "Usage: $0 <log_file_path>"
    exit 1  # Exit with error code 1
fi

# Store the first argument (log file path) in a variable
LOG_FILE="$1"
# Set the email address for alerts
RECIPIENT_EMAIL="alert@project.com"

# Check if the log file actually exists
# -f flag tests if file exists and is a regular file
if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file '$LOG_FILE' does not exist."
    exit 1
fi

# Verify that the 'mail' command is available on the system
# command -v checks if a command exists in PATH
# &> /dev/null redirects both stdout and stderr to null (silences output)
# if ! command -v mail &> /dev/null; then
#     echo "Error: 'mail' command not found."
#     exit 1
# fi

echo "Starting log monitor for: $LOG_FILE"

# Define a function to send email alerts
send_alert() {
    # local makes variables only accessible within this function
    local http_status_code="$1"  # First function argument
    local http_path="$2"         # Second function argument
    
    # Format the alert message
    local message="HTTP [$http_status_code] on [$http_path]"
    
    # Send email using mail command
    echo "$RECIPIENT_EMAIL" "$message"
    
    # Log the alert action locally
    echo "Alert sent: $message"
}

# Get the current size of the log file in bytes
# stat -c%s gets file size, 2>/dev/null suppresses errors
# || echo 0 provides fallback value if stat fails
initial_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

# Monitor the log file in real-time
# tail -F follows file even if it's rotated/recreated
# -c +N starts from byte position N
# $((arithmetic)) performs arithmetic expansion
tail -F -c +$((initial_size + 1)) "$LOG_FILE" | while read -r line; do
    
    # Check if the current line contains " 500 " (HTTP 500 error)
    # grep -q runs quietly (no output), just returns exit code
    if echo "$line" | grep -q " 500 "; then
        
        # Extract the HTTP status code from the log line
        # grep -oE shows only the matching part with extended regex
        # ' [0-9]{3} ' matches space + 3 digits + space
        # tr -d ' ' removes spaces
        http_status_code=$(echo "$line" | grep -oE ' [0-9]{3} ' | tr -d ' ')
        
        # Extract the HTTP path from the log line
        # '"[A-Z]+ [^ ]+ HTTP/[0-9.]+' matches request line like "GET /path HTTP/1.1"
        # cut -d' ' -f2 splits on space and takes 2nd field (the path)
        http_path=$(echo "$line" | grep -oE '"[A-Z]+ [^ ]+ HTTP/[0-9.]+' | cut -d' ' -f2)
        
        # Handle case where path extraction failed
        # -z tests if variable is empty
        if [ -z "$http_path" ]; then
            http_path="unknown"
        fi 
        
        # Log the detected error
        echo "HTTP 500 error detected: $http_path"
        
        # Call our alert function with the extracted data
        send_alert "$http_status_code" "$http_path"
    fi
done

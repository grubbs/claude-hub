#!/bin/bash
# Health monitoring script for Claude webhook
# Add to crontab: */5 * * * * /home/daniel/claude-hub/scripts/health-monitor.sh

# Change to the project directory
cd /home/daniel/claude-hub

WEBHOOK_URL="http://localhost:3002/health"
LOG_FILE="/home/daniel/claude-hub/logs/health-monitor.log"
SLACK_WEBHOOK="" # Add your Slack webhook URL for notifications

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to send notification (customize as needed)
send_notification() {
    local message="$1"
    log_message "ALERT: $message"
    
    # Send to Slack if webhook is configured
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"Claude Webhook Alert: $message\"}" 2>/dev/null
    fi
    
    # Send email (if mail is configured)
    # echo "$message" | mail -s "Claude Webhook Alert" admin@example.com
}

# Check if container is running (look for "Up" in status)
if ! docker compose ps webhook | grep -E "Up[[:space:]]" > /dev/null 2>&1; then
    log_message "Container not running, attempting restart..."
    
    docker compose down
    docker compose up -d
    
    sleep 10
    
    if docker compose ps webhook | grep -E "Up[[:space:]]" > /dev/null 2>&1; then
        send_notification "Webhook container was down but successfully restarted"
    else
        send_notification "CRITICAL: Failed to restart webhook container"
        exit 1
    fi
fi

# Check health endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL" 2>/dev/null)

if [ "$HTTP_STATUS" != "200" ]; then
    log_message "Health check failed with status $HTTP_STATUS, attempting restart..."
    
    docker compose restart webhook
    
    sleep 10
    
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL" 2>/dev/null)
    
    if [ "$HTTP_STATUS" = "200" ]; then
        send_notification "Webhook health check failed but recovered after restart"
    else
        send_notification "CRITICAL: Webhook health check failing after restart (HTTP $HTTP_STATUS)"
        exit 1
    fi
else
    log_message "Health check passed"
fi

# Check for Docker socket permissions
if ! docker compose exec webhook sh -c "docker ps" >/dev/null 2>&1; then
    log_message "Docker socket permission issue detected, fixing..."
    docker compose exec -u root webhook sh -c "groupadd -g 121 dockerhost 2>/dev/null || true && usermod -aG dockerhost claudeuser"
    docker compose restart webhook
    send_notification "Fixed Docker socket permissions and restarted webhook"
fi

# Rotate log file if it's too large (>10MB)
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log_message "Log file rotated"
fi
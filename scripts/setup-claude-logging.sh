#!/bin/bash
# Setup Claude logging with 30-day retention

# Create log directory structure
LOG_BASE="/home/daniel/claude-hub/logs"
mkdir -p "$LOG_BASE/claude-sessions"
mkdir -p "$LOG_BASE/archived"

echo "Claude logging system setup complete!"
echo "Logs will be stored in: $LOG_BASE/claude-sessions"
echo "Logs older than 30 days will be automatically deleted"

# Create logrotate configuration for automatic deletion
sudo tee /etc/logrotate.d/claude-logs > /dev/null <<EOF
$LOG_BASE/claude-sessions/*.log {
    daily
    maxage 30
    missingok
    notifempty
    compress
    delaycompress
    create 0644 daniel daniel
}
EOF

echo "Logrotate configured for 30-day retention"
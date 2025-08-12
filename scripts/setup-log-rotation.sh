#!/bin/bash
# Setup automatic log rotation and cleanup

LOG_DIR="/home/daniel/claude-hub/logs/claude-sessions"

# Create the log directory
mkdir -p "$LOG_DIR"

# Create a cron job for daily cleanup
CRON_CMD="0 2 * * * find $LOG_DIR -name '*.log' -mtime +30 -delete"

# Add to user's crontab if not already present
(crontab -l 2>/dev/null | grep -v "$LOG_DIR.*-delete"; echo "$CRON_CMD") | crontab -

echo "Log rotation configured!"
echo "Logs in $LOG_DIR will be automatically deleted after 30 days"
echo "Cleanup runs daily at 2 AM"

# Also create a manual cleanup script
cat > /home/daniel/claude-hub/scripts/cleanup-old-logs.sh << 'EOF'
#!/bin/bash
# Manual cleanup of old Claude logs

LOG_DIR="/home/daniel/claude-hub/logs/claude-sessions"
DAYS=30

echo "Cleaning Claude logs older than $DAYS days..."
echo "Directory: $LOG_DIR"

# Show what will be deleted
echo ""
echo "Files to be deleted:"
find "$LOG_DIR" -name "*.log" -mtime +$DAYS -ls

echo ""
echo -n "Proceed with deletion? (y/n): "
read confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    find "$LOG_DIR" -name "*.log" -mtime +$DAYS -delete
    echo "Cleanup complete!"
else
    echo "Cleanup cancelled"
fi

# Show disk usage
echo ""
echo "Current disk usage:"
du -sh "$LOG_DIR"
EOF

chmod +x /home/daniel/claude-hub/scripts/cleanup-old-logs.sh
echo "Manual cleanup script created: scripts/cleanup-old-logs.sh"
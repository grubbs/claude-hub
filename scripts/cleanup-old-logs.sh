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

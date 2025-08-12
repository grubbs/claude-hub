#!/bin/bash
# Watch Claude containers in real-time

echo "Watching for Claude containers (Ctrl+C to stop)..."
echo ""

while true; do
    RUNNING=$(docker ps --format "{{.Names}}" | grep "claude-.*-rail")
    
    if [ ! -z "$RUNNING" ]; then
        clear
        echo "=== CLAUDE IS RUNNING ==="
        echo "Time: $(date)"
        echo "Container: $RUNNING"
        echo ""
        
        # Show resource usage
        docker stats --no-stream "$RUNNING"
        echo ""
        
        # Show last 10 lines of logs
        echo "=== Latest Activity ==="
        docker logs "$RUNNING" 2>&1 | tail -10
        
        # Optional: Follow logs in real-time (uncomment if you want continuous log streaming)
        # docker logs -f "$RUNNING"
    else
        printf "\r[$(date +%H:%M:%S)] No Claude containers running... (watching)"
    fi
    
    sleep 2
done
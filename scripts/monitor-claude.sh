#!/bin/bash
# Monitor currently running Claude containers

echo "=== Claude Container Monitor ==="
echo "Time: $(date)"
echo ""

# Check for running Claude containers
CLAUDE_CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep "claude-.*-rail")

if [ -z "$CLAUDE_CONTAINERS" ]; then
    echo "No Claude containers currently running"
else
    echo "Active Claude Containers:"
    echo "$CLAUDE_CONTAINERS"
    echo ""
    
    # Show resource usage
    echo "Resource Usage:"
    docker stats --no-stream $(docker ps -q --filter "name=claude-.*-rail")
fi

echo ""
echo "=== Recent Claude Container History ==="
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep "claude-.*-rail" | head -5

echo ""
echo "=== Webhook Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep webhook
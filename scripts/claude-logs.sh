#!/bin/bash
# View logs from recent Claude containers

echo "=== Recent Claude Container Logs ==="

# Get the most recent Claude container (running or stopped)
LATEST_CONTAINER=$(docker ps -a --format "{{.Names}}" | grep "claude-.*-rail" | head -1)

if [ -z "$LATEST_CONTAINER" ]; then
    echo "No Claude containers found"
    exit 0
fi

echo "Latest container: $LATEST_CONTAINER"
echo "Status: $(docker ps -a --filter "name=$LATEST_CONTAINER" --format "{{.Status}}")"
echo ""
echo "=== Container Logs ==="
docker logs "$LATEST_CONTAINER" 2>&1 | tail -100

# To save logs permanently, uncomment:
# LOG_DIR="/home/daniel/claude-hub/logs/claude-containers"
# mkdir -p "$LOG_DIR"
# docker logs "$LATEST_CONTAINER" > "$LOG_DIR/${LATEST_CONTAINER}_$(date +%Y%m%d_%H%M%S).log" 2>&1
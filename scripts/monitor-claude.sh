#!/bin/bash
# Monitor currently running Claude containers and authentication status

# Colors for better visibility
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=== Claude Container & Auth Monitor ==="
echo "Time: $(date)"
echo ""

# Authentication Status Section
echo "=== 🔐 Authentication Status ==="
AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"
if [ -f "$AUTH_DIR/.credentials.json" ]; then
    # Get auth age
    FILE_TIMESTAMP=$(stat -c %Y "$AUTH_DIR/.credentials.json" 2>/dev/null || echo "0")
    if [ "$FILE_TIMESTAMP" != "0" ]; then
        CURRENT_TIME=$(date +%s)
        AUTH_AGE=$((CURRENT_TIME - FILE_TIMESTAMP))
        AUTH_AGE_HOURS=$((AUTH_AGE / 3600))
        AUTH_AGE_DAYS=$((AUTH_AGE / 86400))
        
        if [ $AUTH_AGE_DAYS -eq 0 ]; then
            echo -e "${GREEN}✅ Auth Age: ${AUTH_AGE_HOURS} hours${NC}"
        elif [ $AUTH_AGE_DAYS -lt 7 ]; then
            HOURS_REMAINDER=$((AUTH_AGE_HOURS % 24))
            echo -e "${GREEN}✅ Auth Age: ${AUTH_AGE_DAYS} days, ${HOURS_REMAINDER} hours${NC}"
        elif [ $AUTH_AGE_DAYS -lt 14 ]; then
            echo -e "${YELLOW}⚠️  Auth Age: ${AUTH_AGE_DAYS} days (getting old)${NC}"
        else
            echo -e "${RED}❌ Auth Age: ${AUTH_AGE_DAYS} days (needs refresh)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Cannot determine auth age${NC}"
    fi
    
    # Check last keep-alive
    if [ -f "/home/daniel/claude-hub/logs/keep-alive-cron.log" ]; then
        LAST_KEEPALIVE=$(tail -1 /home/daniel/claude-hub/logs/keep-alive-cron.log 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
        if [ -n "$LAST_KEEPALIVE" ]; then
            echo "Last keep-alive: $LAST_KEEPALIVE"
        fi
    fi
else
    echo -e "${RED}❌ No authentication found${NC}"
fi

echo ""
echo "=== 🤖 Active Claude Containers ==="
# Check for ALL running Claude containers (not just -rail)
CLAUDE_CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep "claude-" | grep -v "webhook")

if [ -z "$CLAUDE_CONTAINERS" ]; then
    echo "No Claude containers currently running"
else
    echo "$CLAUDE_CONTAINERS"
    echo ""
    
    # Show resource usage for all Claude containers
    echo "Resource Usage:"
    CLAUDE_IDS=$(docker ps -q --filter "name=claude-" | grep -v webhook)
    if [ -n "$CLAUDE_IDS" ]; then
        docker stats --no-stream $CLAUDE_IDS 2>/dev/null || echo "Unable to get stats"
    fi
fi

echo ""
echo "=== 📜 Recent Claude Container History ==="
# Show ALL recent Claude containers (not just -rail)
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep "claude-" | grep -v "webhook" | head -10

echo ""
echo "=== 🌐 Webhook Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep webhook

# Show webhook health
echo ""
HEALTH=$(curl -s http://localhost:3002/health 2>/dev/null | grep -o '"status":"ok"' || echo "")
if [ -n "$HEALTH" ]; then
    echo -e "${GREEN}✅ Webhook Health: OK${NC}"
else
    echo -e "${RED}❌ Webhook Health: Not responding${NC}"
fi
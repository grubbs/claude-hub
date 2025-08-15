#!/bin/bash
# Compact real-time monitor optimized for tmux pane
# Designed to fit in a narrow pane alongside ngrok and main terminal

# Colors
R='\033[0;31m'  # Red
G='\033[0;32m'  # Green
Y='\033[1;33m'  # Yellow
B='\033[0;34m'  # Blue
C='\033[0;36m'  # Cyan
W='\033[1;37m'  # White
N='\033[0m'      # No Color

# Terminal escape codes
CLEAR_SCREEN='\033[2J'  # Clear screen
HOME='\033[H'           # Move cursor to home
HIDE_CURSOR='\033[?25l' # Hide cursor
SHOW_CURSOR='\033[?25h' # Show cursor

# Config
REFRESH=1

# Check if we need sudo for docker
DOCKER_SUDO=""
if ! docker ps >/dev/null 2>&1; then
    if sudo docker ps >/dev/null 2>&1; then
        DOCKER_SUDO="sudo "
        echo "Docker requires sudo privileges - using sudo for docker commands"
        sleep 2
    else
        echo "Error: Docker is not accessible. Please check Docker installation and permissions."
        exit 1
    fi
fi

# Helper function to run docker commands
docker_cmd() {
    ${DOCKER_SUDO}docker "$@"
}

# Helper function to run docker compose commands  
docker_compose_cmd() {
    ${DOCKER_SUDO}docker compose "$@"
}

# Cleanup on exit
trap 'echo -e "${SHOW_CURSOR}\n${Y}Monitor stopped${N}"; exit 0' INT TERM

# Initialize terminal
echo -ne "${HIDE_CURSOR}"

# Main loop
while true; do
    # Clear screen and move cursor to home (no blink)
    echo -ne "${CLEAR_SCREEN}${HOME}"
    
    # Header - combined on one line
    echo -e "${W}═══ CLAUDE MONITOR ═══${N} $(date '+%H:%M:%S')"
    
    # Authentication Status (compact)
    echo -e "${W}AUTH:${N}"
    AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"
    if [ -f "$AUTH_DIR/.credentials.json" ]; then
        FILE_TIMESTAMP=$(stat -c %Y "$AUTH_DIR/.credentials.json" 2>/dev/null || echo "0")
        if [ "$FILE_TIMESTAMP" != "0" ]; then
            CURRENT_TIME=$(date +%s)
            AUTH_AGE=$((CURRENT_TIME - FILE_TIMESTAMP))
            AUTH_AGE_HOURS=$((AUTH_AGE / 3600))
            AUTH_AGE_DAYS=$((AUTH_AGE / 86400))
            
            if [ $AUTH_AGE_DAYS -eq 0 ]; then
                echo -e " ${G}● ${AUTH_AGE_HOURS}h old${N}"
            elif [ $AUTH_AGE_DAYS -lt 7 ]; then
                echo -e " ${G}● ${AUTH_AGE_DAYS}d old${N}"
            elif [ $AUTH_AGE_DAYS -lt 14 ]; then
                echo -e " ${Y}● ${AUTH_AGE_DAYS}d (aging)${N}"
            else
                echo -e " ${R}● ${AUTH_AGE_DAYS}d (expired!)${N}"
            fi
        fi
    else
        echo -e " ${R}● No auth${N}"
    fi
    
    # Show last keep-alive run
    KEEPALIVE_LOG="/home/daniel/claude-hub/logs/claude-keep-alive.log"
    if [ -f "$KEEPALIVE_LOG" ]; then
        # Get last timestamp from log
        LAST_RUN=$(tail -1 "$KEEPALIVE_LOG" 2>/dev/null | grep -oE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' | tr -d '[]' | head -1)
        if [ -n "$LAST_RUN" ]; then
            # Convert to epoch
            LAST_EPOCH=$(date -d "$LAST_RUN" +%s 2>/dev/null || echo "0")
            if [ "$LAST_EPOCH" != "0" ]; then
                CURRENT_TIME=$(date +%s)
                TIME_DIFF=$((CURRENT_TIME - LAST_EPOCH))
                if [ $TIME_DIFF -lt 3600 ]; then
                    MINS=$((TIME_DIFF / 60))
                    echo -e " ${C}↻${N} ${MINS}m ago"
                elif [ $TIME_DIFF -lt 86400 ]; then
                    HOURS=$((TIME_DIFF / 3600))
                    echo -e " ${C}↻${N} ${HOURS}h ago"
                else
                    echo -e " ${Y}↻${N} >24h ago"
                fi
            fi
        fi
    fi
    
    # Webhook Status
    echo -e "${W}WEBHOOK:${N}"
    # More robust webhook detection - check multiple ways
    webhook_status=$(docker_compose_cmd ps 2>&1 | grep "webhook" | grep -v "WARN" | grep -v "level=" || echo "")
    if [ -z "$webhook_status" ]; then
        # Fallback to docker ps
        webhook_status=$(docker_cmd ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep "webhook" || echo "")
    fi
    if echo "$webhook_status" | grep -qE "(Up |healthy)"; then
        uptime=$(echo "$webhook_status" | grep -oE "Up [^(]+" | sed 's/Up //')
        echo -e " ${G}● UP${N} $uptime"
        
        # Health check
        health=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3002/health" 2>/dev/null)
        if [ "$health" = "200" ]; then
            echo -e " ${G}● Health OK${N}"
        else
            echo -e " ${R}● Health: $health${N}"
        fi
    else
        echo -e " ${R}● DOWN${N}"
    fi
    echo ""
    
    # Claude Status
    echo -e "${W}CLAUDE:${N}"
    # Show ALL Claude containers, not just -rail
    claude_containers=$(docker_cmd ps --format "{{.Names}}" 2>/dev/null | grep "^claude-" | grep -v "webhook" 2>/dev/null || true)
    if [ -n "$claude_containers" ]; then
        claude_count=$(echo "$claude_containers" | wc -l)
    else
        claude_count=0
    fi
    if [ "$claude_count" -gt 0 ]; then
        echo -e " ${C}● $claude_count RUNNING${N}"
        
        # Show container names (abbreviated)
        echo "$claude_containers" | while read container; do
            [ -z "$container" ] && continue
            # Extract repo and issue number (works for both rail and hub)
            if echo "$container" | grep -q "rail"; then
                repo="rail"
                issue=$(echo $container | grep -oE "rail-[0-9]+" | cut -d'-' -f2)
            elif echo "$container" | grep -q "hub"; then
                repo="hub"
                issue=$(echo $container | grep -oE "hub-[0-9]+" | cut -d'-' -f2)
            else
                # Generic format: claude-<hash>
                repo="claude"
                issue=""
            fi
            
            # Get basic stats
            stats=$(docker_cmd stats --no-stream "$container" 2>/dev/null | tail -1)
            if [ ! -z "$stats" ]; then
                cpu=$(echo "$stats" | awk '{print $3}')
                mem=$(echo "$stats" | awk '{print $7}')
                if [ -n "$issue" ]; then
                    echo -e " ${C}→${N} $repo #$issue"
                else
                    echo -e " ${C}→${N} $container"
                fi
                echo "   CPU:$cpu MEM:$mem"
            fi
        done
    else
        echo -e " ${W}● Idle${N}"
    fi
    echo ""
    
    # Recent Activity (last 3 events)
    echo -e "${W}RECENT:${N}"
    docker_compose_cmd logs webhook --tail 50 2>/dev/null | \
        grep -E "(issue_comment|Processing.*mention|Claude Code completed)" | \
        tail -3 | \
        while IFS= read -r line; do
            if echo "$line" | grep -q "issue_comment"; then
                time=$(echo "$line" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1)
                echo -e " ${Y}►${N} Comment [$time]"
            elif echo "$line" | grep -q "Processing.*mention"; then
                echo -e " ${B}►${N} Processing..."
            elif echo "$line" | grep -q "completed"; then
                echo -e " ${G}►${N} Completed"
            fi
        done
    
    # Show if no recent activity
    recent_logs=$(docker_compose_cmd logs webhook --tail 50 2>/dev/null || true)
    if [ -z "$recent_logs" ] || ! echo "$recent_logs" | grep -q "issue_comment"; then
        echo -e " ${W}(no recent activity)${N}"
    fi
    echo ""
    
    # Live Claude output (if running)
    claude_container=$(echo "$claude_containers" | head -1)
    if [ ! -z "$claude_container" ]; then
        echo -e "${W}LIVE OUTPUT:${N}"
        docker_cmd logs --tail 5 "$claude_container" 2>&1 | \
            cut -c1-40 | \
            sed 's/^/ /'
        echo ""
    fi
    
    # Session logs count
    LOG_DIR="/home/daniel/claude-hub/logs/claude-sessions"
    log_count=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    if [ "$log_count" -gt 0 ]; then
        echo -e "${W}LOGS:${N} $log_count sessions"
        latest=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ ! -z "$latest" ]; then
            name=$(basename "$latest" | cut -d'_' -f1-2)
            echo " Latest: $name"
        fi
    fi
    
    # Footer - combined on one line  
    echo "───────────────────── [Refresh: ${REFRESH}s]"
    
    sleep $REFRESH
done
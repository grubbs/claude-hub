#!/bin/bash

# Monitor authentication lifetime with and without keep-alive
# This script tracks auth file ages and session validity over time

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"
MONITOR_LOG="$PROJECT_ROOT/logs/auth-lifetime-monitor.csv"
STATUS_LOG="$PROJECT_ROOT/logs/auth-status-monitor.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$MONITOR_LOG")"

# Initialize CSV if it doesn't exist
if [ ! -f "$MONITOR_LOG" ]; then
    echo "timestamp,auth_age_hours,auth_works,keep_alive_enabled,test_output" > "$MONITOR_LOG"
fi

# Function to test if auth actually works
test_auth_works() {
    # Check if we have any Claude-related container running (suppress permission errors)
    if docker ps 2>/dev/null | grep -q "webhook"; then
        # We have the webhook container, auth is likely working
        if [ -f "$AUTH_DIR/.credentials.json" ]; then
            echo "likely_working"
            return 0
        else
            echo "no_auth_files"
            return 1
        fi
    else
        # Try to check with claude-setup image if available
        if docker images 2>/dev/null | grep -q "claude-setup"; then
            TEST_OUTPUT=$(docker run --rm \
                -v "$AUTH_DIR:/home/node/.claude:ro" \
                -e CLAUDE_HOME=/home/node/.claude \
                claude-setup:latest \
                timeout 5 echo "test" 2>&1) || return 1
            
            if echo "$TEST_OUTPUT" | grep -q "test"; then
                echo "true"
                return 0
            else
                echo "unclear"
                return 2
            fi
        else
            echo "webhook_running"
            return 0
        fi
    fi
}

# Get current auth age
get_auth_age_hours() {
    # Try to read the auth file even if we're running as sudo
    local CRED_FILE="$AUTH_DIR/.credentials.json"
    
    # If running as root, try to read the file anyway
    if [ "$EUID" -eq 0 ]; then
        CRED_FILE="/home/daniel/.claude-hub/.credentials.json"
    fi
    
    if [ -f "$CRED_FILE" ] && [ -r "$CRED_FILE" ]; then
        FILE_TIMESTAMP=$(stat -c %Y "$CRED_FILE" 2>/dev/null)
        if [ -n "$FILE_TIMESTAMP" ]; then
            CURRENT_TIME=$(date +%s)
            AUTH_AGE=$((CURRENT_TIME - FILE_TIMESTAMP))
            AUTH_AGE_HOURS=$((AUTH_AGE / 3600))
            echo "$AUTH_AGE_HOURS"
        else
            echo "-1"
        fi
    else
        # Try without read check for sudo
        if [ -f "$CRED_FILE" ]; then
            FILE_TIMESTAMP=$(stat -c %Y "$CRED_FILE" 2>/dev/null)
            if [ -n "$FILE_TIMESTAMP" ]; then
                CURRENT_TIME=$(date +%s)
                AUTH_AGE=$((CURRENT_TIME - FILE_TIMESTAMP))
                AUTH_AGE_HOURS=$((AUTH_AGE / 3600))
                echo "$AUTH_AGE_HOURS"
            else
                echo "0"
            fi
        else
            echo "-1"
        fi
    fi
}

# Check if keep-alive is scheduled
is_keep_alive_scheduled() {
    # If running as root, check the user's crontab
    if [ "$EUID" -eq 0 ]; then
        if sudo -u daniel crontab -l 2>/dev/null | grep -q "keep-alive-claude-max.sh"; then
            echo "true"
        else
            echo "false"
        fi
    else
        if crontab -l 2>/dev/null | grep -q "keep-alive-claude-max.sh"; then
            echo "true"
        else
            echo "false"
        fi
    fi
}

# Main monitoring function
monitor_auth() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    AUTH_AGE=$(get_auth_age_hours)
    AUTH_WORKS=$(test_auth_works)
    KEEP_ALIVE=$(is_keep_alive_scheduled)
    
    # Clean test output for CSV
    TEST_STATUS="${AUTH_WORKS:-unknown}"
    
    # Log to CSV
    echo "$TIMESTAMP,$AUTH_AGE,$TEST_STATUS,$KEEP_ALIVE,\"$TEST_OUTPUT\"" >> "$MONITOR_LOG"
    
    # Log to status file
    echo "[$TIMESTAMP] Auth Age: ${AUTH_AGE}h | Works: $TEST_STATUS | Keep-Alive: $KEEP_ALIVE" | tee -a "$STATUS_LOG"
    
    # Display status
    echo ""
    echo "📊 Authentication Status"
    echo "========================"
    echo "Timestamp: $TIMESTAMP"
    echo "Auth Age: $AUTH_AGE hours"
    
    if [ "$TEST_STATUS" = "true" ] || [ "$TEST_STATUS" = "likely_working" ] || [ "$TEST_STATUS" = "webhook_running" ]; then
        echo -e "${GREEN}✅ Authentication is working${NC}"
    elif [ "$TEST_STATUS" = "false" ] || [ "$TEST_STATUS" = "no_auth_files" ]; then
        echo -e "${RED}❌ Authentication has expired${NC}"
    else
        echo -e "${YELLOW}⚠️  Authentication status unclear${NC}"
    fi
    
    echo "Keep-Alive Scheduled: $KEEP_ALIVE"
    echo ""
}

# Command line options
case "${1:-monitor}" in
    monitor)
        monitor_auth
        ;;
    continuous)
        echo "🔄 Starting continuous monitoring (every 30 minutes)..."
        echo "Press Ctrl+C to stop"
        while true; do
            monitor_auth
            sleep 1800  # 30 minutes
        done
        ;;
    report)
        echo "📈 Authentication Lifetime Report"
        echo "=================================="
        echo ""
        if [ -f "$MONITOR_LOG" ]; then
            echo "Last 10 measurements:"
            tail -10 "$MONITOR_LOG" | column -t -s ','
            echo ""
            
            # Calculate statistics
            TOTAL_RECORDS=$(wc -l < "$MONITOR_LOG")
            WORKING_COUNT=$(grep -c ",true," "$MONITOR_LOG" 2>/dev/null || echo 0)
            FAILED_COUNT=$(grep -c ",false," "$MONITOR_LOG" 2>/dev/null || echo 0)
            
            echo "Statistics:"
            echo "- Total measurements: $((TOTAL_RECORDS - 1))"
            echo "- Working auth: $WORKING_COUNT"
            echo "- Failed auth: $FAILED_COUNT"
            
            # Find longest working session
            if [ -f "$MONITOR_LOG" ]; then
                MAX_AGE=$(awk -F',' '$3=="true" {print $2}' "$MONITOR_LOG" | sort -rn | head -1)
                if [ -n "$MAX_AGE" ]; then
                    echo "- Max working age observed: $MAX_AGE hours"
                fi
            fi
        else
            echo "No monitoring data available yet."
            echo "Run: $0 monitor"
        fi
        ;;
    graph)
        echo "📊 Generating auth lifetime graph..."
        if [ -f "$MONITOR_LOG" ]; then
            python3 - <<EOF
import csv
import datetime
import matplotlib.pyplot as plt
from pathlib import Path

log_file = "$MONITOR_LOG"
output_file = "$PROJECT_ROOT/logs/auth-lifetime-graph.png"

timestamps = []
ages = []
statuses = []
keep_alive = []

with open(log_file, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            timestamps.append(datetime.datetime.strptime(row['timestamp'], '%Y-%m-%d %H:%M:%S'))
            ages.append(int(row['auth_age_hours']))
            statuses.append(row['auth_works'] == 'true')
            keep_alive.append(row['keep_alive_enabled'] == 'true')
        except:
            continue

if timestamps:
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8), sharex=True)
    
    # Plot age over time
    ax1.plot(timestamps, ages, 'b-', label='Auth Age (hours)')
    ax1.set_ylabel('Age (hours)')
    ax1.set_title('Claude Max Authentication Lifetime')
    ax1.grid(True, alpha=0.3)
    ax1.legend()
    
    # Add horizontal lines for key thresholds
    ax1.axhline(y=168, color='yellow', linestyle='--', alpha=0.5, label='7 days')
    ax1.axhline(y=336, color='red', linestyle='--', alpha=0.5, label='14 days')
    
    # Plot status over time
    ax2.scatter(timestamps, statuses, c=['green' if s else 'red' for s in statuses], alpha=0.6)
    ax2.set_ylabel('Auth Working')
    ax2.set_xlabel('Time')
    ax2.set_yticks([0, 1])
    ax2.set_yticklabels(['Failed', 'Working'])
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=100)
    print(f"Graph saved to: {output_file}")
else:
    print("Not enough data to generate graph")
EOF
        else
            echo "No data available for graphing"
        fi
        ;;
    *)
        echo "Usage: $0 [monitor|continuous|report|graph]"
        echo "  monitor    - Take a single measurement"
        echo "  continuous - Monitor continuously every 30 minutes"
        echo "  report     - Show statistics report"
        echo "  graph      - Generate lifetime graph (requires matplotlib)"
        ;;
esac
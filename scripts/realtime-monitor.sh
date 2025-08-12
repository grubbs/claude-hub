#!/bin/bash
# Real-time Claude webhook monitor for tmux
# Shows webhook status, Claude activity, and recent events

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
WEBHOOK_URL="http://localhost:3002/health"
LOG_DIR="/home/daniel/claude-hub/logs/claude-sessions"
HEALTH_LOG="/home/daniel/claude-hub/logs/health-monitor.log"
REFRESH_RATE=2

# Terminal setup
clear
trap 'echo -e "\n${YELLOW}Monitor stopped${NC}"; exit 0' INT TERM

# Function to get terminal width
get_term_width() {
    echo $(tput cols)
}

# Function to print a separator line
print_separator() {
    local width=$(get_term_width)
    printf '%*s\n' "$width" '' | tr ' ' '─'
}

# Function to center text
center_text() {
    local text="$1"
    local width=$(get_term_width)
    local text_length=${#text}
    local padding=$(( (width - text_length) / 2 ))
    printf "%*s%s\n" $padding "" "$text"
}

# Function to check webhook health
check_webhook_health() {
    local status=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL" 2>/dev/null)
    if [ "$status" = "200" ]; then
        echo -e "${GREEN}● HEALTHY${NC}"
    else
        echo -e "${RED}● UNHEALTHY (HTTP $status)${NC}"
    fi
}

# Function to check if webhook container is running
check_webhook_container() {
    if docker compose ps webhook 2>/dev/null | grep -q "Up "; then
        local uptime=$(docker compose ps webhook 2>/dev/null | grep webhook | awk '{for(i=5;i<=NF;i++) printf "%s ", $i}')
        echo -e "${GREEN}● RUNNING${NC} $uptime"
    else
        echo -e "${RED}● NOT RUNNING${NC}"
    fi
}

# Function to check Claude containers
check_claude_containers() {
    local claude_count=$(docker ps --format "{{.Names}}" | grep -c "claude-.*-rail" 2>/dev/null || echo 0)
    if [ "$claude_count" -gt 0 ]; then
        echo -e "${CYAN}● $claude_count ACTIVE${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep "claude-.*-rail" | head -3 | while read line; do
            echo "  └─ $line"
        done
    else
        echo -e "${WHITE}● IDLE${NC}"
    fi
}

# Function to get Claude container stats
get_claude_stats() {
    local claude_containers=$(docker ps -q --filter "name=claude-.*-rail" 2>/dev/null)
    if [ ! -z "$claude_containers" ]; then
        docker stats --no-stream $claude_containers 2>/dev/null | tail -n +2 | while read line; do
            local name=$(echo "$line" | awk '{print $2}' | cut -d'-' -f2-4)
            local cpu=$(echo "$line" | awk '{print $3}')
            local mem=$(echo "$line" | awk '{print $7}')
            echo "  $name: CPU $cpu, MEM $mem"
        done
    fi
}

# Function to show recent webhook events
show_recent_events() {
    # Get last 5 webhook events from container logs
    docker compose logs webhook --tail 100 2>/dev/null | \
        grep -E "(issue_comment|pull_request|check_suite)" | \
        tail -5 | \
        while read -r line; do
            if echo "$line" | grep -q "issue_comment"; then
                echo -e "  ${YELLOW}►${NC} Issue comment event"
            elif echo "$line" | grep -q "pull_request"; then
                echo -e "  ${BLUE}►${NC} Pull request event"
            elif echo "$line" | grep -q "check_suite"; then
                echo -e "  ${MAGENTA}►${NC} Check suite event"
            fi
        done
}

# Function to show recent Claude activity
show_claude_activity() {
    # Check for recent Claude logs
    if [ -d "$LOG_DIR" ] && [ "$(ls -A $LOG_DIR 2>/dev/null)" ]; then
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ ! -z "$latest_log" ]; then
            local log_name=$(basename "$latest_log")
            local last_line=$(tail -1 "$latest_log" 2>/dev/null | cut -c1-60)
            echo -e "  ${GREEN}Latest:${NC} $log_name"
            echo -e "  ${WHITE}Last:${NC} $last_line..."
        fi
    else
        echo -e "  ${WHITE}No session logs yet${NC}"
    fi
}

# Function to show real-time Claude output if running
show_claude_realtime() {
    local claude_container=$(docker ps --format "{{.Names}}" | grep "claude-.*-rail" | head -1)
    if [ ! -z "$claude_container" ]; then
        echo -e "${BOLD}${CYAN}┌─ LIVE OUTPUT from $claude_container ─┐${NC}"
        docker logs --tail 10 "$claude_container" 2>&1 | sed 's/^/│ /'
        echo -e "${CYAN}└────────────────────────────────────────┘${NC}"
    fi
}

# Function to show system resources
show_system_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_info=$(free -h | grep Mem)
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local disk_usage=$(df -h /home | tail -1 | awk '{print $5}')
    
    echo -e "  CPU: ${cpu_usage}% | MEM: ${mem_used}/${mem_total} | DISK: ${disk_usage}"
}

# Main monitoring loop
while true; do
    clear
    
    # Header
    echo -e "${BOLD}${WHITE}"
    center_text "╔══════════════════════════════════════════╗"
    center_text "║    CLAUDE WEBHOOK REAL-TIME MONITOR     ║"
    center_text "║         $(date '+%Y-%m-%d %H:%M:%S')          ║"
    center_text "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_separator
    
    # Webhook Status Section
    echo -e "${BOLD}${WHITE}📡 WEBHOOK STATUS${NC}"
    echo -e "  Container: $(check_webhook_container)"
    echo -e "  Health:    $(check_webhook_health)"
    echo ""
    
    # Claude Activity Section
    echo -e "${BOLD}${WHITE}🤖 CLAUDE ACTIVITY${NC}"
    echo -e "  Status: $(check_claude_containers)"
    get_claude_stats
    echo ""
    
    # Recent Events Section
    echo -e "${BOLD}${WHITE}📊 RECENT EVENTS${NC}"
    recent_events=$(show_recent_events)
    if [ -z "$recent_events" ]; then
        echo -e "  ${WHITE}No recent events${NC}"
    else
        echo "$recent_events"
    fi
    echo ""
    
    # Session Logs Section
    echo -e "${BOLD}${WHITE}📝 SESSION LOGS${NC}"
    show_claude_activity
    echo ""
    
    # System Resources
    echo -e "${BOLD}${WHITE}💻 SYSTEM RESOURCES${NC}"
    show_system_resources
    echo ""
    
    print_separator
    
    # Live Claude Output (if running)
    show_claude_realtime
    
    # Footer with controls
    print_separator
    echo -e "${WHITE}[Refresh: ${REFRESH_RATE}s] [Ctrl+C: Exit] [Monitoring: $(date '+%H:%M:%S')]${NC}"
    
    sleep $REFRESH_RATE
done
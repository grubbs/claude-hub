#!/bin/bash

# Simple experiment to test keep-alive effectiveness
# This script sets up A/B testing for the keep-alive mechanism

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPERIMENT_LOG="$PROJECT_ROOT/logs/keep-alive-experiment.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$EXPERIMENT_LOG"
}

show_menu() {
    echo ""
    echo "🧪 Claude Max Keep-Alive Experiment"
    echo "===================================="
    echo ""
    echo "Choose experiment mode:"
    echo ""
    echo "1) Quick Test (1 hour)"
    echo "   - Runs keep-alive every 10 minutes"
    echo "   - Monitors auth status"
    echo "   - Good for initial validation"
    echo ""
    echo "2) Daily Test (24 hours)"
    echo "   - Runs keep-alive every 6 hours"
    echo "   - Tracks auth persistence"
    echo "   - Realistic usage pattern"
    echo ""
    echo "3) Endurance Test (7 days)"
    echo "   - Runs keep-alive every 12 hours"
    echo "   - Tests long-term effectiveness"
    echo "   - Find maximum lifetime"
    echo ""
    echo "4) Control Test (No keep-alive)"
    echo "   - Only monitors, no keep-alive"
    echo "   - Establishes baseline decay"
    echo "   - Measure natural timeout"
    echo ""
    echo "5) View Current Status"
    echo "   - Check auth age and status"
    echo "   - See if keep-alive is scheduled"
    echo "   - Review recent logs"
    echo ""
    echo "6) Stop All Experiments"
    echo "   - Remove cron jobs"
    echo "   - Stop monitoring"
    echo "   - Clean up"
    echo ""
    read -p "Select option (1-6): " choice
    echo ""
}

quick_test() {
    log_message "Starting Quick Test (1 hour, 10-minute intervals)"
    
    # Remove existing cron jobs
    crontab -l 2>/dev/null | grep -v keep-alive-claude-max | crontab - 2>/dev/null
    crontab -l 2>/dev/null | grep -v monitor-auth-lifetime | crontab - 2>/dev/null
    
    # Add aggressive keep-alive
    (crontab -l 2>/dev/null; echo "*/10 * * * * $SCRIPT_DIR/keep-alive-claude-max.sh >> $PROJECT_ROOT/logs/keep-alive-test.log 2>&1") | crontab -
    (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/monitor-auth-lifetime.sh monitor") | crontab -
    
    echo -e "${GREEN}✅ Quick test started${NC}"
    echo "- Keep-alive: Every 10 minutes"
    echo "- Monitoring: Every 5 minutes"
    echo "- Duration: 1 hour"
    echo ""
    echo "Check progress:"
    echo "  tail -f $PROJECT_ROOT/logs/auth-status-monitor.log"
    echo ""
    echo "After 1 hour, run:"
    echo "  $SCRIPT_DIR/monitor-auth-lifetime.sh report"
    
    log_message "Quick test configured successfully"
}

daily_test() {
    log_message "Starting Daily Test (24 hours, 6-hour intervals)"
    
    # Remove existing cron jobs
    crontab -l 2>/dev/null | grep -v keep-alive-claude-max | crontab - 2>/dev/null
    crontab -l 2>/dev/null | grep -v monitor-auth-lifetime | crontab - 2>/dev/null
    
    # Add moderate keep-alive
    (crontab -l 2>/dev/null; echo "0 */6 * * * $SCRIPT_DIR/keep-alive-claude-max.sh >> $PROJECT_ROOT/logs/keep-alive-test.log 2>&1") | crontab -
    (crontab -l 2>/dev/null; echo "0 * * * * $SCRIPT_DIR/monitor-auth-lifetime.sh monitor") | crontab -
    
    echo -e "${GREEN}✅ Daily test started${NC}"
    echo "- Keep-alive: Every 6 hours"
    echo "- Monitoring: Every hour"
    echo "- Duration: 24 hours"
    echo ""
    echo "Check progress:"
    echo "  tail -f $PROJECT_ROOT/logs/auth-status-monitor.log"
    
    log_message "Daily test configured successfully"
}

endurance_test() {
    log_message "Starting Endurance Test (7 days, 12-hour intervals)"
    
    # Remove existing cron jobs
    crontab -l 2>/dev/null | grep -v keep-alive-claude-max | crontab - 2>/dev/null
    crontab -l 2>/dev/null | grep -v monitor-auth-lifetime | crontab - 2>/dev/null
    
    # Add conservative keep-alive
    (crontab -l 2>/dev/null; echo "0 */12 * * * $SCRIPT_DIR/keep-alive-claude-max.sh >> $PROJECT_ROOT/logs/keep-alive-test.log 2>&1") | crontab -
    (crontab -l 2>/dev/null; echo "0 */2 * * * $SCRIPT_DIR/monitor-auth-lifetime.sh monitor") | crontab -
    
    echo -e "${GREEN}✅ Endurance test started${NC}"
    echo "- Keep-alive: Every 12 hours"
    echo "- Monitoring: Every 2 hours"
    echo "- Duration: 7 days"
    echo ""
    echo "Check daily progress:"
    echo "  $SCRIPT_DIR/monitor-auth-lifetime.sh report"
    
    log_message "Endurance test configured successfully"
}

control_test() {
    log_message "Starting Control Test (monitoring only, no keep-alive)"
    
    # Remove ALL cron jobs
    crontab -l 2>/dev/null | grep -v keep-alive-claude-max | crontab - 2>/dev/null
    crontab -l 2>/dev/null | grep -v monitor-auth-lifetime | crontab - 2>/dev/null
    
    # Add only monitoring
    (crontab -l 2>/dev/null; echo "0 * * * * $SCRIPT_DIR/monitor-auth-lifetime.sh monitor") | crontab -
    
    echo -e "${YELLOW}⚠️  Control test started (NO keep-alive)${NC}"
    echo "- Keep-alive: DISABLED"
    echo "- Monitoring: Every hour"
    echo "- Purpose: Establish baseline decay"
    echo ""
    echo "This will show natural session timeout without intervention."
    echo ""
    echo "Check progress:"
    echo "  tail -f $PROJECT_ROOT/logs/auth-status-monitor.log"
    
    log_message "Control test configured (no keep-alive)"
}

view_status() {
    echo "📊 Current Experiment Status"
    echo "============================="
    echo ""
    
    # Check auth status
    AUTH_AGE=$($SCRIPT_DIR/monitor-auth-lifetime.sh monitor 2>&1 | grep "Auth Age:" | awk '{print $3}')
    echo "Authentication age: ${AUTH_AGE} hours"
    
    # Check cron jobs
    echo ""
    echo "Scheduled jobs:"
    if crontab -l 2>/dev/null | grep -q keep-alive-claude-max; then
        echo -e "${GREEN}✅ Keep-alive is scheduled${NC}"
        crontab -l | grep keep-alive-claude-max
    else
        echo -e "${YELLOW}⚠️  Keep-alive is NOT scheduled${NC}"
    fi
    
    if crontab -l 2>/dev/null | grep -q monitor-auth-lifetime; then
        echo -e "${GREEN}✅ Monitoring is scheduled${NC}"
        crontab -l | grep monitor-auth-lifetime
    else
        echo -e "${YELLOW}⚠️  Monitoring is NOT scheduled${NC}"
    fi
    
    # Show recent activity
    echo ""
    echo "Recent keep-alive activity:"
    if [ -f "$PROJECT_ROOT/logs/keep-alive-test.log" ]; then
        tail -3 "$PROJECT_ROOT/logs/keep-alive-test.log"
    else
        echo "No keep-alive logs yet"
    fi
    
    echo ""
    echo "Recent monitoring:"
    if [ -f "$PROJECT_ROOT/logs/auth-status-monitor.log" ]; then
        tail -3 "$PROJECT_ROOT/logs/auth-status-monitor.log"
    else
        echo "No monitoring logs yet"
    fi
    
    # Generate report if data exists
    if [ -f "$PROJECT_ROOT/logs/auth-lifetime-monitor.csv" ]; then
        echo ""
        echo "Data points collected: $(wc -l < "$PROJECT_ROOT/logs/auth-lifetime-monitor.csv")"
        echo ""
        echo "Run full report:"
        echo "  $SCRIPT_DIR/monitor-auth-lifetime.sh report"
    fi
}

stop_all() {
    log_message "Stopping all experiments"
    
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v keep-alive-claude-max | crontab - 2>/dev/null
    crontab -l 2>/dev/null | grep -v monitor-auth-lifetime | crontab - 2>/dev/null
    
    echo -e "${RED}🛑 All experiments stopped${NC}"
    echo ""
    echo "Cron jobs removed:"
    echo "- Keep-alive schedule cleared"
    echo "- Monitoring schedule cleared"
    echo ""
    echo "Logs preserved in:"
    echo "- $PROJECT_ROOT/logs/keep-alive-test.log"
    echo "- $PROJECT_ROOT/logs/auth-status-monitor.log"
    echo "- $PROJECT_ROOT/logs/auth-lifetime-monitor.csv"
    
    log_message "All experiments stopped"
}

# Main
mkdir -p "$PROJECT_ROOT/logs"

show_menu

case $choice in
    1)
        quick_test
        ;;
    2)
        daily_test
        ;;
    3)
        endurance_test
        ;;
    4)
        control_test
        ;;
    5)
        view_status
        ;;
    6)
        stop_all
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
log_message "Experiment script completed"
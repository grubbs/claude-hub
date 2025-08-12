#!/bin/bash
# Interactive Claude log viewer

LOG_DIR="/home/daniel/claude-hub/logs/claude-sessions"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_menu() {
    echo ""
    echo "=== Claude Log Viewer ==="
    echo "1) View latest session"
    echo "2) List all sessions (newest first)"
    echo "3) Search logs by repository"
    echo "4) Search logs by date"
    echo "5) View specific log file"
    echo "6) Show tool usage statistics"
    echo "7) Show session summary"
    echo "8) Clean logs older than 30 days"
    echo "q) Quit"
    echo ""
    echo -n "Select option: "
}

view_latest() {
    LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [ -z "$LATEST" ]; then
        echo "No logs found"
        return
    fi
    echo -e "${GREEN}Latest session: $(basename $LATEST)${NC}"
    less "$LATEST"
}

list_sessions() {
    echo -e "${BLUE}Recent Claude sessions:${NC}"
    ls -lht "$LOG_DIR"/*.log 2>/dev/null | head -20 | awk '{print $9, $6, $7, $8}' | while read file date time year; do
        basename "$file"
        echo "  Date: $date $time"
        grep "Repository:" "$file" | head -1
        grep "Issue/PR:" "$file" | head -1
        echo ""
    done
}

search_by_repo() {
    echo -n "Enter repository name (e.g., owner/repo): "
    read repo
    echo -e "${BLUE}Sessions for $repo:${NC}"
    grep -l "Repository: $repo" "$LOG_DIR"/*.log 2>/dev/null | while read file; do
        echo "$(basename $file)"
        grep "Start Time:" "$file"
        echo ""
    done
}

view_specific() {
    echo -n "Enter log filename: "
    read filename
    if [ -f "$LOG_DIR/$filename" ]; then
        less "$LOG_DIR/$filename"
    else
        echo -e "${RED}File not found${NC}"
    fi
}

show_tool_usage() {
    echo -e "${BLUE}Tool Usage Statistics:${NC}"
    echo ""
    
    # Count tool usage across all logs
    for tool in "Bash" "Read" "Edit" "Write" "Search" "GitHub"; do
        count=$(grep -h "Tool: $tool" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        if [ $count -gt 0 ]; then
            printf "%-10s: %d times\n" "$tool" "$count"
        fi
    done
}

show_summary() {
    echo -e "${BLUE}Session Summary:${NC}"
    echo ""
    
    # Count sessions by status
    total=$(ls "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    completed=$(grep -l "Session completed" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    errors=$(grep -l "ERROR\|error" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    
    echo "Total sessions: $total"
    echo "Completed: $completed"
    echo "With errors: $errors"
    echo ""
    
    # Show disk usage
    if [ -d "$LOG_DIR" ]; then
        echo "Disk usage: $(du -sh "$LOG_DIR" | cut -f1)"
    fi
}

clean_old_logs() {
    echo "Cleaning logs older than 30 days..."
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete
    echo "Done!"
}

# Main loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) view_latest ;;
        2) list_sessions | less ;;
        3) search_by_repo ;;
        4) 
            echo -n "Enter date (YYYYMMDD): "
            read date
            ls -la "$LOG_DIR"/*${date}*.log 2>/dev/null || echo "No logs for that date"
            ;;
        5) view_specific ;;
        6) show_tool_usage ;;
        7) show_summary ;;
        8) clean_old_logs ;;
        q|Q) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
done
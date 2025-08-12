#!/bin/bash
# Setup tmux session with Claude monitoring layout
# This version assumes ngrok is already running elsewhere
# Layout: Main (Claude Code) | Right split (ngrok status top, monitor bottom)

SESSION_NAME="claude-hub"
CLAUDE_DIR="/home/daniel/claude-hub"

# Check if session already exists
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? != 0 ]; then
    echo "Creating new tmux session: $SESSION_NAME"
    
    # Create new session with main window for Claude Code
    tmux new-session -d -s $SESSION_NAME -n "claude" -c "$CLAUDE_DIR"
    
    # Split window vertically (main left, right pane for ngrok/monitor)
    tmux split-window -h -t $SESSION_NAME:0 -c "$CLAUDE_DIR"
    
    # Split right pane horizontally (ngrok status top, monitor bottom)
    tmux split-window -v -t $SESSION_NAME:0.1 -c "$CLAUDE_DIR"
    
    # Adjust pane sizes (60% for main, 40% for right side)
    tmux resize-pane -t $SESSION_NAME:0.0 -x 60%
    
    # Start services in each pane
    # Pane 0 (left): Interactive shell for Claude Code
    tmux send-keys -t $SESSION_NAME:0.0 "echo 'Claude Code terminal ready'" C-m
    tmux send-keys -t $SESSION_NAME:0.0 "echo 'Usage: @grubbs-claude-bot [command] in GitHub issues/PRs'" C-m
    tmux send-keys -t $SESSION_NAME:0.0 "echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.0 "# Check webhook status" C-m
    tmux send-keys -t $SESSION_NAME:0.0 "docker compose ps webhook" C-m
    
    # Pane 1 (top-right): Ngrok status monitor (since ngrok is already running)
    tmux send-keys -t $SESSION_NAME:0.1 "echo 'Ngrok Status Monitor (ngrok already running)'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "echo '========================================'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "echo ''" C-m
    
    # Create a simple ngrok status monitor
    tmux send-keys -t $SESSION_NAME:0.1 "while true; do" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  clear" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo 'NGROK TUNNEL STATUS'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo '=================='" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  # Check if ngrok is running" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  if pgrep -x ngrok > /dev/null; then" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    echo '✓ Ngrok is running'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    # Get tunnel info from ngrok API" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    if curl -s http://localhost:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[] | select(.proto==\"https\") | \"Public URL: \" + .public_url' 2>/dev/null; then" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "      echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "      curl -s http://localhost:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[] | select(.proto==\"https\") | \"Forwarding: \" + .config.addr' 2>/dev/null" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    else" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "      echo 'Unable to get tunnel info'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    fi" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  else" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    echo '✗ Ngrok is not running'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "    echo 'To start ngrok: ngrok http 3002'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  fi" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo 'Web Interface: http://localhost:4040'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo ''" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  echo '[Refreshing every 5 seconds...]'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "  sleep 5" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "done" C-m
    
    # Pane 2 (bottom-right): Monitor
    tmux send-keys -t $SESSION_NAME:0.2 "./scripts/tmux-monitor.sh" C-m
    
    # Set pane titles
    tmux select-pane -t $SESSION_NAME:0.0 -T "Claude Code"
    tmux select-pane -t $SESSION_NAME:0.1 -T "Ngrok Status"
    tmux select-pane -t $SESSION_NAME:0.2 -T "Monitor"
    
    # Enable pane status
    tmux set -t $SESSION_NAME pane-border-status top
    
    # Focus on main pane
    tmux select-pane -t $SESSION_NAME:0.0
    
    echo "Tmux session created with layout:"
    echo "  Left:         Claude Code terminal"
    echo "  Top-Right:    Ngrok status monitor (for existing ngrok process)"
    echo "  Bottom-Right: Real-time Claude monitor"
    echo ""
    echo "To attach: tmux attach -t $SESSION_NAME"
else
    echo "Session $SESSION_NAME already exists"
    echo "To attach: tmux attach -t $SESSION_NAME"
    echo "To kill and recreate: tmux kill-session -t $SESSION_NAME"
fi
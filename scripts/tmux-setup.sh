#!/bin/bash
# Setup tmux session with Claude monitoring layout
# Layout: Main (Claude Code) | Right split (ngrok top, monitor bottom)

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
    
    # Split right pane horizontally (ngrok top, monitor bottom)
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
    
    # Pane 1 (top-right): ngrok
    tmux send-keys -t $SESSION_NAME:0.1 "echo 'Starting ngrok tunnel...'" C-m
    tmux send-keys -t $SESSION_NAME:0.1 "ngrok http 3002" C-m
    
    # Pane 2 (bottom-right): Monitor
    tmux send-keys -t $SESSION_NAME:0.2 "./scripts/tmux-monitor.sh" C-m
    
    # Set pane titles
    tmux select-pane -t $SESSION_NAME:0.0 -T "Claude Code"
    tmux select-pane -t $SESSION_NAME:0.1 -T "Ngrok Tunnel"
    tmux select-pane -t $SESSION_NAME:0.2 -T "Monitor"
    
    # Enable pane status
    tmux set -t $SESSION_NAME pane-border-status top
    
    # Focus on main pane
    tmux select-pane -t $SESSION_NAME:0.0
    
    echo "Tmux session created with layout:"
    echo "  Left:         Claude Code terminal"
    echo "  Top-Right:    Ngrok tunnel"
    echo "  Bottom-Right: Real-time monitor"
    echo ""
    echo "To attach: tmux attach -t $SESSION_NAME"
else
    echo "Session $SESSION_NAME already exists"
    echo "To attach: tmux attach -t $SESSION_NAME"
    echo "To kill and recreate: tmux kill-session -t $SESSION_NAME"
fi
#!/bin/bash
# Enhanced entrypoint script with full logging

# Generate unique log filename
LOG_DIR="/logs/claude-sessions"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER_NAME="${REPO_FULL_NAME//\//_}_${ISSUE_NUMBER}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${CONTAINER_NAME}.log"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Start logging
{
    echo "=========================================="
    echo "Claude Session Log"
    echo "=========================================="
    echo "Start Time: $(date)"
    echo "Repository: $REPO_FULL_NAME"
    echo "Issue/PR: #$ISSUE_NUMBER"
    echo "Operation Type: $OPERATION_TYPE"
    echo "Container: $(hostname)"
    echo "=========================================="
    echo ""
} > "$LOG_FILE"

# Log all environment setup
log_message "Setting up environment..."

# Function to setup Claude authentication
setup_claude_auth() {
    log_message "Setting up Claude authentication..."
    
    if [ -d "/home/node/.claude" ]; then
        log_message "Found mounted auth directory"
        cp -r /home/node/.claude /workspace/.claude 2>&1 | tee -a "$LOG_FILE"
        chown -R node:node /workspace/.claude 2>&1 | tee -a "$LOG_FILE"
        log_message "Authentication directory synced"
    fi
}

# Function to clone repository
clone_repository() {
    log_message "Cloning repository $REPO_FULL_NAME..."
    
    # Configure git with GitHub token for authentication
    if [ -n "$GITHUB_TOKEN" ]; then
        git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
        log_message "Configured GitHub authentication"
    fi
    
    cd /workspace
    git clone "https://github.com/${REPO_FULL_NAME}.git" repo 2>&1 | tee -a "$LOG_FILE"
    cd repo
    
    if [ "$IS_PULL_REQUEST" = "true" ] && [ -n "$BRANCH_NAME" ]; then
        log_message "Checking out PR branch: $BRANCH_NAME"
        git fetch origin "$BRANCH_NAME" 2>&1 | tee -a "$LOG_FILE"
        git checkout "$BRANCH_NAME" 2>&1 | tee -a "$LOG_FILE"
    else
        log_message "Using main branch"
    fi
}

# Function to run Claude with full output capture
run_claude() {
    log_message "Starting Claude Code CLI..."
    log_message "Command length: ${#COMMAND} characters"
    
    cd /workspace/repo
    
    # Determine Claude command based on operation type
    if [ "$OPERATION_TYPE" = "tagging" ]; then
        log_message "Running in tagging mode (limited tools)..."
        CLAUDE_CMD="claude --allowedTools Read,GitHub"
    else
        log_message "Running with full tool access..."
        CLAUDE_CMD="claude"
    fi
    
    # Run Claude and capture ALL output (stdout, stderr, and tool usage)
    log_message "========== CLAUDE OUTPUT START =========="
    
    # Use script command to capture full terminal output including colors and tool usage
    # Note: Using printf to handle multi-line commands properly
    script -q -c "printf '%s\n' \"\$COMMAND\" | HOME=/workspace CLAUDE_HOME=/workspace/.claude $CLAUDE_CMD" "$LOG_FILE.raw" 2>&1
    
    # Also capture with regular output for processing
    printf '%s\n' "$COMMAND" | HOME=/workspace CLAUDE_HOME=/workspace/.claude $CLAUDE_CMD 2>&1 | while IFS= read -r line; do
        echo "$line" | tee -a "$LOG_FILE"
        
        # Detect and highlight tool usage
        if echo "$line" | grep -q "Tool:"; then
            echo ">>> TOOL USAGE: $line" >> "$LOG_FILE"
        fi
    done
    
    log_message "========== CLAUDE OUTPUT END =========="
}

# Main execution flow with logging
{
    setup_claude_auth
    clone_repository
    run_claude
    
    log_message "Session completed"
    echo ""
    echo "=========================================="
    echo "End Time: $(date)"
    echo "Log saved to: $LOG_FILE"
    echo "=========================================="
} 2>&1 | tee -a "$LOG_FILE"

# Copy log to persistent location if needed
if [ -d "/home/daniel/claude-hub/logs/claude-sessions" ]; then
    cp "$LOG_FILE" "/home/daniel/claude-hub/logs/claude-sessions/" 2>/dev/null || true
fi

# Output summary for webhook
echo "Session completed. Log: $LOG_FILE"
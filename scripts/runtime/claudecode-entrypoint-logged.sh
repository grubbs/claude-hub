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

# Ensure workspace directory exists and has proper permissions
mkdir -p /workspace
chown -R node:node /workspace

# Function to setup Claude authentication
setup_claude_auth() {
    log_message "Setting up Claude authentication..."
    
    if [ -d "/home/node/.claude" ]; then
        log_message "Found mounted auth directory"
        mkdir -p /workspace/.claude
        cp -r /home/node/.claude/* /workspace/.claude/ 2>&1 | tee -a "$LOG_FILE" || true
        cp -r /home/node/.claude/.* /workspace/.claude/ 2>&1 | grep -v "omitting directory" | tee -a "$LOG_FILE" || true
        chown -R node:node /workspace/.claude 2>&1 | tee -a "$LOG_FILE"
        chmod 600 /workspace/.claude/.credentials.json 2>/dev/null || true
        log_message "Authentication directory synced"
    fi
}

# Function to clone repository
clone_repository() {
    log_message "Cloning repository $REPO_FULL_NAME..."
    
    # Setup GitHub CLI authentication
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>&1 | tee -a "$LOG_FILE"
        gh auth setup-git 2>&1 | tee -a "$LOG_FILE"
        log_message "Configured GitHub CLI authentication"
    fi
    
    cd /workspace
    if [ -n "$GITHUB_TOKEN" ]; then
        git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_FULL_NAME}.git" repo 2>&1 | tee -a "$LOG_FILE"
    else
        git clone "https://github.com/${REPO_FULL_NAME}.git" repo 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Fix ownership so Claude (running as node user) can write to the repository
    chown -R node:node /workspace/repo
    log_message "Fixed repository ownership for node user"
    
    cd repo
    
    # Configure git for commits
    git config --global user.email "${BOT_EMAIL:-claude@example.com}"
    git config --global user.name "${BOT_USERNAME:-ClaudeBot}"
    
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
    
    # Determine Claude command and allowed tools based on operation type
    if [ "$OPERATION_TYPE" = "auto-tagging" ]; then
        log_message "Running in tagging mode (limited tools)..."
        ALLOWED_TOOLS="Read,GitHub,Bash(gh issue edit:*),Bash(gh issue view:*),Bash(gh label list:*)"
    elif [ "$OPERATION_TYPE" = "pr-review" ] || [ "$OPERATION_TYPE" = "manual-pr-review" ]; then
        log_message "Running in PR review mode (broad research access)..."
        ALLOWED_TOOLS="Read,GitHub,Bash(gh:*),Bash(git log:*),Bash(git show:*),Bash(git diff:*),Bash(git blame:*),Bash(find:*),Bash(grep:*),Bash(rg:*),Bash(cat:*),Bash(head:*),Bash(tail:*),Bash(ls:*),Bash(tree:*)"
    else
        log_message "Running with full tool access..."
        # Include gh pr and gh issue commands for full GitHub integration
        ALLOWED_TOOLS="Bash,Create,Edit,Read,Write,GitHub,Bash(gh pr:*),Bash(gh issue:*)"
    fi
    
    # Build the full Claude command
    CLAUDE_CMD="/usr/local/share/npm-global/bin/claude --allowedTools \"${ALLOWED_TOOLS}\" --verbose"
    
    # Run Claude and capture ALL output (stdout, stderr, and tool usage)
    log_message "========== CLAUDE OUTPUT START =========="
    
    # Use script command to capture full terminal output including colors and tool usage
    # Using --print flag for non-interactive execution with all environment variables
    script -q -c "sudo -u node -E env \
        HOME=/workspace \
        CLAUDE_HOME=/workspace/.claude \
        PATH=\"/usr/local/bin:/usr/local/share/npm-global/bin:\$PATH\" \
        ANTHROPIC_API_KEY=\"\${ANTHROPIC_API_KEY}\" \
        GH_TOKEN=\"\${GITHUB_TOKEN}\" \
        GITHUB_TOKEN=\"\${GITHUB_TOKEN}\" \
        BASH_DEFAULT_TIMEOUT_MS=\"\${BASH_DEFAULT_TIMEOUT_MS}\" \
        BASH_MAX_TIMEOUT_MS=\"\${BASH_MAX_TIMEOUT_MS}\" \
        $CLAUDE_CMD --print \"\$COMMAND\"" "$LOG_FILE.raw" 2>&1
    
    # Also capture with regular output for processing
    sudo -u node -E env \
        HOME=/workspace \
        CLAUDE_HOME=/workspace/.claude \
        PATH="/usr/local/bin:/usr/local/share/npm-global/bin:$PATH" \
        ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
        GH_TOKEN="${GITHUB_TOKEN}" \
        GITHUB_TOKEN="${GITHUB_TOKEN}" \
        BASH_DEFAULT_TIMEOUT_MS="${BASH_DEFAULT_TIMEOUT_MS}" \
        BASH_MAX_TIMEOUT_MS="${BASH_MAX_TIMEOUT_MS}" \
        $CLAUDE_CMD --print "$COMMAND" 2>&1 | while IFS= read -r line; do
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
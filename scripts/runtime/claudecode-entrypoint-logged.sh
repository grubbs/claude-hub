#!/bin/bash
# Enhanced entrypoint script with full logging

# Generate unique log filename
LOG_DIR="/logs/claude-sessions"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER_NAME="${REPO_FULL_NAME//\//_}_${ISSUE_NUMBER}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${CONTAINER_NAME}.log"

# Function to log with timestamp (only to log file, not stdout)
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
        cp -r /home/node/.claude/* /workspace/.claude/ 2>&1 >> "$LOG_FILE" || true
        cp -r /home/node/.claude/.* /workspace/.claude/ 2>&1 | grep -v "omitting directory" >> "$LOG_FILE" || true
        chown -R node:node /workspace/.claude 2>&1 >> "$LOG_FILE"
        chmod 600 /workspace/.claude/.credentials.json 2>/dev/null || true
        log_message "Authentication directory synced"
    fi
}

# Function to clone repository
clone_repository() {
    log_message "Cloning repository $REPO_FULL_NAME..."
    
    # Setup GitHub CLI authentication
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>&1 >> "$LOG_FILE"
        gh auth setup-git 2>&1 >> "$LOG_FILE"
        log_message "Configured GitHub CLI authentication"
    fi
    
    cd /workspace
    if [ -n "$GITHUB_TOKEN" ]; then
        git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_FULL_NAME}.git" repo 2>&1 >> "$LOG_FILE"
    else
        git clone "https://github.com/${REPO_FULL_NAME}.git" repo 2>&1 >> "$LOG_FILE"
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
        git fetch origin "$BRANCH_NAME" 2>&1 >> "$LOG_FILE"
        git checkout "$BRANCH_NAME" 2>&1 >> "$LOG_FILE"
    else
        log_message "Using main branch"
    fi
}

# Function to run Claude with proper response separation
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
    CLAUDE_CMD="/usr/local/share/npm-global/bin/claude --allowedTools \"${ALLOWED_TOOLS}\""
    
    # Run Claude and capture ALL output for logging
    log_message "========== CLAUDE OUTPUT START =========="
    
    # Create temporary files for processing (using main's approach for better temp file management)
    FULL_OUTPUT="/tmp/claude_full_$$.txt"
    RESPONSE_FILE="/tmp/claude_response_$$.txt"
    
    # Run Claude with full output capture to file only (NO tee to prevent double output)
    sudo -u node -E env \
        HOME=/workspace \
        CLAUDE_HOME=/workspace/.claude \
        PATH="/usr/local/bin:/usr/local/share/npm-global/bin:$PATH" \
        ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
        GH_TOKEN="${GITHUB_TOKEN}" \
        GITHUB_TOKEN="${GITHUB_TOKEN}" \
        BASH_DEFAULT_TIMEOUT_MS="${BASH_DEFAULT_TIMEOUT_MS}" \
        BASH_MAX_TIMEOUT_MS="${BASH_MAX_TIMEOUT_MS}" \
        $CLAUDE_CMD --print "$COMMAND" 2>&1 > "$FULL_OUTPUT"
    
    # Log the full output for debugging
    cat "$FULL_OUTPUT" >> "$LOG_FILE"
    
    # Extract only Claude's response (everything after the last tool invocation)
    # Look for the last occurrence of tool usage patterns
    last_tool_line=$(grep -n "^Tool:\|^Using\|^Running\|^Executing" "$FULL_OUTPUT" 2>/dev/null | tail -1 | cut -d: -f1)
    
    if [ -n "$last_tool_line" ]; then
        # Extract everything after the last tool usage, excluding empty lines
        tail -n +$((last_tool_line + 1)) "$FULL_OUTPUT" | grep -v "^$" > "$RESPONSE_FILE"
    else
        # No tools used, output the entire response
        cat "$FULL_OUTPUT" > "$RESPONSE_FILE"
    fi
    
    log_message "========== CLAUDE OUTPUT END =========="
    
    # Output the response to stdout (this goes to GitHub) with markers
    echo "__CLAUDE_RESPONSE_START__"
    if [ -f "$RESPONSE_FILE" ] && [ -s "$RESPONSE_FILE" ]; then
        cat "$RESPONSE_FILE"
    else
        # If no response was extracted, provide a helpful error message
        echo "❌ No response content extracted from Claude. Please check the system logs."
    fi
    echo "__CLAUDE_RESPONSE_END__"
    
    # Clean up temporary files
    rm -f "$FULL_OUTPUT" "$RESPONSE_FILE"
}

# Main execution flow with selective logging
# Run setup and auth (redirect to log file only)
{
    setup_claude_auth
    clone_repository
} 2>&1 >> "$LOG_FILE"

# Run Claude (outputs to both stdout for GitHub AND logs internally)
run_claude

# Final logging (log file only)
{
    log_message "Session completed"
    echo ""
    echo "=========================================="
    echo "End Time: $(date)"
    echo "Log saved to: $LOG_FILE"
    echo "=========================================="
} >> "$LOG_FILE"

# Copy log to persistent location if needed
if [ -d "/home/daniel/claude-hub/logs/claude-sessions" ]; then
    cp "$LOG_FILE" "/home/daniel/claude-hub/logs/claude-sessions/" 2>/dev/null || true
fi

# Don't output any summary to stdout - Claude's response has already been output
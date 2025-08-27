#!/bin/bash
# FIXED entrypoint script - complete rewrite to eliminate hanging issues

# Exit on any error
set -e

# Trap to ensure we always exit cleanly
trap 'echo "[$(date)] Script exiting with code $?" >&2; exit' EXIT INT TERM

# Generate unique log filename
LOG_DIR="/logs/claude-sessions"
mkdir -p "$LOG_DIR" || true
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER_NAME="${REPO_FULL_NAME//\//_}_${ISSUE_NUMBER}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${CONTAINER_NAME}.log"

# Initialize log file
{
    echo "=========================================="
    echo "Claude Session Log"
    echo "=========================================="
    echo "Start Time: $(date)"
    echo "Repository: $REPO_FULL_NAME"
    echo "Issue/PR: #$ISSUE_NUMBER"
    echo "Operation Type: $OPERATION_TYPE"
    echo "=========================================="
} > "$LOG_FILE" 2>&1 || true

# Function to log only to file
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>&1 || true
}

# Setup Claude authentication
log_to_file "Setting up Claude authentication..."
if [ -d "/home/node/.claude" ]; then
    mkdir -p /workspace/.claude
    cp -r /home/node/.claude/* /workspace/.claude/ 2>> "$LOG_FILE" || true
    chown -R node:node /workspace/.claude 2>> "$LOG_FILE" || true
    log_to_file "Authentication directory synced"
fi

# Setup workspace
mkdir -p /workspace
chown -R node:node /workspace

# Clone repository
log_to_file "Cloning repository $REPO_FULL_NAME..."
cd /workspace
if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token >> "$LOG_FILE" 2>&1 || true
    gh auth setup-git >> "$LOG_FILE" 2>&1 || true
    git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_FULL_NAME}.git" repo >> "$LOG_FILE" 2>&1 || true
else
    git clone "https://github.com/${REPO_FULL_NAME}.git" repo >> "$LOG_FILE" 2>&1 || true
fi

# Configure git
cd /workspace/repo || exit 1
git config --global user.email "${BOT_EMAIL:-claude@example.com}"
git config --global user.name "${BOT_USERNAME:-ClaudeBot}"

# Handle branch checkout
if [ "$IS_PULL_REQUEST" = "true" ] && [ -n "$BRANCH_NAME" ]; then
    log_to_file "Checking out PR branch: $BRANCH_NAME"
    git fetch origin "$BRANCH_NAME" >> "$LOG_FILE" 2>&1 || true
    git checkout "$BRANCH_NAME" >> "$LOG_FILE" 2>&1 || true
fi

# Determine allowed tools based on operation type
if [ "$OPERATION_TYPE" = "auto-tagging" ]; then
    ALLOWED_TOOLS="Read,GitHub,Bash(gh issue edit:*),Bash(gh issue view:*),Bash(gh label list:*)"
elif [ "$OPERATION_TYPE" = "pr-review" ] || [ "$OPERATION_TYPE" = "manual-pr-review" ]; then
    ALLOWED_TOOLS="Read,GitHub,Bash(gh:*),Bash(git log:*),Bash(git show:*),Bash(git diff:*)"
else
    ALLOWED_TOOLS="Bash,Create,Edit,Read,Write,GitHub,Bash(gh pr:*),Bash(gh issue:*)"
fi

# Build Claude command
CLAUDE_CMD="/usr/local/share/npm-global/bin/claude --allowedTools \"${ALLOWED_TOOLS}\""

# Create temp file for Claude output
CLAUDE_OUTPUT="/tmp/claude_output_$$.txt"

log_to_file "Starting Claude Code CLI..."
log_to_file "========== CLAUDE OUTPUT START =========="

# Run Claude and capture output to file
# IMPORTANT: Run in foreground, capture all output to file
sudo -u node -E env \
    HOME=/workspace \
    CLAUDE_HOME=/workspace/.claude \
    PATH="/usr/local/bin:/usr/local/share/npm-global/bin:$PATH" \
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    GH_TOKEN="${GITHUB_TOKEN}" \
    GITHUB_TOKEN="${GITHUB_TOKEN}" \
    $CLAUDE_CMD --print "$COMMAND" > "$CLAUDE_OUTPUT" 2>&1

# Log Claude's output
cat "$CLAUDE_OUTPUT" >> "$LOG_FILE" 2>&1 || true

log_to_file "========== CLAUDE OUTPUT END =========="

# Extract Claude's response for GitHub
# Look for the last tool usage and output everything after it
last_tool_line=$(grep -n "^Tool:\|^Using\|^Running\|^Executing" "$CLAUDE_OUTPUT" 2>/dev/null | tail -1 | cut -d: -f1)

# Output response with markers
echo "__CLAUDE_RESPONSE_START__"
if [ -n "$last_tool_line" ]; then
    tail -n +$((last_tool_line + 1)) "$CLAUDE_OUTPUT" | grep -v "^$"
else
    cat "$CLAUDE_OUTPUT"
fi
echo "__CLAUDE_RESPONSE_END__"

# Clean up
rm -f "$CLAUDE_OUTPUT"

# Final log entry
{
    echo ""
    echo "=========================================="
    echo "End Time: $(date)"
    echo "Log saved to: $LOG_FILE"
    echo "=========================================="
} >> "$LOG_FILE" 2>&1 || true

log_to_file "Session completed successfully"

# Explicit exit
exit 0
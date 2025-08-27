#!/bin/bash
# DEBUG version of the entrypoint script to diagnose hanging issues

# Enable debug mode
set -x

# Output to stderr so we can see what's happening
echo "DEBUG: Script started at $(date)" >&2
echo "DEBUG: PID: $$" >&2
echo "DEBUG: REPO_FULL_NAME: $REPO_FULL_NAME" >&2
echo "DEBUG: ISSUE_NUMBER: $ISSUE_NUMBER" >&2

# Generate unique log filename
LOG_DIR="/logs/claude-sessions"
echo "DEBUG: Creating log directory: $LOG_DIR" >&2
mkdir -p "$LOG_DIR" 2>&1 | tee /dev/stderr
echo "DEBUG: Log directory created, checking if it exists..." >&2
ls -la "$LOG_DIR" 2>&1 | tee /dev/stderr

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER_NAME="${REPO_FULL_NAME//\//_}_${ISSUE_NUMBER}_${TIMESTAMP}"
LOG_FILE="$LOG_DIR/${CONTAINER_NAME}.log"

echo "DEBUG: Log file will be: $LOG_FILE" >&2
echo "DEBUG: Testing write to log file..." >&2
echo "TEST WRITE" > "$LOG_FILE" 2>&1 | tee /dev/stderr
cat "$LOG_FILE" 2>&1 | tee /dev/stderr

# Simple test: Just output the markers and a message
echo "DEBUG: Outputting response markers..." >&2
echo "__CLAUDE_RESPONSE_START__"
echo "DEBUG TEST: This is a test response from the debug script"
echo "Container started at: $(date)"
echo "Script PID: $$"
echo "Log file: $LOG_FILE"
echo "__CLAUDE_RESPONSE_END__"

echo "DEBUG: Response markers sent" >&2
echo "DEBUG: Script completing at $(date)" >&2
echo "DEBUG: Exiting with code 0" >&2

exit 0
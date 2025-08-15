#!/bin/bash
# Note: set -e disabled because touch commands may fail with permission errors (expected)

# Script to keep Claude Max authentication alive by performing periodic operations
# This helps prevent session timeout by maintaining activity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"
LOG_FILE="$PROJECT_ROOT/logs/claude-keep-alive.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo "🔄 Claude Max Keep-Alive Service"
echo "================================="
echo ""

log_message "Starting Claude Max keep-alive check"

# Check if auth directory exists
if [ ! -d "$AUTH_DIR" ]; then
    log_message "ERROR: Authentication directory not found: $AUTH_DIR"
    echo -e "${RED}❌ Authentication directory not found: $AUTH_DIR${NC}"
    exit 1
fi

# Build Docker image if needed
if ! docker images | grep -q "claude-setup"; then
    log_message "Building claude-setup image..."
    docker build -f "$PROJECT_ROOT/Dockerfile.claude-setup" -t claude-setup:latest "$PROJECT_ROOT" > /dev/null 2>&1
fi

# Removed perform_keep_alive function - now using direct Claude execution instead

# Track success/failure
SUCCESS_COUNT=0
FAILURE_COUNT=0

# Perform various keep-alive operations
echo ""
echo "🔧 Performing keep-alive operations..."
echo ""

# 1. Execute actual Claude command to maintain session
echo "Testing Claude session with simple command..."
log_message "Executing Claude keep-alive command"

# Create a temporary test file for Claude to read
TEST_FILE="/tmp/claude-keepalive-test-$$"
echo "Keep-alive test at $(date)" > "$TEST_FILE"

# Run Claude with a simple command that uses the API
if docker run --rm \
    -v "${AUTH_DIR}:/home/node/.claude" \
    -v "/tmp:/tmp" \
    --network host \
    claude-setup:latest \
    sh -c "echo 'Testing session' | claude --no-interactive" > /dev/null 2>&1; then
    
    echo -e "${GREEN}✅ Claude session active - keep-alive successful${NC}"
    log_message "SUCCESS: Claude session is active"
    ((SUCCESS_COUNT++))
else
    echo -e "${RED}❌ Claude session expired or unavailable${NC}"
    log_message "FAILED: Claude session expired or unavailable"
    ((FAILURE_COUNT++))
fi

# Clean up test file
rm -f "$TEST_FILE"

# 2. Verify authentication files still exist
echo "Verifying authentication files..."
if [ -f "$AUTH_DIR/.credentials.json" ]; then
    echo -e "${GREEN}✅ Authentication file exists${NC}"
    log_message "SUCCESS: Auth file exists"
    ((SUCCESS_COUNT++))
else
    echo -e "${RED}❌ Authentication file not found${NC}"
    log_message "FAILED: Auth file missing"
    ((FAILURE_COUNT++))
fi

# 3. Verify statsig directory exists and has recent files
if [ -d "$AUTH_DIR/statsig" ]; then
    STATSIG_FILES=$(ls -1 "$AUTH_DIR/statsig" 2>/dev/null | wc -l)
    if [ $STATSIG_FILES -gt 0 ]; then
        echo -e "${GREEN}✅ Statsig configuration present (${STATSIG_FILES} files)${NC}"
        log_message "SUCCESS: Statsig check - ${STATSIG_FILES} files found"
        ((SUCCESS_COUNT++))
    else
        echo -e "${YELLOW}⚠️  Statsig directory empty${NC}"
        log_message "WARNING: Statsig directory empty"
        ((FAILURE_COUNT++))
    fi
else
    echo -e "${YELLOW}⚠️  Statsig directory missing${NC}"
    log_message "WARNING: Statsig directory not found"
    ((FAILURE_COUNT++))
fi

# Update authentication files timestamps
echo ""
echo "📝 Updating authentication timestamps..."

# Touch the credentials file to update its timestamp
if [ -f "$AUTH_DIR/.credentials.json" ]; then
    # Try to update timestamp
    if touch "$AUTH_DIR/.credentials.json" 2>/dev/null; then
        echo -e "${GREEN}✅ Updated .credentials.json timestamp${NC}"
        log_message "Updated .credentials.json timestamp"
    else
        echo -e "${YELLOW}⚠️  Could not update timestamp (permission denied)${NC}"
        log_message "WARNING: Could not update .credentials.json timestamp - this is OK"
    fi
fi

# Touch statsig files
if [ -d "$AUTH_DIR/statsig" ]; then
    if touch "$AUTH_DIR/statsig"/* 2>/dev/null; then
        echo -e "${GREEN}✅ Updated statsig timestamps${NC}"
        log_message "Updated statsig timestamps"
    else
        echo -e "${YELLOW}⚠️  Could not update statsig timestamps (permission denied)${NC}"
        log_message "WARNING: Could not update statsig timestamps - this is OK"
    fi
fi

# Summary
echo ""
echo "📊 Keep-Alive Summary"
echo "====================="
echo "Successful operations: $SUCCESS_COUNT"
echo "Failed operations: $FAILURE_COUNT"

if [ $FAILURE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All keep-alive operations completed successfully${NC}"
    log_message "Keep-alive check completed successfully ($SUCCESS_COUNT operations)"
    EXIT_CODE=0
elif [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Some operations failed, but authentication appears to be working${NC}"
    log_message "Keep-alive check completed with warnings ($SUCCESS_COUNT successful, $FAILURE_COUNT failed)"
    EXIT_CODE=0
else
    echo -e "${RED}❌ All operations failed - authentication may need to be refreshed${NC}"
    echo ""
    echo "Please run: ./scripts/setup/setup-claude-interactive.sh"
    log_message "Keep-alive check failed - all operations failed"
    EXIT_CODE=1
fi

# Show next steps
echo ""
echo "💡 Next Steps:"
echo "=============="
echo "• Check detailed status: ./scripts/auth/check-claude-max-status.sh"
echo "• View keep-alive log: tail -f $LOG_FILE"
echo ""
echo "• Add to crontab for automatic keep-alive (every 6 hours):"
echo "  crontab -e"
echo "  0 */6 * * * $SCRIPT_DIR/keep-alive-claude-max.sh > /dev/null 2>&1"
echo ""
echo "• Or use systemd timer for more control:"
echo "  See: $PROJECT_ROOT/docs/claude-max-keep-alive.md"

log_message "Keep-alive script finished with exit code $EXIT_CODE"
exit $EXIT_CODE
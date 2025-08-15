#!/bin/bash
set -e

# Script to check the status of Claude Max authentication
# This works with the captured authentication from setup-claude-interactive.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Claude Max Authentication Status Check"
echo "=========================================="
echo ""

# Check if auth directory exists and has files
if [ ! -d "$AUTH_DIR" ]; then
    echo -e "${RED}❌ Authentication directory not found: $AUTH_DIR${NC}"
    echo "   Run ./scripts/setup/setup-claude-interactive.sh first"
    exit 1
fi

# Check if directory has any authentication files
AUTH_FILES=$(ls -A "$AUTH_DIR" 2>/dev/null | wc -l)
if [ "$AUTH_FILES" -eq 0 ]; then
    echo -e "${RED}❌ Authentication directory is empty: $AUTH_DIR${NC}"
    echo "   No authentication files found."
    echo ""
    echo "   To set up authentication:"
    echo "   1. Run: ./scripts/setup/setup-claude-interactive.sh"
    echo "   2. Or copy existing auth: cp -r ~/.claude/* $AUTH_DIR/"
    echo ""
    echo "   Note: You're using Claude Max subscription authentication,"
    echo "   not API keys. This requires interactive setup."
    exit 1
fi

# Check for key authentication files
echo "📁 Checking authentication files..."
echo ""

# Check credentials file
if [ -f "$AUTH_DIR/.credentials.json" ]; then
    FILE_SIZE=$(stat -c%s "$AUTH_DIR/.credentials.json" 2>/dev/null || stat -f%z "$AUTH_DIR/.credentials.json" 2>/dev/null || echo "0")
    FILE_AGE=$(($(date +%s) - $(stat -c %Y "$AUTH_DIR/.credentials.json" 2>/dev/null || stat -f %m "$AUTH_DIR/.credentials.json" 2>/dev/null)))
    FILE_AGE_HOURS=$((FILE_AGE / 3600))
    FILE_AGE_DAYS=$((FILE_AGE / 86400))
    
    echo -e "${GREEN}✅ .credentials.json found${NC}"
    echo "   Size: $FILE_SIZE bytes"
    echo "   Last modified: $FILE_AGE_HOURS hours ago ($FILE_AGE_DAYS days)"
    
    # Check if credentials might be stale (older than 7 days)
    if [ $FILE_AGE_DAYS -gt 7 ]; then
        echo -e "${YELLOW}   ⚠️  Credentials are more than 7 days old - may need refresh${NC}"
    fi
else
    echo -e "${RED}❌ .credentials.json not found${NC}"
fi

# Check session databases
echo ""
echo "📊 Checking session databases..."
DB_FILES=$(find "$AUTH_DIR" -name "*.db" 2>/dev/null)
if [ -n "$DB_FILES" ]; then
    for db in $DB_FILES; do
        DB_NAME=$(basename "$db")
        DB_SIZE=$(du -h "$db" | cut -f1)
        DB_AGE=$(($(date +%s) - $(stat -c %Y "$db" 2>/dev/null || stat -f %m "$db" 2>/dev/null)))
        DB_AGE_MINS=$((DB_AGE / 60))
        
        echo -e "${GREEN}✅ $DB_NAME${NC}"
        echo "   Size: $DB_SIZE"
        echo "   Last modified: $DB_AGE_MINS minutes ago"
    done
else
    echo -e "${YELLOW}⚠️  No database files found${NC}"
fi

# Test authentication with a simple Claude command
echo ""
echo "🧪 Testing authentication..."
echo ""

# Build Docker image if it doesn't exist
if ! docker images | grep -q "claude-setup"; then
    echo "Building claude-setup image..."
    docker build -f "$PROJECT_ROOT/Dockerfile.claude-setup" -t claude-setup:latest "$PROJECT_ROOT" > /dev/null 2>&1
fi

# Test with a simple echo command
echo "Testing Claude CLI with authentication..."

# First check if we're using the main claudecode image
if docker images | grep -q "claudecode:latest"; then
    TEST_OUTPUT=$(docker run --rm \
        -v "$AUTH_DIR:/home/node/.claude:ro" \
        -e CLAUDE_HOME=/home/node/.claude \
        --entrypoint /bin/bash \
        claudecode:latest \
        -c "timeout 15 /usr/local/share/npm-global/bin/claude --print 'Authentication test' 2>&1") || TEST_RESULT=$?
else
    # Fall back to claude-setup image
    TEST_OUTPUT=$(docker run --rm \
        -v "$AUTH_DIR:/home/node/.claude:ro" \
        -e CLAUDE_HOME=/home/node/.claude \
        claude-setup:latest \
        timeout 15 sudo -u node -E env HOME=/home/node PATH=/usr/local/share/npm-global/bin:$PATH \
        /usr/local/share/npm-global/bin/claude --print "Authentication test" 2>&1) || TEST_RESULT=$?
fi

if [ -z "$TEST_RESULT" ] || [ "$TEST_RESULT" -eq 0 ]; then
    if echo "$TEST_OUTPUT" | grep -q "Authentication test"; then
        echo -e "${GREEN}✅ Authentication is working!${NC}"
        echo "   Claude responded successfully"
    elif echo "$TEST_OUTPUT" | grep -i -q "unauthorized\|expired\|invalid.*API.*key\|Please run.*login"; then
        echo -e "${RED}❌ Authentication has expired or is invalid${NC}"
        echo "   Error: $TEST_OUTPUT"
        echo ""
        echo "   Please run: ./scripts/setup/setup-claude-interactive.sh"
    elif echo "$TEST_OUTPUT" | grep -i -q "claude.*--dangerously-skip-permissions"; then
        echo -e "${YELLOW}⚠️  Container using setup script - auth files exist but may need container restart${NC}"
        echo "   Your authentication files are present and fresh."
        echo "   The webhook service should work correctly."
    else
        echo -e "${YELLOW}⚠️  Unclear authentication status${NC}"
        echo "   Output: $TEST_OUTPUT"
    fi
else
    if echo "$TEST_OUTPUT" | grep -i -q "timeout"; then
        echo -e "${YELLOW}⚠️  Command timed out - authentication may be working but slow${NC}"
    else
        echo -e "${RED}❌ Authentication test failed${NC}"
        echo "   Error: $TEST_OUTPUT"
    fi
fi

# Check for active Claude sessions
echo ""
echo "🔄 Checking for active Claude sessions..."
ACTIVE_CONTAINERS=$(docker ps --filter "name=claude-" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" 2>/dev/null | tail -n +2)
if [ -n "$ACTIVE_CONTAINERS" ]; then
    echo -e "${GREEN}Active Claude containers:${NC}"
    echo "$ACTIVE_CONTAINERS"
else
    echo "No active Claude containers running"
fi

# Session statistics
echo ""
echo "📈 Session Statistics:"
echo "========================"

# Count session logs
if [ -d "$PROJECT_ROOT/logs/claude-sessions" ]; then
    SESSION_COUNT=$(ls -1 "$PROJECT_ROOT/logs/claude-sessions"/*.log 2>/dev/null | wc -l)
    if [ $SESSION_COUNT -gt 0 ]; then
        echo "Total sessions logged: $SESSION_COUNT"
        
        # Get recent sessions
        echo ""
        echo "Recent sessions (last 5):"
        ls -lt "$PROJECT_ROOT/logs/claude-sessions"/*.log 2>/dev/null | head -5 | while read -r line; do
            FILE=$(echo "$line" | awk '{print $NF}')
            BASENAME=$(basename "$FILE")
            echo "  - $BASENAME"
        done
    else
        echo "No session logs found"
    fi
else
    echo "Session log directory not found"
fi

# Recommendations
echo ""
echo "💡 Recommendations:"
echo "==================="

if [ $FILE_AGE_DAYS -gt 7 ] 2>/dev/null; then
    echo -e "${YELLOW}• Your authentication is more than 7 days old${NC}"
    echo "  Consider refreshing: ./scripts/auth/refresh-claude-max.sh"
fi

if [ $FILE_AGE_DAYS -gt 14 ] 2>/dev/null; then
    echo -e "${RED}• Your authentication is more than 14 days old${NC}"
    echo "  You should refresh now: ./scripts/setup/setup-claude-interactive.sh"
fi

echo ""
echo "• To keep authentication alive, run periodic health checks:"
echo "  ./scripts/auth/keep-alive-claude-max.sh"
echo ""
echo "• For automatic refresh, add to cron:"
echo "  0 */6 * * * $SCRIPT_DIR/keep-alive-claude-max.sh"

echo ""
echo "✅ Status check complete"
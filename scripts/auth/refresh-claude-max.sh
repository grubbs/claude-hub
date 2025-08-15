#!/bin/bash
set -e

# Script to refresh Claude Max authentication
# This attempts to refresh the session without requiring full re-authentication

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTH_DIR="${CLAUDE_AUTH_HOST_DIR:-${HOME}/.claude-hub}"
BACKUP_DIR="$AUTH_DIR/backups/$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔄 Claude Max Authentication Refresh"
echo "====================================="
echo ""

# Check if auth directory exists
if [ ! -d "$AUTH_DIR" ]; then
    echo -e "${RED}❌ Authentication directory not found: $AUTH_DIR${NC}"
    echo "   Run ./scripts/setup/setup-claude-interactive.sh first"
    exit 1
fi

# Create backup of current authentication
echo "📦 Backing up current authentication..."
mkdir -p "$BACKUP_DIR"
cp -r "$AUTH_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
echo -e "${GREEN}✅ Backup created at: $BACKUP_DIR${NC}"
echo ""

# Build Docker image if needed
if ! docker images | grep -q "claude-setup"; then
    echo "Building claude-setup image..."
    docker build -f "$PROJECT_ROOT/Dockerfile.claude-setup" -t claude-setup:latest "$PROJECT_ROOT" > /dev/null 2>&1
fi

# Function to test current authentication
test_auth() {
    docker run --rm \
        -v "$AUTH_DIR:/home/node/.claude:ro" \
        -e CLAUDE_HOME=/home/node/.claude \
        claude-setup:latest \
        timeout 10 sudo -u node -E env HOME=/home/node PATH=/usr/local/share/npm-global/bin:$PATH \
        /usr/local/share/npm-global/bin/claude --print "test" > /dev/null 2>&1
    return $?
}

# Test current authentication
echo "🧪 Testing current authentication..."
if test_auth; then
    echo -e "${GREEN}✅ Current authentication is working${NC}"
    echo ""
    echo "Attempting to refresh session..."
else
    echo -e "${YELLOW}⚠️  Current authentication may be expired${NC}"
    echo ""
fi

# Attempt to refresh the session
echo "🔄 Attempting session refresh..."
echo ""

# Method 1: Try to use the existing session with a new operation
echo "Method 1: Session activity refresh..."
REFRESH_OUTPUT=$(docker run --rm \
    -v "$AUTH_DIR:/home/node/.claude:rw" \
    -e CLAUDE_HOME=/home/node/.claude \
    claude-setup:latest \
    timeout 30 sudo -u node -E env HOME=/home/node PATH=/usr/local/share/npm-global/bin:$PATH \
    /usr/local/share/npm-global/bin/claude --print "Refresh session" 2>&1) || REFRESH_RESULT=$?

if [ -z "$REFRESH_RESULT" ] || [ "$REFRESH_RESULT" -eq 0 ]; then
    echo -e "${GREEN}✅ Session refreshed successfully${NC}"
    
    # Update file timestamps
    find "$AUTH_DIR" -type f -exec touch {} \;
    echo "   Updated authentication file timestamps"
    
    # Test the refreshed session
    echo ""
    echo "🧪 Verifying refreshed session..."
    if test_auth; then
        echo -e "${GREEN}✅ Authentication verified and working!${NC}"
        echo ""
        echo "Session successfully refreshed. No further action needed."
        exit 0
    else
        echo -e "${YELLOW}⚠️  Verification failed, trying alternative method...${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Simple refresh failed, trying alternative method...${NC}"
fi

# Method 2: Interactive refresh (requires user interaction)
echo ""
echo "Method 2: Interactive refresh..."
echo -e "${BLUE}This method requires your interaction${NC}"
echo ""
echo "Would you like to perform an interactive refresh? (y/n)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Starting interactive refresh..."
    echo "================================"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "1. You will be connected to a Docker container"
    echo "2. Run: claude --dangerously-skip-permissions"
    echo "3. If prompted, log in with your Claude account"
    echo "4. After successful login, type: exit"
    echo ""
    echo "Press Enter to continue..."
    read -r
    
    # Run interactive container
    docker run -it --rm \
        -v "$AUTH_DIR:/home/node/.claude" \
        -e CLAUDE_HOME=/home/node/.claude \
        --entrypoint /bin/bash \
        claude-setup:latest \
        -c "
        echo 'Container started. Running authentication refresh...'
        echo ''
        sudo -u node -E env HOME=/home/node PATH=/usr/local/share/npm-global/bin:$PATH bash
        "
    
    # Test the refreshed authentication
    echo ""
    echo "🧪 Testing refreshed authentication..."
    if test_auth; then
        echo -e "${GREEN}✅ Authentication successfully refreshed!${NC}"
        
        # Clean up backup since refresh was successful
        echo ""
        echo "Cleaning up backup..."
        rm -rf "$BACKUP_DIR"
        echo "Backup removed (authentication successful)"
        
        exit 0
    else
        echo -e "${RED}❌ Authentication test failed${NC}"
        echo ""
        echo "Restore from backup? (y/n)"
        read -r restore_response
        
        if [[ "$restore_response" =~ ^[Yy]$ ]]; then
            echo "Restoring from backup..."
            rm -rf "$AUTH_DIR"/*
            cp -r "$BACKUP_DIR"/* "$AUTH_DIR/"
            echo -e "${GREEN}✅ Restored from backup${NC}"
        fi
        
        exit 1
    fi
else
    echo ""
    echo "Interactive refresh cancelled."
    echo ""
    echo "Alternative options:"
    echo "• Run keep-alive to maintain current session: ./scripts/auth/keep-alive-claude-max.sh"
    echo "• Perform full re-authentication: ./scripts/setup/setup-claude-interactive.sh"
    exit 1
fi
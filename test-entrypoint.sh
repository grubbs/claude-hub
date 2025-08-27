#!/bin/bash
# Test the entrypoint script behavior locally

echo "Testing entrypoint script behavior..."

# Set required environment variables
export REPO_FULL_NAME="test/repo"
export ISSUE_NUMBER="999"
export OPERATION_TYPE="default"
export COMMAND="Test command"
export GITHUB_TOKEN="test_token"
export BOT_USERNAME="TestBot"
export BOT_EMAIL="test@example.com"

# Create a mock Claude command that just outputs something
cat > /tmp/mock-claude.sh << 'EOF'
#!/bin/bash
echo "Mock Claude response"
echo "Tool: Using mock tool"
echo "This is the final response after tool usage"
exit 0
EOF
chmod +x /tmp/mock-claude.sh

# Replace claude command with mock
sed 's|/usr/local/share/npm-global/bin/claude|/tmp/mock-claude.sh|g' \
    scripts/runtime/claudecode-entrypoint-logged.sh > /tmp/test-entrypoint.sh

chmod +x /tmp/test-entrypoint.sh

echo "Running test entrypoint..."
timeout 10s bash /tmp/test-entrypoint.sh

EXIT_CODE=$?
if [ $EXIT_CODE -eq 124 ]; then
    echo "ERROR: Script timed out after 10 seconds!"
    echo "The script is hanging somewhere"
else
    echo "Script completed with exit code: $EXIT_CODE"
fi

echo "Checking for output between markers..."
bash /tmp/test-entrypoint.sh 2>/dev/null | sed -n '/__CLAUDE_RESPONSE_START__/,/__CLAUDE_RESPONSE_END__/p'
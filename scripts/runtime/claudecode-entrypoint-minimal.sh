#!/bin/bash
# MINIMAL entrypoint script - just the essentials

# Simple logging
echo "[$(date)] Starting minimal entrypoint" >&2

# Output markers with response
echo "__CLAUDE_RESPONSE_START__"
echo "This is a test response - minimal script working"
echo "__CLAUDE_RESPONSE_END__"

echo "[$(date)] Completed minimal entrypoint" >&2

# Explicit exit
exit 0
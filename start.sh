#!/bin/bash
# Simple start script that keeps everything running

cd /home/daniel/claude-hub

# Function to check if webhook is healthy
check_health() {
    curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/health
}

# Start webhook container
echo "Starting webhook container..."
docker compose up -d

# Wait for it to be healthy
sleep 10

# Check if healthy
if [ "$(check_health)" = "200" ]; then
    echo "✓ Webhook is running"
else
    echo "⚠ Webhook may need attention"
fi

# Keep ngrok or cloudflared running
echo "Starting tunnel..."
while true; do
    # Use ngrok if available, otherwise cloudflared
    if command -v ngrok &> /dev/null; then
        echo "Using ngrok..."
        ngrok http 3002
    else
        echo "Using cloudflared..."
        cloudflared tunnel --url http://localhost:3002
    fi
    
    echo "Tunnel disconnected, restarting in 5 seconds..."
    sleep 5
done
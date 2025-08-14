# Claude Max Authentication Keep-Alive Guide

This guide explains how to maintain your Claude Max authentication session to prevent timeouts and avoid frequent re-authentication.

## Overview

Claude Max authentication (using your subscription instead of API keys) can expire after periods of inactivity. The keep-alive scripts help maintain your session by:

1. **Monitoring** authentication status
2. **Performing** periodic operations to maintain activity
3. **Refreshing** sessions when needed
4. **Automating** the keep-alive process

## Available Scripts

### 1. Check Authentication Status

```bash
./scripts/auth/check-claude-max-status.sh
```

**What it does:**
- Checks if authentication files exist
- Verifies file age and warns if stale
- Tests authentication with a simple Claude command
- Shows active Claude containers
- Provides session statistics

**When to use:**
- To verify your authentication is working
- Before running important tasks
- When troubleshooting authentication issues

### 2. Keep Authentication Alive

```bash
./scripts/auth/keep-alive-claude-max.sh
```

**What it does:**
- Performs lightweight Claude operations to maintain activity
- Updates authentication file timestamps
- Logs all operations for monitoring
- Returns success/failure status

**When to use:**
- Regularly (every 6-12 hours) to prevent session timeout
- After periods of inactivity
- As part of automated maintenance

### 3. Refresh Authentication

```bash
./scripts/auth/refresh-claude-max.sh
```

**What it does:**
- Backs up current authentication
- Attempts automatic session refresh
- Provides interactive refresh option if needed
- Can restore from backup if refresh fails

**When to use:**
- When authentication has expired
- When keep-alive operations start failing
- Before the 14-day expiration mark

## Setting Up Automated Keep-Alive

### Method 1: Using Cron (Recommended)

Add to your crontab to run every 6 hours:

```bash
# Edit crontab
crontab -e

# Add this line (adjust path as needed)
0 */6 * * * /home/daniel/claude-hub/scripts/auth/keep-alive-claude-max.sh >> /home/daniel/claude-hub/logs/claude-keep-alive-cron.log 2>&1
```

### Method 2: Using Systemd Timer

Create a systemd service:

```bash
# Create service file
sudo nano /etc/systemd/system/claude-keep-alive.service
```

```ini
[Unit]
Description=Claude Max Authentication Keep-Alive
After=network.target

[Service]
Type=oneshot
User=daniel
WorkingDirectory=/home/daniel/claude-hub
ExecStart=/home/daniel/claude-hub/scripts/auth/keep-alive-claude-max.sh
StandardOutput=append:/home/daniel/claude-hub/logs/claude-keep-alive.log
StandardError=append:/home/daniel/claude-hub/logs/claude-keep-alive.log

[Install]
WantedBy=multi-user.target
```

Create timer file:

```bash
sudo nano /etc/systemd/system/claude-keep-alive.timer
```

```ini
[Unit]
Description=Run Claude Keep-Alive every 6 hours
Requires=claude-keep-alive.service

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable claude-keep-alive.timer
sudo systemctl start claude-keep-alive.timer

# Check status
sudo systemctl status claude-keep-alive.timer
sudo systemctl list-timers | grep claude
```

### Method 3: Using Docker Compose

Add a keep-alive service to your `docker-compose.yml`:

```yaml
services:
  claude-keep-alive:
    image: claude-setup:latest
    volumes:
      - ${CLAUDE_AUTH_HOST_DIR:-~/.claude-hub}:/home/node/.claude
      - ./logs:/logs
    environment:
      - CLAUDE_HOME=/home/node/.claude
    command: |
      sh -c "while true; do
        /scripts/auth/keep-alive-claude-max.sh
        sleep 21600  # 6 hours
      done"
    restart: unless-stopped
```

## Monitoring Authentication Health

### View Keep-Alive Logs

```bash
# Real-time monitoring
tail -f logs/claude-keep-alive.log

# Check recent activity
grep "SUCCESS\|FAILED" logs/claude-keep-alive.log | tail -20

# Count successes and failures
echo "Successes: $(grep -c SUCCESS logs/claude-keep-alive.log)"
echo "Failures: $(grep -c FAILED logs/claude-keep-alive.log)"
```

### Set Up Alerts

Create a monitoring script:

```bash
#!/bin/bash
# scripts/auth/monitor-claude-auth.sh

AUTH_STATUS=$(./scripts/auth/check-claude-max-status.sh 2>&1)

if echo "$AUTH_STATUS" | grep -q "Authentication has expired"; then
    # Send alert (example using mail)
    echo "Claude authentication expired!" | mail -s "Claude Auth Alert" your-email@example.com
    
    # Or send to Slack webhook
    curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"⚠️ Claude authentication has expired and needs renewal"}' \
        YOUR_SLACK_WEBHOOK_URL
fi
```

## Best Practices

### 1. Regular Monitoring
- Check status daily: `./scripts/auth/check-claude-max-status.sh`
- Review keep-alive logs weekly
- Set up automated alerts for failures

### 2. Proactive Maintenance
- Run keep-alive every 6-12 hours
- Refresh authentication weekly (before it gets stale)
- Keep backups of working authentication

### 3. Backup Strategy
```bash
# Manual backup
cp -r ~/.claude-hub ~/.claude-hub.backup.$(date +%Y%m%d)

# Automated daily backup (add to cron)
0 3 * * * tar -czf ~/backups/claude-auth-$(date +\%Y\%m\%d).tar.gz ~/.claude-hub
```

### 4. Recovery Plan
If authentication fails:
1. Try keep-alive first: `./scripts/auth/keep-alive-claude-max.sh`
2. If that fails, try refresh: `./scripts/auth/refresh-claude-max.sh`
3. If both fail, re-authenticate: `./scripts/setup/setup-claude-interactive.sh`
4. Restore from backup if available

## Troubleshooting

### Authentication Suddenly Stops Working

1. **Check file permissions:**
   ```bash
   ls -la ~/.claude-hub/
   # Files should be readable by your user
   ```

2. **Check Docker volumes:**
   ```bash
   docker run --rm -v ~/.claude-hub:/test alpine ls -la /test
   ```

3. **Verify environment variables:**
   ```bash
   echo $CLAUDE_AUTH_HOST_DIR
   grep CLAUDE_AUTH docker-compose.yml
   ```

### Keep-Alive Fails Consistently

1. **Check logs for specific errors:**
   ```bash
   grep ERROR logs/claude-keep-alive.log | tail -10
   ```

2. **Test authentication manually:**
   ```bash
   docker run -it --rm \
     -v ~/.claude-hub:/home/node/.claude \
     claude-setup:latest \
     sudo -u node claude --print "test"
   ```

3. **Verify network connectivity:**
   ```bash
   docker run --rm claude-setup:latest ping -c 3 api.anthropic.com
   ```

### Sessions Expire Too Quickly

- Increase keep-alive frequency (every 3-4 hours)
- Check for time sync issues: `timedatectl status`
- Ensure consistent use of the same authentication directory

## Session Lifetime Expectations

Based on community observations:

- **Active use**: Sessions can last 30+ days with regular activity
- **With keep-alive**: 14-21 days typical
- **Without keep-alive**: 7-14 days before requiring refresh
- **Complete inactivity**: May expire in 3-7 days

## Advanced Configuration

### Custom Keep-Alive Commands

Edit `keep-alive-claude-max.sh` to add custom operations:

```bash
# Add your own keep-alive operations
perform_keep_alive "Custom operation" "Your specific command here"
```

### Adjust Timeouts

Modify timeouts in the scripts:

```bash
# In keep-alive script
timeout 20  # Increase to 30 or 60 for slower connections
```

### Multiple Authentication Directories

Support multiple Claude accounts:

```bash
# For personal account
CLAUDE_AUTH_HOST_DIR=~/.claude-personal ./scripts/auth/keep-alive-claude-max.sh

# For work account  
CLAUDE_AUTH_HOST_DIR=~/.claude-work ./scripts/auth/keep-alive-claude-max.sh
```

## Integration with CI/CD

For GitHub Actions:

```yaml
name: Claude Keep-Alive
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:  # Manual trigger

jobs:
  keep-alive:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Run keep-alive
        run: |
          ./scripts/auth/keep-alive-claude-max.sh
        env:
          CLAUDE_AUTH_HOST_DIR: ${{ secrets.CLAUDE_AUTH_DIR }}
```

## Summary

The keep-alive system helps maintain your Claude Max authentication without requiring frequent manual re-authentication. By automating the keep-alive process, you can ensure your webhook service remains operational and responsive.

Key points:
- Run keep-alive every 6-12 hours
- Monitor logs for issues
- Refresh before 14 days
- Keep backups of working authentication
- Set up alerts for failures
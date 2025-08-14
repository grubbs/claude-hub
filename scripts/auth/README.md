# Claude Max Authentication Scripts

These scripts help manage Claude Max subscription authentication (not API keys).

## Current Status

Your authentication directory (`~/.claude-hub`) contains:
- ✅ `.credentials.json` - Authentication token file
- ✅ `statsig/` directory - Feature flags and configuration
- ✅ `shell-snapshots/` - Session snapshots

## Available Scripts

### 1. `check-claude-max-status.sh`
Checks the current status of your Claude Max authentication.

**Usage:**
```bash
./scripts/auth/check-claude-max-status.sh
```

**What it reports:**
- Authentication file existence and age
- Session database status
- Active Claude containers
- Recent session logs
- Recommendations for maintenance

### 2. `keep-alive-claude-max.sh`
Performs periodic operations to keep your authentication session active.

**Usage:**
```bash
./scripts/auth/keep-alive-claude-max.sh
```

**What it does:**
- Runs test commands through Claude
- Updates authentication file timestamps
- Logs all operations for monitoring

**Note:** Currently requires writable auth directory. May need adjustment based on your setup.

### 3. `refresh-claude-max.sh`
Attempts to refresh an expired authentication session.

**Usage:**
```bash
./scripts/auth/refresh-claude-max.sh
```

**What it does:**
- Backs up current authentication
- Attempts automatic refresh
- Provides interactive refresh option
- Can restore from backup if needed

## Common Issues & Solutions

### Issue: "Authentication directory is empty"
**Solution:** Run initial setup:
```bash
./scripts/setup/setup-claude-interactive.sh
```

### Issue: "Unclear authentication status"
**Cause:** Claude is prompting for interactive setup, indicating:
- Authentication may be expired (>14 days old)
- Token needs refresh
- First-time setup needed

**Solution:**
1. Try keep-alive first: `./scripts/auth/keep-alive-claude-max.sh`
2. If that fails, refresh: `./scripts/auth/refresh-claude-max.sh`
3. Last resort, re-authenticate: `./scripts/setup/setup-claude-interactive.sh`

### Issue: Keep-alive operations timeout
**Cause:** Authentication is expired or network issues

**Solution:**
1. Check network: `ping api.anthropic.com`
2. Refresh authentication: `./scripts/auth/refresh-claude-max.sh`

## Automation Setup

### Using Cron
Add to crontab (`crontab -e`):
```bash
# Run keep-alive every 6 hours
0 */6 * * * /path/to/claude-hub/scripts/auth/keep-alive-claude-max.sh >> /path/to/logs/keep-alive.log 2>&1

# Check status daily at 9 AM
0 9 * * * /path/to/claude-hub/scripts/auth/check-claude-max-status.sh >> /path/to/logs/status.log 2>&1
```

### Using systemd
See `/docs/claude-max-keep-alive.md` for systemd timer setup.

## Authentication Lifespan

Based on testing:
- **With keep-alive**: 14-21 days typical
- **Without keep-alive**: 7-14 days
- **Complete inactivity**: 3-7 days

Your current authentication:
- Created: ~18 hours ago
- Status: May need interactive refresh
- Recommendation: Run `./scripts/setup/setup-claude-interactive.sh` if keep-alive fails

## Environment Variables

The scripts use:
```bash
CLAUDE_AUTH_HOST_DIR=${HOME}/.claude-hub  # Authentication directory location
```

To use a different auth directory:
```bash
CLAUDE_AUTH_HOST_DIR=/custom/path ./scripts/auth/check-claude-max-status.sh
```

## Debugging

Enable verbose output:
```bash
bash -x ./scripts/auth/check-claude-max-status.sh
```

Check Docker mount:
```bash
docker run --rm -v ~/.claude-hub:/test alpine ls -la /test/
```

Test Claude directly:
```bash
docker run --rm \
  -v ~/.claude-hub:/workspace/.claude \
  -e HOME=/workspace \
  -e CLAUDE_HOME=/workspace/.claude \
  --entrypoint /bin/bash \
  claudecode:latest \
  -c "cd /workspace && /usr/local/share/npm-global/bin/claude --version"
```

## Next Steps

1. If authentication is expired, run: `./scripts/setup/setup-claude-interactive.sh`
2. Set up cron job for automatic keep-alive
3. Monitor logs regularly: `tail -f logs/claude-keep-alive.log`
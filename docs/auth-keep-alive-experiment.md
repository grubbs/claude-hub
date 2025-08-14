# Claude Max Authentication Keep-Alive Experiment

## Hypothesis
The keep-alive script will extend Claude Max authentication lifetime by maintaining session activity, preventing timeout from inactivity.

## Experiment Design

### Control Group (Baseline)
**Setup:** No keep-alive script running
**Duration:** 14 days
**Monitoring:** Every 6 hours

### Test Group A (Frequent Keep-Alive)
**Setup:** Keep-alive script runs every 6 hours
**Duration:** 14 days
**Monitoring:** Every 6 hours

### Test Group B (Daily Keep-Alive)
**Setup:** Keep-alive script runs once daily
**Duration:** 14 days
**Monitoring:** Every 6 hours

## Methodology

### Phase 1: Baseline Measurement (Days 1-3)
1. Fresh authentication on Day 0
2. Monitor without any keep-alive
3. Record when auth stops working
4. Document natural session lifetime

### Phase 2: Keep-Alive Testing (Days 4-14)
1. Re-authenticate on Day 4
2. Enable keep-alive schedule
3. Monitor auth status continuously
4. Track session persistence

### Phase 3: Stress Test (Days 15-21)
1. Gradually reduce keep-alive frequency
2. Find minimum viable frequency
3. Test recovery from expired sessions

## Metrics to Track

### Primary Metrics
- **Session Lifetime**: Hours until auth fails
- **Keep-Alive Effectiveness**: Does running script extend lifetime?
- **Optimal Frequency**: Minimum frequency needed

### Secondary Metrics
- File timestamp changes
- Statsig directory updates
- Docker container behavior
- Network connectivity impact

## Data Collection

### Automated Monitoring
```bash
# Add to crontab for hourly monitoring
0 * * * * /home/daniel/claude-hub/scripts/auth/monitor-auth-lifetime.sh monitor
```

### Manual Checkpoints
- Daily manual verification
- Screenshot auth status
- Note any unusual behavior

## Implementation Steps

### Step 1: Start Baseline (No Keep-Alive)
```bash
# Remove any existing keep-alive cron jobs
crontab -l | grep -v keep-alive-claude-max > /tmp/crontab.tmp
crontab /tmp/crontab.tmp

# Start monitoring
./scripts/auth/monitor-auth-lifetime.sh continuous &
MONITOR_PID=$!
echo $MONITOR_PID > /tmp/auth-monitor.pid

# Check initial status
./scripts/auth/check-claude-max-status.sh
```

### Step 2: Enable Keep-Alive (After Baseline)
```bash
# Add keep-alive to cron (6-hour interval)
(crontab -l 2>/dev/null; echo "0 */6 * * * /home/daniel/claude-hub/scripts/auth/keep-alive-claude-max.sh >> /home/daniel/claude-hub/logs/keep-alive-cron.log 2>&1") | crontab -

# Verify it's scheduled
crontab -l | grep keep-alive
```

### Step 3: Collect Data
```bash
# View real-time monitoring
tail -f logs/auth-status-monitor.log

# Generate report
./scripts/auth/monitor-auth-lifetime.sh report

# Create visualization (if matplotlib installed)
./scripts/auth/monitor-auth-lifetime.sh graph
```

## Expected Results

### Without Keep-Alive
- Session expires in 7-14 days
- Auth files remain but become invalid
- Docker commands fail with "unauthorized"

### With Keep-Alive (6-hour)
- Session should last 14-21+ days
- Regular activity prevents timeout
- Graceful degradation if missed runs

### With Keep-Alive (24-hour)
- Session might last 10-14 days
- Higher risk of timeout
- May need manual refresh

## Analysis Plan

### Statistical Analysis
1. Calculate mean session lifetime for each group
2. Perform t-test for significance
3. Determine correlation between frequency and lifetime

### Visualization
```python
# Generate comparison charts
import pandas as pd
import matplotlib.pyplot as plt

# Load CSV data
df = pd.read_csv('logs/auth-lifetime-monitor.csv')

# Plot lifetime curves
plt.figure(figsize=(12, 6))
plt.plot(df['timestamp'], df['auth_age_hours'])
plt.axhline(y=168, color='y', linestyle='--', label='7 days')
plt.axhline(y=336, color='r', linestyle='--', label='14 days')
plt.xlabel('Time')
plt.ylabel('Auth Age (hours)')
plt.title('Authentication Lifetime with Keep-Alive')
plt.legend()
plt.show()
```

## Quick Start Experiment

### Option A: Accelerated Test (3 days)
```bash
# Day 1: Baseline (no keep-alive)
./scripts/auth/monitor-auth-lifetime.sh continuous &

# Day 2: Enable aggressive keep-alive (every hour)
(crontab -l; echo "0 * * * * /home/daniel/claude-hub/scripts/auth/keep-alive-claude-max.sh") | crontab -

# Day 3: Analyze results
./scripts/auth/monitor-auth-lifetime.sh report
```

### Option B: Real-World Test (2 weeks)
```bash
# Week 1: Control (no intervention)
# Just monitor natural decay

# Week 2: Test (with keep-alive)
# Enable 6-hour keep-alive and compare
```

## Troubleshooting

### If Auth Expires During Test
1. Note exact time of expiration
2. Save all logs before re-auth
3. Run: `./scripts/setup/setup-claude-interactive.sh`
4. Resume experiment with new session

### If Keep-Alive Fails
1. Check cron logs: `grep CRON /var/log/syslog`
2. Verify script permissions
3. Test manually: `./scripts/auth/keep-alive-claude-max.sh`

## Success Criteria

The experiment is successful if:
1. **Measurable Extension**: Keep-alive extends session by >50%
2. **Predictable Behavior**: Can predict when refresh needed
3. **Automation Works**: Cron job runs reliably
4. **Recovery Possible**: Can detect and recover from expiry

## Next Steps After Experiment

Based on results:
1. **If Successful**: Document optimal schedule, deploy permanently
2. **If Partial**: Adjust frequency, test other approaches
3. **If Failed**: Investigate alternative methods (API keys, different auth)

## Current Status

- Authentication Age: ~18 hours
- Keep-Alive Script: Tested and working
- Monitoring Script: Created and ready
- Experiment Status: Ready to begin

To start the experiment now:
```bash
# Begin monitoring
./scripts/auth/monitor-auth-lifetime.sh monitor

# Check current status
./scripts/auth/check-claude-max-status.sh

# View initial data
cat logs/auth-lifetime-monitor.csv
```
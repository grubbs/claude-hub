# Fork Configuration Guide

This guide helps you configure your personal fork of claude-hub to use your own GitHub account and settings instead of the default "cheffromspace" references.

## Overview

The original repository includes some hardcoded default values for the original author. This guide shows you how to properly configure your fork with your own settings.

## Configuration Steps

### 1. Update Your .env File

Add these essential environment variables to your `.env` file:

```bash
# Your GitHub username (replaces all "cheffromspace" references)
DEFAULT_GITHUB_OWNER=your-github-username
DEFAULT_GITHUB_USER=your-github-username
DEFAULT_GITHUB_REPO=claude-hub

# Authorization (add your username to the list)
AUTHORIZED_USERS=your-github-username,your-bot-username
DEFAULT_AUTHORIZED_USER=your-github-username

# Bot configuration
BOT_USERNAME=YourBotName
BOT_EMAIL=bot@example.com
```

### 2. GitHub Repository Variables (Optional)

If you plan to use GitHub Actions to publish Docker images, set these repository variables:

1. Go to: Settings → Secrets and variables → Actions → Variables
2. Add:
   - `DOCKER_HUB_USERNAME`: Your Docker Hub username
   - `DOCKER_HUB_ORGANIZATION`: Your Docker Hub organization (or username)
   - `DOCKER_IMAGE_NAME`: Your preferred image name (default: claude-hub)

### 3. Where These Are Used

Your configuration replaces hardcoded defaults in:

| Location | Purpose | Configurable Via |
|----------|---------|------------------|
| `docker-compose.yml` | Default fallback values | Environment variables |
| `.github/workflows/docker-publish.yml` | Docker Hub publishing | Repository variables |
| API endpoints | Default repository for Slack commands | Environment variables |
| CLI tools | Default owner/user for commands | Environment variables |

## Quick Setup Script

Run this to create a personalized configuration:

```bash
#!/bin/bash
# Replace YOUR_GITHUB_USERNAME with your actual GitHub username

cat >> .env << EOF

# Personal Fork Configuration
DEFAULT_GITHUB_OWNER=YOUR_GITHUB_USERNAME
DEFAULT_GITHUB_USER=YOUR_GITHUB_USERNAME
DEFAULT_GITHUB_REPO=claude-hub
AUTHORIZED_USERS=YOUR_GITHUB_USERNAME,YOUR_BOT_USERNAME
DEFAULT_AUTHORIZED_USER=YOUR_GITHUB_USERNAME
EOF

echo "✅ Configuration added to .env"
echo "📝 Remember to update YOUR_GITHUB_USERNAME and YOUR_BOT_USERNAME"
```

## Docker Compose Behavior

The `docker-compose.yml` file uses this pattern:
```yaml
DEFAULT_GITHUB_OWNER=${DEFAULT_GITHUB_OWNER:-Cheffromspace}
```

This means:
1. First, it checks your `.env` file for `DEFAULT_GITHUB_OWNER`
2. If not found, it falls back to "Cheffromspace"
3. With your `.env` configured, your values take precedence

## Testing Your Configuration

After setting up your environment variables:

1. **Check configuration:**
   ```bash
   docker compose config | grep -E "DEFAULT_GITHUB|AUTHORIZED_USERS"
   ```

2. **Verify your values are being used:**
   ```bash
   docker compose run --rm webhook env | grep -E "DEFAULT_GITHUB|AUTHORIZED"
   ```

3. **Test with a webhook:**
   Create an issue mentioning your bot:
   ```
   @YourBotName help me understand this repository
   ```

## Troubleshooting

### Still Seeing "cheffromspace"?

1. **Check your .env file:**
   ```bash
   grep DEFAULT_GITHUB .env
   ```

2. **Restart services:**
   ```bash
   docker compose down
   docker compose up -d
   ```

3. **Check for typos:**
   Variable names are case-sensitive. Use exactly:
   - `DEFAULT_GITHUB_OWNER`
   - `DEFAULT_GITHUB_USER`
   - `AUTHORIZED_USERS`

### Docker Hub Publishing Issues

If GitHub Actions fails to publish Docker images:

1. The workflow uses repository variables (not secrets) for usernames
2. Set them at: Settings → Secrets and variables → Actions → Variables
3. The fallback to "cheffromspace" only applies if variables aren't set

## Clean Slate Setup

For a completely clean configuration:

```bash
# 1. Copy the example environment file
cp .env.example .env

# 2. Edit with your values
nano .env

# 3. Remove any old container images
docker compose down --rmi local

# 4. Rebuild with your configuration
docker compose build
docker compose up -d
```

## Summary

With these environment variables properly set, your fork will:
- Use your GitHub username instead of "cheffromspace"
- Authorize you and your bot to use the webhook
- Default to your repositories for Slack commands
- Publish Docker images to your Docker Hub account (if configured)

No code changes are required - everything is configurable through environment variables!
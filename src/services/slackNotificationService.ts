import { WebClient } from '@slack/web-api';
import { createLogger } from '../utils/logger';

interface TaskContext {
  repoFullName: string;
  issueNumber?: number;
  pullRequestNumber?: number;
  type: 'issue_comment' | 'pull_request_comment' | 'pr_review' | 'auto_tag' | 'check_suite';
  user: string;
  command: string;
  startTime: number;
  branchName?: string | null;
}

interface TaskResult {
  success: boolean;
  responsePreview?: string;
  githubUrl: string;
  duration?: number;
  error?: Error;
}

interface SlackBlock {
  type: string;
  text?: {
    type: string;
    text: string;
    emoji?: boolean;
  };
  fields?: Array<{
    type: string;
    text: string;
  }>;
  elements?: Array<{
    type: string;
    text?: string;
    url?: string;
  }>;
}

export class SlackNotificationService {
  private client: WebClient | null = null;
  private channelId: string;
  private logger = createLogger('SlackNotification');
  private enabled: boolean;
  private notifyOnSuccess: boolean;
  private notifyOnError: boolean;
  private minDurationMs: number;

  constructor() {
    this.enabled = process.env.SLACK_NOTIFICATION_ENABLED === 'true';
    this.notifyOnSuccess = process.env.SLACK_NOTIFY_ON_SUCCESS !== 'false'; // Default true
    this.notifyOnError = process.env.SLACK_NOTIFY_ON_ERROR !== 'false'; // Default true
    this.minDurationMs = parseInt(process.env.SLACK_NOTIFY_MIN_DURATION_MS ?? '5000', 10);
    
    if (this.enabled && process.env.SLACK_BOT_TOKEN) {
      this.client = new WebClient(process.env.SLACK_BOT_TOKEN);
      this.channelId = process.env.SLACK_CHANNEL_ID ?? 'claude-bot-actions';
      this.logger.info('Slack notification service initialized', {
        channelId: this.channelId,
        notifyOnSuccess: this.notifyOnSuccess,
        notifyOnError: this.notifyOnError,
        minDurationMs: this.minDurationMs
      });
    } else {
      this.channelId = '';
      this.logger.info('Slack notification service disabled');
    }
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      const remainingMinutes = minutes % 60;
      return `${hours}h ${remainingMinutes}m`;
    } else if (minutes > 0) {
      const remainingSeconds = seconds % 60;
      return `${minutes}m ${remainingSeconds}s`;
    } else {
      return `${seconds}s`;
    }
  }

  private getOperationTypeDisplay(type: string): string {
    const typeMap: Record<string, string> = {
      'issue_comment': 'Issue Comment',
      'pull_request_comment': 'PR Comment',
      'pr_review': 'PR Review',
      'auto_tag': 'Auto-Tagging',
      'check_suite': 'Check Suite'
    };
    return typeMap[type] || type;
  }

  private formatSuccessMessage(context: TaskContext, result: TaskResult): { blocks: SlackBlock[]; fallbackText: string } {
    const duration = result.duration ?? (Date.now() - context.startTime);
    const durationStr = this.formatDuration(duration);
    
    const issueOrPr = context.pullRequestNumber ? 
      `PR #${context.pullRequestNumber}` : 
      `Issue #${context.issueNumber}`;

    const blocks: SlackBlock[] = [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: '✅ Claude Task Completed',
          emoji: true
        }
      },
      {
        type: 'section',
        fields: [
          {
            type: 'mrkdwn',
            text: `*Repository:*\n${context.repoFullName}`
          },
          {
            type: 'mrkdwn',
            text: `*${context.pullRequestNumber ? 'Pull Request' : 'Issue'}:*\n<${result.githubUrl}|${issueOrPr}>`
          },
          {
            type: 'mrkdwn',
            text: `*Type:*\n${this.getOperationTypeDisplay(context.type)}`
          },
          {
            type: 'mrkdwn',
            text: `*Duration:*\n${durationStr}`
          },
          {
            type: 'mrkdwn',
            text: `*Triggered by:*\n@${context.user}`
          },
          {
            type: 'mrkdwn',
            text: `*Command:*\n${context.command.substring(0, 100)}${context.command.length > 100 ? '...' : ''}`
          }
        ]
      }
    ];

    if (result.responsePreview) {
      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Response Preview:*\n\`\`\`${result.responsePreview.substring(0, 500)}${result.responsePreview.length > 500 ? '...' : ''}\`\`\``
        }
      });
    }

    blocks.push({
      type: 'context',
      elements: [
        {
          type: 'mrkdwn',
          text: `Container: claudecode:latest | Completed at ${new Date().toISOString()}`
        }
      ]
    });

    const fallbackText = `✅ Claude completed ${issueOrPr} in ${context.repoFullName} (${durationStr})`;

    return { blocks, fallbackText };
  }

  private formatErrorMessage(context: TaskContext, error: Error): { blocks: SlackBlock[]; fallbackText: string } {
    const duration = Date.now() - context.startTime;
    const durationStr = this.formatDuration(duration);
    
    const issueOrPr = context.pullRequestNumber ? 
      `PR #${context.pullRequestNumber}` : 
      context.issueNumber ? `Issue #${context.issueNumber}` : 'N/A';

    const githubUrl = context.pullRequestNumber ?
      `https://github.com/${context.repoFullName}/pull/${context.pullRequestNumber}` :
      context.issueNumber ?
      `https://github.com/${context.repoFullName}/issues/${context.issueNumber}` :
      `https://github.com/${context.repoFullName}`;

    const errorId = `err-${Date.now().toString(36)}`;

    const blocks: SlackBlock[] = [
      {
        type: 'header',
        text: {
          type: 'plain_text',
          text: '❌ Claude Task Failed',
          emoji: true
        }
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Error:* ${error.message}`
        }
      },
      {
        type: 'section',
        fields: [
          {
            type: 'mrkdwn',
            text: `*Repository:*\n${context.repoFullName}`
          },
          {
            type: 'mrkdwn',
            text: `*${context.pullRequestNumber ? 'Pull Request' : 'Issue'}:*\n<${githubUrl}|${issueOrPr}>`
          },
          {
            type: 'mrkdwn',
            text: `*Type:*\n${this.getOperationTypeDisplay(context.type)}`
          },
          {
            type: 'mrkdwn',
            text: `*Duration before failure:*\n${durationStr}`
          },
          {
            type: 'mrkdwn',
            text: `*Triggered by:*\n@${context.user}`
          },
          {
            type: 'mrkdwn',
            text: `*Error ID:*\n${errorId}`
          }
        ]
      }
    ];

    if (context.command) {
      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Command:*\n\`\`\`${context.command.substring(0, 200)}${context.command.length > 200 ? '...' : ''}\`\`\``
        }
      });
    }

    if (error.stack) {
      const stackPreview = error.stack.split('\n').slice(0, 5).join('\n');
      blocks.push({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: `*Stack Trace:*\n\`\`\`${stackPreview}\`\`\``
        }
      });
    }

    blocks.push({
      type: 'context',
      elements: [
        {
          type: 'mrkdwn',
          text: `Container: claudecode:latest | Failed at ${new Date().toISOString()} | Error ID: ${errorId}`
        }
      ]
    });

    const fallbackText = `❌ Claude failed processing ${issueOrPr} in ${context.repoFullName}: ${error.message}`;

    return { blocks, fallbackText };
  }

  async notifyTaskComplete(context: TaskContext, result: TaskResult): Promise<void> {
    if (!this.client || !this.enabled || !this.notifyOnSuccess) {
      return;
    }

    const duration = result.duration ?? (Date.now() - context.startTime);
    
    // Skip notifications for very quick operations unless they're errors
    if (!result.error && duration < this.minDurationMs) {
      this.logger.debug('Skipping notification for quick operation', {
        duration,
        minDurationMs: this.minDurationMs
      });
      return;
    }

    try {
      const message = this.formatSuccessMessage(context, result);
      
      const response = await this.client.chat.postMessage({
        channel: this.channelId,
        blocks: message.blocks as unknown[],
        text: message.fallbackText
      });

      this.logger.info('Slack notification sent successfully', {
        context,
        messageTs: response.ts,
        channel: response.channel
      });
    } catch (error) {
      this.logger.error('Failed to send Slack notification', { 
        error, 
        context,
        channelId: this.channelId 
      });
      // Don't throw - notifications should not break the main flow
    }
  }

  async notifyTaskError(context: TaskContext, error: Error): Promise<void> {
    if (!this.client || !this.enabled || !this.notifyOnError) {
      return;
    }

    try {
      const message = this.formatErrorMessage(context, error);
      
      const response = await this.client.chat.postMessage({
        channel: this.channelId,
        blocks: message.blocks as unknown[],
        text: message.fallbackText
      });

      this.logger.info('Slack error notification sent', {
        context,
        messageTs: response.ts,
        channel: response.channel,
        error: error.message
      });
    } catch (slackError) {
      this.logger.error('Failed to send Slack error notification', { 
        slackError, 
        originalError: error,
        context,
        channelId: this.channelId 
      });
      // Don't throw - notifications should not break the main flow
    }
  }

  async notifyTaskStart(context: TaskContext): Promise<void> {
    if (!this.client || !this.enabled) {
      return;
    }

    const notifyOnStart = process.env.SLACK_NOTIFY_ON_START === 'true';
    if (!notifyOnStart) {
      return;
    }

    try {
      const issueOrPr = context.pullRequestNumber ? 
        `PR #${context.pullRequestNumber}` : 
        `Issue #${context.issueNumber}`;

      const blocks: SlackBlock[] = [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `⏳ *Claude is starting to process ${issueOrPr} in ${context.repoFullName}*\n_Command: ${context.command.substring(0, 100)}${context.command.length > 100 ? '...' : ''}_`
          }
        }
      ];

      await this.client.chat.postMessage({
        channel: this.channelId,
        blocks: blocks as unknown[],
        text: `⏳ Claude is processing ${issueOrPr} in ${context.repoFullName}`
      });

      this.logger.debug('Task start notification sent', { context });
    } catch (error) {
      this.logger.error('Failed to send task start notification', { error, context });
      // Don't throw - notifications should not break the main flow
    }
  }

  isEnabled(): boolean {
    return this.enabled && this.client !== null;
  }
}

// Export singleton instance
export const slackNotificationService = new SlackNotificationService();
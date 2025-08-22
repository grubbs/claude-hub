import type { WebhookContext, WebhookHandlerResponse } from '../../../types/webhook';
import type { SlackWebhookPayload } from '../SlackWebhookProvider';
import { createLogger } from '../../../utils/logger';
import { processCommand } from '../../../services/claudeService';
import axios from 'axios';

const logger = createLogger('TestHandler');

/**
 * Handler for /test Slack command
 * General purpose testing and webhook acknowledgment
 */
export class TestHandler {
  name = 'test_handler';

  /**
   * Check if this handler can process the event
   */
  canHandle(payload: SlackWebhookPayload): boolean {
    return payload.data.command === '/test';
  }

  /**
   * Handle the /test command
   */
  async handle(
    payload: SlackWebhookPayload,
    _context: WebhookContext
  ): Promise<WebhookHandlerResponse> {
    const { text, response_url, user_name, channel_name } = payload.data;

    try {
      // Parse repository from text if it contains owner/repo format
      let repoFullName: string;
      let commandText = text?.trim() ?? '';

      // Check if text contains a repository path (owner/repo format)
      const repoMatch = commandText.match(/^([\w-]+\/[\w-]+)\s*(.*)/);

      if (repoMatch) {
        // Use the repository from the text
        repoFullName = repoMatch[1];
        commandText = repoMatch[2] ?? 'webhook test acknowledgment';
        logger.info(`Using repository from text: ${repoFullName}`);
      } else {
        // Use default repository from environment
        const defaultRepo = process.env.DEFAULT_GITHUB_REPO ?? 'demo-repository';

        // Check if DEFAULT_GITHUB_REPO already contains owner/repo format
        if (defaultRepo.includes('/')) {
          // It's already a full path, use it directly
          repoFullName = defaultRepo;
        } else {
          // It's just a repo name, use DEFAULT_GITHUB_OWNER
          const owner = process.env.DEFAULT_GITHUB_OWNER;

          if (!owner) {
            await this.respondToSlack(response_url, {
              text: '❌ DEFAULT_GITHUB_OWNER not configured. Please specify repository as: `/test owner/repo [command]`'
            });
            return {
              success: false,
              error: 'DEFAULT_GITHUB_OWNER not configured'
            };
          }

          repoFullName = `${owner}/${defaultRepo}`;
        }

        commandText = commandText ?? 'webhook test acknowledgment';
        logger.info(`Using default repository: ${repoFullName}`);
      }

      // Send immediate acknowledgment to Slack
      await this.respondToSlack(response_url, {
        text: `🧪 Processing test command for repository: ${repoFullName}`
      });

      // Create prompt for Claude
      const claudePrompt = `You are responding to a webhook test from Slack.

User ${user_name} from ${channel_name} channel sent a test command.
Repository: ${repoFullName}
Command: ${commandText}

Please acknowledge the test and perform the requested action if any.
If it's just a test, create a simple acknowledgment.`;

      // Process with Claude
      const response = await processCommand({
        repoFullName,
        issueNumber: null,
        command: claudePrompt,
        operationType: 'default'
      });

      // Send success response to Slack
      await this.respondToSlack(response_url, {
        text: `✅ Test completed!\n\n${response.substring(0, 500)}${response.length > 500 ? '...' : ''}`
      });

      logger.info('Successfully processed test command', {
        user: user_name,
        repository: repoFullName,
        command: commandText
      });

      return {
        success: true,
        message: 'Test command processed',
        data: { repository: repoFullName }
      };
    } catch (error) {
      logger.error('Failed to process test command', { error, text });

      await this.respondToSlack(response_url, {
        text: `❌ Test failed: ${error instanceof Error ? error.message : 'Unknown error'}`
      });

      return {
        success: false,
        error: error instanceof Error ? error.message : 'Failed to process test command'
      };
    }
  }

  /**
   * Send response back to Slack
   */
  private async respondToSlack(
    responseUrl: string | undefined,
    message: { text: string }
  ): Promise<void> {
    if (!responseUrl) {
      logger.warn('No response URL provided for Slack message');
      return;
    }

    try {
      await axios.post(responseUrl, message);
    } catch (error) {
      logger.error('Failed to send response to Slack', { error });
    }
  }
}

// Export singleton instance
export const testHandler = new TestHandler();

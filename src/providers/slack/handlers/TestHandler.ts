import type { WebhookContext, WebhookHandlerResponse } from '../../../types/webhook';
import type { SlackWebhookPayload } from '../SlackWebhookProvider';
import { createLogger } from '../../../utils/logger';
import { parseRepositoryFromText } from '../../../utils/repositoryParser';
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
      // Parse repository from text
      const inputText = text?.trim() ?? '';
      const parsed = parseRepositoryFromText(inputText);
      const { owner, repo, remainingText } = parsed;

      // Check if we have a valid owner (for backward compatibility with error message)
      if (
        !parsed.isExplicit &&
        !process.env.DEFAULT_GITHUB_OWNER &&
        !process.env.DEFAULT_GITHUB_REPO?.includes('/')
      ) {
        await this.respondToSlack(response_url, {
          text: '❌ DEFAULT_GITHUB_OWNER not configured. Please specify repository as: `/test owner/repo [command]`'
        });
        return {
          success: false,
          error: 'DEFAULT_GITHUB_OWNER not configured'
        };
      }

      const repoFullName = `${owner}/${repo}`;
      const commandText = remainingText || 'webhook test acknowledgment';

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

import crypto from 'crypto';
import type { WebhookRequest } from '../../types/express';
import type { BaseWebhookPayload, WebhookProvider } from '../../types/webhook';
import { createLogger } from '../../utils/logger';

const logger = createLogger('SlackWebhookProvider');

export interface SlackWebhookPayload extends BaseWebhookPayload {
  provider: 'slack';
  data: {
    token?: string;
    team_id?: string;
    team_domain?: string;
    channel_id?: string;
    channel_name?: string;
    user_id?: string;
    user_name?: string;
    command?: string;
    text?: string;
    response_url?: string;
    trigger_id?: string;
    api_app_id?: string;
  };
}

/**
 * Slack webhook provider implementation
 */
export class SlackWebhookProvider implements WebhookProvider<SlackWebhookPayload> {
  name = 'slack' as const;

  /**
   * Verify Slack request signature
   * https://api.slack.com/authentication/verifying-requests-from-slack
   */
  verifySignature(req: WebhookRequest, secret: string): Promise<boolean> {
    return Promise.resolve(this.verifySignatureSync(req, secret));
  }

  private verifySignatureSync(req: WebhookRequest, secret: string): boolean {
    const signature = req.headers['x-slack-signature'] as string;
    const timestamp = req.headers['x-slack-request-timestamp'] as string;

    if (!signature || !timestamp) {
      logger.warn('Missing Slack signature or timestamp headers');
      return false;
    }

    // Check timestamp to prevent replay attacks (must be within 5 minutes)
    const currentTime = Math.floor(Date.now() / 1000);
    const requestTime = parseInt(timestamp, 10);

    if (Math.abs(currentTime - requestTime) > 60 * 5) {
      logger.warn('Slack request timestamp too old');
      return false;
    }

    // Compute signature
    const sigBasestring = `v0:${timestamp}:${req.rawBody?.toString() ?? ''}`;
    const mySignature =
      'v0=' + crypto.createHmac('sha256', secret).update(sigBasestring).digest('hex');

    // Compare signatures
    return crypto.timingSafeEqual(Buffer.from(mySignature, 'utf8'), Buffer.from(signature, 'utf8'));
  }

  /**
   * Parse Slack webhook payload
   */
  parsePayload(req: WebhookRequest): Promise<SlackWebhookPayload> {
    // Slack sends URL-encoded form data for slash commands
    const data = req.body as SlackWebhookPayload['data'];

    return Promise.resolve({
      id: `slack-${data.trigger_id ?? Date.now()}`,
      timestamp: new Date().toISOString(),
      provider: 'slack',
      source: 'slack',
      event: data.command ? `slash_command:${data.command}` : 'unknown',
      data
    });
  }

  /**
   * Get event type from payload
   */
  getEventType(payload: SlackWebhookPayload): string {
    if (payload.data.command) {
      return `slash_command:${payload.data.command}`;
    }
    return 'unknown';
  }

  /**
   * Get human-readable event description
   */
  getEventDescription(payload: SlackWebhookPayload): string {
    const { command, user_name, text } = payload.data;

    if (command) {
      return `${user_name ?? 'Unknown user'} used ${command}: ${text ?? '(no text)'}`;
    }

    return 'Slack webhook received';
  }

  /**
   * Validate payload structure
   */
  validatePayload(payload: SlackWebhookPayload): Promise<boolean> {
    // Basic validation for slash commands
    if (payload.data.command) {
      return Promise.resolve(!!(payload.data.team_id && payload.data.user_id));
    }

    return Promise.resolve(true);
  }
}

// Export singleton instance
export const slackWebhookProvider = new SlackWebhookProvider();

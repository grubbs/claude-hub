import { webhookRegistry } from '../../core/webhook/WebhookRegistry';
import { slackWebhookProvider } from './SlackWebhookProvider';
import { planHandler } from './handlers/PlanHandler';
import { bugHandler } from './handlers/BugHandler';
import { testHandler } from './handlers/TestHandler';
import { createLogger } from '../../utils/logger';

const logger = createLogger('SlackProvider');

// Register the Slack webhook provider
webhookRegistry.registerProvider(slackWebhookProvider);
logger.info('Slack webhook provider registered');

// Register handlers for Slack slash commands
webhookRegistry.registerHandler('slack', {
  event: 'slash_command:/plan',
  handle: planHandler.handle.bind(planHandler),
  canHandle: planHandler.canHandle.bind(planHandler)
});
logger.info('Registered handler for /plan command');

webhookRegistry.registerHandler('slack', {
  event: 'slash_command:/bug',
  handle: bugHandler.handle.bind(bugHandler),
  canHandle: bugHandler.canHandle.bind(bugHandler)
});
logger.info('Registered handler for /bug command');

webhookRegistry.registerHandler('slack', {
  event: 'slash_command:/test',
  handle: testHandler.handle.bind(testHandler),
  canHandle: testHandler.canHandle.bind(testHandler)
});
logger.info('Registered handler for /test command');

export { slackWebhookProvider };

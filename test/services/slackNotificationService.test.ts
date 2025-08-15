import { WebClient } from '@slack/web-api';
import { SlackNotificationService } from '../../src/services/slackNotificationService';

// Mock the Slack WebClient
jest.mock('@slack/web-api');
jest.mock('../../src/utils/logger');

describe('SlackNotificationService', () => {
  let service: SlackNotificationService;
  let mockPostMessage: jest.Mock;
  const originalEnv = process.env;

  beforeEach(() => {
    jest.clearAllMocks();
    
    // Setup environment variables
    process.env = {
      ...originalEnv,
      SLACK_NOTIFICATION_ENABLED: 'true',
      SLACK_BOT_TOKEN: 'xoxb-test-token',
      SLACK_CHANNEL_ID: 'C1234567890',
      SLACK_NOTIFY_ON_SUCCESS: 'true',
      SLACK_NOTIFY_ON_ERROR: 'true',
      SLACK_NOTIFY_MIN_DURATION_MS: '1000'
    };

    // Mock the WebClient.chat.postMessage method
    mockPostMessage = jest.fn().mockResolvedValue({
      ok: true,
      ts: '1234567890.123456',
      channel: 'C1234567890'
    });

    (WebClient as jest.MockedClass<typeof WebClient>).mockImplementation(() => ({
      chat: {
        postMessage: mockPostMessage
      }
    } as any));

    // Create new service instance
    service = new SlackNotificationService();
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe('notifyTaskComplete', () => {
    const taskContext = {
      repoFullName: 'owner/repo',
      issueNumber: 42,
      type: 'issue_comment' as const,
      user: 'testuser',
      command: 'Fix this bug',
      startTime: Date.now() - 5000 // 5 seconds ago
    };

    const taskResult = {
      success: true,
      responsePreview: 'Bug fixed successfully',
      githubUrl: 'https://github.com/owner/repo/issues/42',
      duration: 5000
    };

    it('should send success notification when task completes successfully', async () => {
      await service.notifyTaskComplete(taskContext, taskResult);

      expect(mockPostMessage).toHaveBeenCalledTimes(1);
      const call = mockPostMessage.mock.calls[0][0];
      
      expect(call.channel).toBe('C1234567890');
      expect(call.text).toContain('✅');
      expect(call.text).toContain('Issue #42');
      expect(call.blocks).toBeDefined();
      
      // Check blocks contain expected information
      const blocks = call.blocks;
      const blockText = JSON.stringify(blocks);
      expect(blockText).toContain('owner/repo');
      expect(blockText).toContain('Issue #42');
      expect(blockText).toContain('@testuser');
      expect(blockText).toContain('Fix this bug');
    });

    it('should not send notification if disabled', async () => {
      process.env.SLACK_NOTIFICATION_ENABLED = 'false';
      const disabledService = new SlackNotificationService();
      
      await disabledService.notifyTaskComplete(taskContext, taskResult);
      
      expect(mockPostMessage).not.toHaveBeenCalled();
    });

    it('should not send notification for quick operations', async () => {
      const quickResult = {
        ...taskResult,
        duration: 500 // Less than minimum duration
      };

      await service.notifyTaskComplete(taskContext, quickResult);
      
      expect(mockPostMessage).not.toHaveBeenCalled();
    });

    it('should not send success notification if SLACK_NOTIFY_ON_SUCCESS is false', async () => {
      process.env.SLACK_NOTIFY_ON_SUCCESS = 'false';
      const noSuccessService = new SlackNotificationService();
      
      await noSuccessService.notifyTaskComplete(taskContext, taskResult);
      
      expect(mockPostMessage).not.toHaveBeenCalled();
    });

    it('should handle PR notifications correctly', async () => {
      const prContext = {
        ...taskContext,
        issueNumber: undefined,
        pullRequestNumber: 123,
        type: 'pull_request_comment' as const
      };

      const prResult = {
        ...taskResult,
        githubUrl: 'https://github.com/owner/repo/pull/123'
      };

      await service.notifyTaskComplete(prContext, prResult);

      const call = mockPostMessage.mock.calls[0][0];
      const blockText = JSON.stringify(call.blocks);
      expect(blockText).toContain('PR #123');
      expect(blockText).toContain('Pull Request');
    });

    it('should handle Slack API errors gracefully', async () => {
      mockPostMessage.mockRejectedValueOnce(new Error('Slack API error'));

      // Should not throw
      await expect(service.notifyTaskComplete(taskContext, taskResult))
        .resolves.not.toThrow();
    });
  });

  describe('notifyTaskError', () => {
    const taskContext = {
      repoFullName: 'owner/repo',
      issueNumber: 42,
      type: 'issue_comment' as const,
      user: 'testuser',
      command: 'Fix this bug',
      startTime: Date.now() - 10000 // 10 seconds ago
    };

    const error = new Error('Container execution timeout');

    it('should send error notification when task fails', async () => {
      await service.notifyTaskError(taskContext, error);

      expect(mockPostMessage).toHaveBeenCalledTimes(1);
      const call = mockPostMessage.mock.calls[0][0];
      
      expect(call.channel).toBe('C1234567890');
      expect(call.text).toContain('❌');
      expect(call.text).toContain('Issue #42');
      
      const blockText = JSON.stringify(call.blocks);
      expect(blockText).toContain('Container execution timeout');
      expect(blockText).toContain('owner/repo');
      expect(blockText).toContain('@testuser');
    });

    it('should not send error notification if disabled', async () => {
      process.env.SLACK_NOTIFY_ON_ERROR = 'false';
      const noErrorService = new SlackNotificationService();
      
      await noErrorService.notifyTaskError(taskContext, error);
      
      expect(mockPostMessage).not.toHaveBeenCalled();
    });

    it('should include stack trace in error notification', async () => {
      const errorWithStack = new Error('Test error');
      errorWithStack.stack = 'Error: Test error\n    at Function.test\n    at Object.run';

      await service.notifyTaskError(taskContext, errorWithStack);

      const call = mockPostMessage.mock.calls[0][0];
      const blockText = JSON.stringify(call.blocks);
      expect(blockText).toContain('Stack Trace');
      expect(blockText).toContain('Error: Test error');
    });

    it('should handle Slack API errors gracefully', async () => {
      mockPostMessage.mockRejectedValueOnce(new Error('Slack API error'));

      // Should not throw
      await expect(service.notifyTaskError(taskContext, error))
        .resolves.not.toThrow();
    });
  });

  describe('notifyTaskStart', () => {
    const taskContext = {
      repoFullName: 'owner/repo',
      issueNumber: 42,
      type: 'issue_comment' as const,
      user: 'testuser',
      command: 'Fix this bug',
      startTime: Date.now()
    };

    it('should send start notification when enabled', async () => {
      process.env.SLACK_NOTIFY_ON_START = 'true';
      const startService = new SlackNotificationService();
      
      await startService.notifyTaskStart(taskContext);

      expect(mockPostMessage).toHaveBeenCalledTimes(1);
      const call = mockPostMessage.mock.calls[0][0];
      
      expect(call.text).toContain('⏳');
      expect(call.text).toContain('Issue #42');
      
      const blockText = JSON.stringify(call.blocks);
      expect(blockText).toContain('Claude is starting to process');
      expect(blockText).toContain('Fix this bug');
    });

    it('should not send start notification by default', async () => {
      await service.notifyTaskStart(taskContext);
      
      expect(mockPostMessage).not.toHaveBeenCalled();
    });
  });

  describe('isEnabled', () => {
    it('should return true when enabled with token', () => {
      expect(service.isEnabled()).toBe(true);
    });

    it('should return false when disabled', () => {
      process.env.SLACK_NOTIFICATION_ENABLED = 'false';
      const disabledService = new SlackNotificationService();
      
      expect(disabledService.isEnabled()).toBe(false);
    });

    it('should return false when no token provided', () => {
      delete process.env.SLACK_BOT_TOKEN;
      const noTokenService = new SlackNotificationService();
      
      expect(noTokenService.isEnabled()).toBe(false);
    });
  });

  describe('formatDuration', () => {
    it('should format seconds correctly', () => {
      const result = (service as any).formatDuration(45000);
      expect(result).toBe('45s');
    });

    it('should format minutes and seconds correctly', () => {
      const result = (service as any).formatDuration(125000);
      expect(result).toBe('2m 5s');
    });

    it('should format hours and minutes correctly', () => {
      const result = (service as any).formatDuration(7325000);
      expect(result).toBe('2h 2m');
    });
  });

  describe('getOperationTypeDisplay', () => {
    it('should return correct display names for operation types', () => {
      expect((service as any).getOperationTypeDisplay('issue_comment')).toBe('Issue Comment');
      expect((service as any).getOperationTypeDisplay('pull_request_comment')).toBe('PR Comment');
      expect((service as any).getOperationTypeDisplay('pr_review')).toBe('PR Review');
      expect((service as any).getOperationTypeDisplay('auto_tag')).toBe('Auto-Tagging');
      expect((service as any).getOperationTypeDisplay('check_suite')).toBe('Check Suite');
      expect((service as any).getOperationTypeDisplay('unknown')).toBe('unknown');
    });
  });
});
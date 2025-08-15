import type { WebhookContext, WebhookHandlerResponse } from '../../../types/webhook';
import type { SlackWebhookPayload } from '../SlackWebhookProvider';
import { createLogger } from '../../../utils/logger';
import { createIssue } from '../../../services/githubService';
import { processCommand } from '../../../services/claudeService';
import axios from 'axios';

const logger = createLogger('PlanHandler');

/**
 * Handler for /plan Slack command
 * Takes an idea and creates a GitHub issue with a detailed design document
 */
export class PlanHandler {
  name = 'plan_handler';

  /**
   * Check if this handler can process the event
   */
  canHandle(payload: SlackWebhookPayload): boolean {
    return payload.data.command === '/plan';
  }

  /**
   * Handle the /plan command
   */
  async handle(
    payload: SlackWebhookPayload,
    _context: WebhookContext
  ): Promise<WebhookHandlerResponse> {
    const { text, response_url, user_name, channel_name } = payload.data;

    if (!text || text.trim().length === 0) {
      await this.respondToSlack(response_url, {
        text: '❌ Please provide an idea to plan. Usage: `/plan [your idea]`'
      });
      return {
        success: false,
        error: 'No idea provided'
      };
    }

    try {
      // Send immediate acknowledgment to Slack
      await this.respondToSlack(response_url, {
        text: `🤔 Processing your idea: "${text}"\nI'll create a detailed GitHub issue with a design document...`
      });

      // Parse repository from text if it starts with owner/repo format
      let owner: string;
      let repo: string;
      let ideaText = text;

      // Check if text starts with a repository path (owner/repo format)
      const repoMatch = text.match(/^([\w-]+)\/([\w-]+)\s+(.*)/);

      if (repoMatch) {
        // Use the repository from the text
        owner = repoMatch[1];
        repo = repoMatch[2];
        ideaText = repoMatch[3];
        logger.info(`Using repository from text: ${owner}/${repo}`);
      } else {
        // Use default repository from environment
        owner = process.env.DEFAULT_GITHUB_OWNER ?? 'claude-did-this';
        repo = process.env.DEFAULT_GITHUB_REPO ?? 'demo-repository';
      }

      // Create prompt for Claude to generate a detailed design document
      const claudePrompt = `You are a senior software architect creating a detailed design document for a new feature idea.

User ${user_name} from ${channel_name} channel has submitted the following idea:
"${ideaText}"

Please create a comprehensive GitHub issue that includes:

1. **Executive Summary** - Brief overview of the proposed feature
2. **Problem Statement** - What problem does this solve? Who benefits?
3. **Proposed Solution** - Detailed technical approach
4. **Technical Architecture** - System design and component interaction
5. **Implementation Plan** - Step-by-step approach with milestones
6. **Code Examples** - Concrete implementation examples in the appropriate language
7. **API Design** (if applicable) - Endpoints, request/response formats
8. **Database Schema** (if applicable) - Tables, relationships, indexes
9. **Security Considerations** - Authentication, authorization, data protection
10. **Performance Implications** - Expected load, scaling considerations
11. **Testing Strategy** - Unit tests, integration tests, E2E tests
12. **Migration Plan** (if modifying existing features)
13. **Open Questions** - Technical decisions that need product owner input
14. **Alternatives Considered** - Other approaches and why they weren't chosen
15. **Success Metrics** - How will we measure if this is successful?
16. **Timeline Estimate** - Rough development time estimate

Format the response as a well-structured GitHub issue with markdown formatting.
Make it thorough but readable. Include specific code examples where helpful.
End with a section of specific questions for the product owner to help refine requirements.`;

      // Process with Claude
      const designDoc = await processCommand({
        repoFullName: `${owner}/${repo}`,
        issueNumber: null,
        command: claudePrompt,
        operationType: 'default'
      });

      // Extract title from the design doc (first line after removing #)
      const lines = designDoc.split('\n');
      const title = lines[0].replace(/^#+\s*/, '') || `Feature Idea: ${text.substring(0, 50)}`;

      // Create GitHub issue
      const issue = await createIssue(owner, repo, {
        title,
        body: `## Submitted via Slack by @${user_name}\n\n**Original Idea:** ${ideaText}\n\n---\n\n${designDoc}`,
        labels: ['enhancement', 'design-document', 'needs-review']
      });

      // Send success response to Slack
      await this.respondToSlack(response_url, {
        text: `✅ Design document created successfully!\n\n**Issue #${issue.number}:** ${title}\n**View on GitHub:** ${issue.html_url}`
      });

      logger.info('Successfully created design document issue', {
        issueNumber: issue.number,
        user: user_name,
        idea: text.substring(0, 100)
      });

      return {
        success: true,
        message: `Created issue #${issue.number}`,
        data: { issueNumber: issue.number, issueUrl: issue.html_url }
      };
    } catch (error) {
      logger.error('Failed to create design document', { error, idea: text });

      await this.respondToSlack(response_url, {
        text: `❌ Failed to create design document: ${error instanceof Error ? error.message : 'Unknown error'}`
      });

      return {
        success: false,
        error: error instanceof Error ? error.message : 'Failed to create design document'
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
export const planHandler = new PlanHandler();

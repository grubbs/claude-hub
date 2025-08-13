import type { WebhookContext, WebhookHandlerResponse } from '../../../types/webhook';
import type { SlackWebhookPayload } from '../SlackWebhookProvider';
import { createLogger } from '../../../utils/logger';
import { createIssue } from '../../../services/githubService';
import { processCommand } from '../../../services/claudeService';
import axios from 'axios';

const logger = createLogger('BugHandler');

/**
 * Handler for /bug Slack command
 * Takes a bug report and creates a GitHub issue with root cause analysis and solution design
 */
export class BugHandler {
  name = 'bug_handler';

  /**
   * Check if this handler can process the event
   */
  canHandle(payload: SlackWebhookPayload): boolean {
    return payload.data.command === '/bug';
  }

  /**
   * Handle the /bug command
   */
  async handle(
    payload: SlackWebhookPayload,
    _context: WebhookContext
  ): Promise<WebhookHandlerResponse> {
    const { text, response_url, user_name, channel_name } = payload.data;

    if (!text || text.trim().length === 0) {
      await this.respondToSlack(response_url, {
        text: '❌ Please describe the bug. Usage: `/bug [description of the issue]`'
      });
      return {
        success: false,
        error: 'No bug description provided'
      };
    }

    try {
      // Send immediate acknowledgment to Slack
      await this.respondToSlack(response_url, {
        text: `🔍 Analyzing bug report: "${text}"\nI'll create a detailed root cause analysis and solution design...`
      });

      // Get repository info from environment or default
      const owner = process.env.DEFAULT_GITHUB_OWNER ?? 'claude-did-this';
      const repo = process.env.DEFAULT_GITHUB_REPO ?? 'demo-repository';

      // Create prompt for Claude to generate root cause analysis and solution
      const claudePrompt = `You are a senior software engineer performing root cause analysis and solution design for a bug report.

User ${user_name} from ${channel_name} channel has reported the following bug:
"${text}"

Please create a comprehensive GitHub issue that includes:

## 🐛 Bug Report Analysis

### 1. **Issue Summary**
Provide a clear, concise summary of the bug.

### 2. **Symptoms**
- What is the observed behavior?
- What error messages appear?
- When does it occur?
- How frequently does it occur?

### 3. **Expected Behavior**
What should happen instead?

### 4. **Root Cause Analysis**
#### Hypothesis 1: [Most Likely Cause]
- Technical explanation
- Code locations likely affected
- Why this would cause the observed symptoms

#### Hypothesis 2: [Alternative Cause]
- Technical explanation
- Code locations likely affected
- Why this would cause the observed symptoms

#### Hypothesis 3: [Less Likely but Possible]
- Technical explanation
- Code locations likely affected
- Why this would cause the observed symptoms

### 5. **Impact Assessment**
- **Severity**: Critical/High/Medium/Low
- **Affected Users**: Who is impacted?
- **Business Impact**: What functionality is broken?
- **Data Integrity**: Any risk to data?
- **Security Implications**: Any security concerns?

### 6. **Reproduction Steps**
1. [Step by step instructions to reproduce]
2. [Include specific data/conditions needed]
3. [Expected vs actual results]

### 7. **Solution Design**

#### Immediate Fix (Hotfix)
- Quick solution to stop the bleeding
- Code changes required
- Estimated time: X hours

\`\`\`[language]
// Example code for immediate fix
\`\`\`

#### Proper Solution
- Comprehensive fix addressing root cause
- Architecture changes if needed
- Code changes required
- Estimated time: X days

\`\`\`[language]
// Example code for proper solution
\`\`\`

### 8. **Testing Strategy**
- **Unit Tests**: Test cases to add
- **Integration Tests**: Scenarios to cover
- **Regression Tests**: Ensure no side effects
- **Manual Testing**: Specific scenarios to verify

### 9. **Prevention Measures**
- How can we prevent similar bugs in the future?
- Code review checklist additions
- Monitoring/alerting improvements
- Documentation updates needed

### 10. **Questions for Product Owner**
- [ ] Should we prioritize the hotfix or wait for proper solution?
- [ ] Are there any workarounds users can use in the meantime?
- [ ] What is the acceptable downtime for fixing this?
- [ ] Should we notify affected users? If so, what should we communicate?
- [ ] [Add specific questions based on the bug]

### 11. **Related Issues**
- List any potentially related issues or previous occurrences

### 12. **References**
- Links to relevant documentation
- Stack traces
- Log files
- Related PRs or commits

Format the response as a well-structured GitHub issue with markdown formatting.
Be thorough but concise. Include specific code examples where helpful.
If you need more information to properly diagnose, list those questions clearly.`;

      // Process with Claude
      const analysis = await processCommand({
        repoFullName: `${owner}/${repo}`,
        issueNumber: null,
        command: claudePrompt,
        operationType: 'default'
      });

      // Extract title from the analysis (first line after removing #)
      const lines = analysis.split('\n');
      const title = lines[0].replace(/^#+\s*/, '') || `Bug Report: ${text.substring(0, 50)}`;

      // Create GitHub issue
      const issue = await createIssue(owner, repo, {
        title,
        body: `## Reported via Slack by @${user_name}\n\n**Original Report:** ${text}\n\n---\n\n${analysis}`,
        labels: ['bug', 'needs-triage', 'root-cause-analysis']
      });

      // Send success response to Slack
      await this.respondToSlack(response_url, {
        text: `✅ Bug analysis created successfully!\n\n**Issue #${issue.number}:** ${title}\n**View on GitHub:** ${issue.html_url}`
      });

      logger.info('Successfully created bug analysis issue', {
        issueNumber: issue.number,
        user: user_name,
        bug: text.substring(0, 100)
      });

      return {
        success: true,
        message: `Created issue #${issue.number}`,
        data: { issueNumber: issue.number, issueUrl: issue.html_url }
      };
    } catch (error) {
      logger.error('Failed to create bug analysis', { error, bug: text });

      await this.respondToSlack(response_url, {
        text: `❌ Failed to create bug analysis: ${error instanceof Error ? error.message : 'Unknown error'}`
      });

      return {
        success: false,
        error: error instanceof Error ? error.message : 'Failed to create bug analysis'
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
export const bugHandler = new BugHandler();

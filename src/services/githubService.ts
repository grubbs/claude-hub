import { Octokit } from '@octokit/rest';
import { createLogger } from '../utils/logger';
import secureCredentials from '../utils/secureCredentials';
import type {
  CreateCommentRequest,
  CreateCommentResponse,
  AddLabelsRequest,
  ManagePRLabelsRequest,
  CreateRepositoryLabelsRequest,
  GetCombinedStatusRequest,
  HasReviewedPRRequest,
  GetCheckSuitesRequest,
  ValidatedGitHubParams,
  GitHubCombinedStatus,
  GitHubLabel,
  GitHubCheckSuitesResponse
} from '../types/github';

const logger = createLogger('githubService');

// Create Octokit instance (lazy initialization)
let octokit: Octokit | null = null;

function getOctokit(): Octokit | null {
  if (!octokit) {
    const githubToken = secureCredentials.get('GITHUB_TOKEN');
    // Support both classic (ghp_) and fine-grained (github_pat_) GitHub tokens
    if (githubToken && (githubToken.includes('ghp_') || githubToken.includes('github_pat_'))) {
      octokit = new Octokit({
        auth: githubToken,
        userAgent: 'Claude-GitHub-Webhook'
      });
    }
  }
  return octokit;
}

/**
 * Posts a comment to a GitHub issue or pull request
 */
export async function postComment({
  repoOwner,
  repoName,
  issueNumber,
  body
}: CreateCommentRequest): Promise<CreateCommentResponse> {
  try {
    // Validate parameters to prevent SSRF
    const validated = validateGitHubParams(repoOwner, repoName, issueNumber);
    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber,
        bodyLength: body.length
      },
      'Posting comment to GitHub'
    );

    // In test mode, just log the comment instead of posting to GitHub
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          issue: issueNumber,
          bodyPreview: body.substring(0, 100) + (body.length > 100 ? '...' : '')
        },
        'TEST MODE: Would post comment to GitHub'
      );

      return {
        id: 'test-comment-id',
        body: body,
        created_at: new Date().toISOString()
      };
    }

    // Use Octokit to create comment
    const { data } = await client.issues.createComment({
      owner: validated.repoOwner,
      repo: validated.repoName,
      issue_number: validated.issueNumber,
      body: body
    });

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber,
        commentId: data.id
      },
      'Comment posted successfully'
    );

    return {
      id: data.id,
      body: data.body ?? '',
      created_at: data.created_at
    };
  } catch (error) {
    const err = error as Error & { response?: { data?: unknown } };
    logger.error(
      {
        err: {
          message: err.message,
          responseData: err.response?.data
        },
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber
      },
      'Error posting comment to GitHub'
    );

    throw new Error(`Failed to post comment: ${err.message}`);
  }
}

/**
 * Validates GitHub repository and issue parameters to prevent SSRF
 */
function validateGitHubParams(
  repoOwner: string,
  repoName: string,
  issueNumber: number
): ValidatedGitHubParams {
  // Validate repoOwner and repoName contain only safe characters
  const repoPattern = /^[a-zA-Z0-9._-]+$/;
  if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
    throw new Error('Invalid repository owner or name - contains unsafe characters');
  }

  // Validate issueNumber is a positive integer
  const issueNum = parseInt(String(issueNumber), 10);
  if (!Number.isInteger(issueNum) || issueNum <= 0) {
    throw new Error('Invalid issue number - must be a positive integer');
  }

  return { repoOwner, repoName, issueNumber: issueNum };
}

/**
 * Adds labels to a GitHub issue
 */
export async function addLabelsToIssue({
  repoOwner,
  repoName,
  issueNumber,
  labels
}: AddLabelsRequest): Promise<GitHubLabel[]> {
  try {
    // Validate parameters to prevent SSRF
    const validated = validateGitHubParams(repoOwner, repoName, issueNumber);
    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber,
        labelCount: labels.length
      },
      'Adding labels to GitHub issue'
    );

    // In test mode, just log the labels instead of applying to GitHub
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          issue: issueNumber,
          labelCount: labels.length
        },
        'TEST MODE: Would add labels to GitHub issue'
      );

      return labels.map((label, index) => ({
        id: index,
        name: label,
        color: '000000',
        description: null
      }));
    }

    // Use Octokit to add labels
    const { data } = await client.issues.addLabels({
      owner: validated.repoOwner,
      repo: validated.repoName,
      issue_number: validated.issueNumber,
      labels: labels
    });

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber,
        appliedLabels: data.map(label => label.name)
      },
      'Labels added successfully'
    );

    return data;
  } catch (error) {
    const err = error as Error & { response?: { data?: unknown } };
    logger.error(
      {
        err: {
          message: err.message,
          responseData: err.response?.data
        },
        repo: `${repoOwner}/${repoName}`,
        issue: issueNumber,
        labelCount: labels.length
      },
      'Error adding labels to GitHub issue'
    );

    throw new Error(`Failed to add labels: ${err.message}`);
  }
}

/**
 * Creates repository labels if they don't exist
 */
export async function createRepositoryLabels({
  repoOwner,
  repoName,
  labels
}: CreateRepositoryLabelsRequest): Promise<GitHubLabel[]> {
  try {
    // Validate repository parameters to prevent SSRF
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name - contains unsafe characters');
    }

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        labelCount: labels.length
      },
      'Creating repository labels'
    );

    // In test mode, just log the operation
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          labels: labels
        },
        'TEST MODE: Would create repository labels'
      );
      return labels.map((label, index) => ({
        id: index,
        name: label.name,
        color: label.color,
        description: label.description ?? null
      }));
    }

    const createdLabels: GitHubLabel[] = [];

    for (const label of labels) {
      try {
        // Use Octokit to create label
        const { data } = await client.issues.createLabel({
          owner: repoOwner,
          repo: repoName,
          name: label.name,
          color: label.color,
          description: label.description
        });

        createdLabels.push(data);
        logger.debug({ labelName: label.name }, 'Label created successfully');
      } catch (error) {
        const err = error as Error & { status?: number };
        // Label might already exist - check if it's a 422 (Unprocessable Entity)
        if (err.status === 422) {
          logger.debug({ labelName: label.name }, 'Label already exists, skipping');
        } else {
          logger.warn(
            {
              err: err.message,
              labelName: label.name
            },
            'Failed to create label'
          );
        }
      }
    }

    return createdLabels;
  } catch (error) {
    const err = error as Error;
    logger.error(
      {
        err: err.message,
        repo: `${repoOwner}/${repoName}`
      },
      'Error creating repository labels'
    );

    throw new Error(`Failed to create labels: ${err.message}`);
  }
}

/**
 * Gets pull request details from GitHub
 */
export async function getPullRequestDetails({
  repoOwner,
  repoName,
  prNumber
}: {
  repoOwner: string;
  repoName: string;
  prNumber: number;
}): Promise<{ head: { ref: string; sha: string }; base: { ref: string } } | null> {
  try {
    // Validate parameters
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name');
    }

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber
      },
      'Fetching pull request details from GitHub'
    );

    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info('TEST MODE: Would fetch PR details from GitHub');
      return {
        head: { ref: 'feature-branch', sha: 'abc123' },
        base: { ref: 'main' }
      };
    }

    const { data } = await client.pulls.get({
      owner: repoOwner,
      repo: repoName,
      pull_number: prNumber
    });

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber,
        headRef: data.head.ref,
        baseRef: data.base.ref
      },
      'Pull request details fetched successfully'
    );

    return {
      head: {
        ref: data.head.ref,
        sha: data.head.sha
      },
      base: {
        ref: data.base.ref
      }
    };
  } catch (error) {
    const err = error as Error;
    logger.error(
      {
        err: err,
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber
      },
      'Error fetching pull request details'
    );
    return null;
  }
}

/**
 * Provides fallback labels based on simple keyword matching
 */
export function getFallbackLabels(title: string, body: string | null): string[] {
  const content = `${title} ${body ?? ''}`.toLowerCase();
  const labels: string[] = [];

  // Type detection - check documentation first for specificity
  if (
    content.includes(' doc ') ||
    content.includes('docs') ||
    content.includes('readme') ||
    content.includes('documentation')
  ) {
    labels.push('type:documentation');
  } else if (
    content.includes('bug') ||
    content.includes('error') ||
    content.includes('issue') ||
    content.includes('problem')
  ) {
    labels.push('type:bug');
  } else if (content.includes('feature') || content.includes('add') || content.includes('new')) {
    labels.push('type:feature');
  } else if (
    content.includes('improve') ||
    content.includes('enhance') ||
    content.includes('better')
  ) {
    labels.push('type:enhancement');
  } else if (content.includes('question') || content.includes('help') || content.includes('how')) {
    labels.push('type:question');
  }

  // Priority detection
  if (
    content.includes('critical') ||
    content.includes('urgent') ||
    content.includes('security') ||
    content.includes('down')
  ) {
    labels.push('priority:critical');
  } else if (content.includes('important') || content.includes('high')) {
    labels.push('priority:high');
  } else {
    labels.push('priority:medium');
  }

  // Component detection
  if (content.includes('api') || content.includes('endpoint')) {
    labels.push('component:api');
  } else if (
    content.includes('ui') ||
    content.includes('frontend') ||
    content.includes('interface')
  ) {
    labels.push('component:frontend');
  } else if (content.includes('backend') || content.includes('server')) {
    labels.push('component:backend');
  } else if (content.includes('database') || content.includes('db')) {
    labels.push('component:database');
  } else if (
    content.includes('auth') ||
    content.includes('login') ||
    content.includes('permission')
  ) {
    labels.push('component:auth');
  } else if (content.includes('webhook') || content.includes('github')) {
    labels.push('component:webhook');
  } else if (content.includes('docker') || content.includes('container')) {
    labels.push('component:docker');
  }

  return labels;
}

/**
 * Gets the combined status for a specific commit/ref
 * Used to verify all required status checks have passed
 */
export async function getCombinedStatus({
  repoOwner,
  repoName,
  ref
}: GetCombinedStatusRequest): Promise<GitHubCombinedStatus> {
  try {
    // Validate parameters to prevent SSRF
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name - contains unsafe characters');
    }

    // Validate ref (commit SHA, branch, or tag)
    const refPattern = /^[a-zA-Z0-9._/-]+$/;
    if (!refPattern.test(ref)) {
      throw new Error('Invalid ref - contains unsafe characters');
    }

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        ref: ref
      },
      'Getting combined status from GitHub'
    );

    // In test mode, return a mock successful status
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          ref: ref
        },
        'TEST MODE: Returning mock successful combined status'
      );

      return {
        state: 'success',
        total_count: 2,
        statuses: [
          { state: 'success', context: 'ci/test', description: null, target_url: null },
          { state: 'success', context: 'ci/build', description: null, target_url: null }
        ]
      };
    }

    // Use Octokit to get combined status
    const { data } = await client.repos.getCombinedStatusForRef({
      owner: repoOwner,
      repo: repoName,
      ref: ref
    });

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        ref: ref,
        state: data.state,
        totalCount: data.total_count
      },
      'Combined status retrieved successfully'
    );

    return data;
  } catch (error) {
    const err = error as Error & { response?: { status?: number; data?: unknown } };
    logger.error(
      {
        err: {
          message: err.message,
          status: err.response?.status,
          responseData: err.response?.data
        },
        repo: `${repoOwner}/${repoName}`,
        ref: ref
      },
      'Error getting combined status from GitHub'
    );

    throw new Error(`Failed to get combined status: ${err.message}`);
  }
}

/**
 * Check if we've already reviewed this PR at the given commit SHA
 */
export async function hasReviewedPRAtCommit({
  repoOwner,
  repoName,
  prNumber,
  commitSha
}: HasReviewedPRRequest): Promise<boolean> {
  try {
    // Validate parameters
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name - contains unsafe characters');
    }

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber,
        commitSha: commitSha
      },
      'Checking if PR has been reviewed at commit'
    );

    // In test mode, return false to allow review
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      return false;
    }

    // Get review comments for this PR using Octokit
    const { data: reviews } = await client.pulls.listReviews({
      owner: repoOwner,
      repo: repoName,
      pull_number: prNumber
    });

    // Check if any review mentions this specific commit SHA
    const botUsername = process.env.BOT_USERNAME ?? 'ClaudeBot';
    const existingReview = reviews.find(review => {
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      return review.user?.login === botUsername && review.body?.includes(`commit: ${commitSha}`);
    });

    return !!existingReview;
  } catch (error) {
    const err = error as Error;
    logger.error(
      {
        err: err.message,
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber
      },
      'Failed to check for existing reviews'
    );
    // On error, assume not reviewed to avoid blocking reviews
    return false;
  }
}

/**
 * Gets check suites for a specific commit
 */
export async function getCheckSuitesForRef({
  repoOwner,
  repoName,
  ref
}: GetCheckSuitesRequest): Promise<GitHubCheckSuitesResponse> {
  try {
    // Validate parameters to prevent SSRF
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name - contains unsafe characters');
    }

    // Validate ref (commit SHA, branch, or tag)
    const refPattern = /^[a-zA-Z0-9._/-]+$/;
    if (!refPattern.test(ref)) {
      throw new Error('Invalid ref - contains unsafe characters');
    }

    logger.info(
      {
        repo: `${repoOwner}/${repoName}`,
        ref
      },
      'Getting check suites for ref'
    );

    // In test mode, return mock data
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      return {
        total_count: 1,
        check_suites: [
          {
            id: 12345,
            head_branch: 'main',
            head_sha: ref,
            status: 'completed',
            conclusion: 'success',
            app: { id: 1, slug: 'github-actions', name: 'GitHub Actions' },
            pull_requests: [],
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            latest_check_runs_count: 1
          }
        ]
      };
    }

    // Use Octokit's built-in method
    const { data } = await client.checks.listSuitesForRef({
      owner: repoOwner,
      repo: repoName,
      ref: ref
    });

    // Transform the response to match our interface
    const transformedResponse: GitHubCheckSuitesResponse = {
      total_count: data.total_count,
      check_suites: data.check_suites.map(suite => ({
        id: suite.id,
        head_branch: suite.head_branch,
        head_sha: suite.head_sha,
        status: suite.status,
        conclusion: suite.conclusion,
        app: suite.app
          ? {
              id: suite.app.id,
              slug: suite.app.slug,
              name: suite.app.name
            }
          : null,
        pull_requests: null, // Simplified for our use case
        created_at: suite.created_at,
        updated_at: suite.updated_at,
        latest_check_runs_count: suite.latest_check_runs_count
      }))
    };

    return transformedResponse;
  } catch (error) {
    const err = error as Error;
    logger.error(
      {
        err: err.message,
        repo: `${repoOwner}/${repoName}`,
        ref
      },
      'Failed to get check suites'
    );

    throw error;
  }
}

/**
 * Add or remove labels on a pull request
 */
export async function managePRLabels({
  repoOwner,
  repoName,
  prNumber,
  labelsToAdd = [],
  labelsToRemove = []
}: ManagePRLabelsRequest): Promise<void> {
  try {
    // Validate parameters
    const repoPattern = /^[a-zA-Z0-9._-]+$/;
    if (!repoPattern.test(repoOwner) || !repoPattern.test(repoName)) {
      throw new Error('Invalid repository owner or name - contains unsafe characters');
    }

    // In test mode, just log
    const client = getOctokit();
    if (process.env.NODE_ENV === 'test' || !client) {
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          pr: prNumber,
          labelsToAdd,
          labelsToRemove
        },
        'TEST MODE: Would manage PR labels'
      );
      return;
    }

    // Remove labels first using Octokit
    for (const label of labelsToRemove) {
      try {
        await client.issues.removeLabel({
          owner: repoOwner,
          repo: repoName,
          issue_number: prNumber,
          name: label
        });
        logger.info(
          {
            repo: `${repoOwner}/${repoName}`,
            pr: prNumber,
            label
          },
          'Removed label from PR'
        );
      } catch (error) {
        const err = error as Error & { status?: number };
        // Ignore 404 errors (label not present)
        if (err.status !== 404) {
          logger.error(
            {
              err: err.message,
              label
            },
            'Failed to remove label'
          );
        }
      }
    }

    // Add new labels using Octokit
    if (labelsToAdd.length > 0) {
      await client.issues.addLabels({
        owner: repoOwner,
        repo: repoName,
        issue_number: prNumber,
        labels: labelsToAdd
      });
      logger.info(
        {
          repo: `${repoOwner}/${repoName}`,
          pr: prNumber,
          labels: labelsToAdd
        },
        'Added labels to PR'
      );
    }
  } catch (error) {
    const err = error as Error;
    logger.error(
      {
        err: err.message,
        repo: `${repoOwner}/${repoName}`,
        pr: prNumber
      },
      'Failed to manage PR labels'
    );
    throw error;
  }
}

/**
 * Creates a new GitHub issue
 */
export async function createIssue(
  owner: string,
  repo: string,
  { title, body, labels = [] }: { title: string; body: string; labels?: string[] }
): Promise<any> {
  try {
    // Validate parameters
    const validated = validateGitHubParams(owner, repo, 1);

    logger.info(
      {
        repo: `${owner}/${repo}`,
        title,
        labels
      },
      'Creating GitHub issue'
    );

    const client = getOctokit();
    if (!client) {
      throw new Error('GitHub client not configured');
    }

    // Create the issue
    const { data } = await client.issues.create({
      owner: validated.repoOwner,
      repo: validated.repoName,
      title,
      body,
      labels
    });

    logger.info(
      {
        repo: `${owner}/${repo}`,
        issueNumber: data.number,
        issueUrl: data.html_url
      },
      'Issue created successfully'
    );

    return data;
  } catch (error) {
    logger.error({ err: error, repo: `${owner}/${repo}` }, 'Failed to create GitHub issue');
    throw error;
  }
}

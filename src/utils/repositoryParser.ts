/**
 * Utility for parsing repository information from text
 */

import { createLogger } from './logger';

const logger = createLogger('repositoryParser');

export interface ParsedRepository {
  owner: string;
  repo: string;
  remainingText: string;
  isExplicit: boolean; // true if explicitly provided in text, false if using defaults
}

/**
 * Parse repository information from text that may start with owner/repo format
 * @param text - The input text to parse
 * @param defaultOwner - Default owner to use if not specified
 * @param defaultRepo - Default repository to use if not specified
 * @returns Parsed repository information
 */
export function parseRepositoryFromText(
  text: string,
  defaultOwner?: string,
  defaultRepo?: string
): ParsedRepository {
  // Trim the input text
  const trimmedText = text.trim();

  // Enhanced regex to handle various GitHub repository name formats
  // Supports: letters, numbers, hyphens, underscores, and dots
  const repoMatch = trimmedText.match(/^([\w.-]+)\/([\w.-]+)(?:\s+(.*))?$/);

  if (repoMatch) {
    // Repository explicitly provided in text
    const owner = repoMatch[1];
    const repo = repoMatch[2];
    const remainingText = repoMatch[3] || '';

    logger.info(`Parsed explicit repository: ${owner}/${repo}`);

    return {
      owner,
      repo,
      remainingText: remainingText.trim(),
      isExplicit: true
    };
  }

  // No repository in text, use defaults
  const defaultRepoValue = defaultRepo ?? process.env.DEFAULT_GITHUB_REPO ?? 'demo-repository';
  const defaultOwnerValue = defaultOwner ?? process.env.DEFAULT_GITHUB_OWNER ?? 'claude-did-this';

  // Check if DEFAULT_GITHUB_REPO already contains owner/repo format
  if (defaultRepoValue.includes('/')) {
    const parts = defaultRepoValue.split('/');
    const owner = parts[0];
    const repo = parts.slice(1).join('/'); // Handle cases with multiple slashes

    logger.info(`Using default repository with full path: ${owner}/${repo}`);

    return {
      owner,
      repo,
      remainingText: trimmedText,
      isExplicit: false
    };
  }

  // Use separate owner and repo defaults
  logger.info(`Using default repository: ${defaultOwnerValue}/${defaultRepoValue}`);

  return {
    owner: defaultOwnerValue,
    repo: defaultRepoValue,
    remainingText: trimmedText,
    isExplicit: false
  };
}

/**
 * Validate repository name format
 * @param owner - Repository owner
 * @param repo - Repository name
 * @returns True if valid, false otherwise
 */
export function isValidRepository(owner: string, repo: string): boolean {
  // GitHub repository naming rules:
  // - Owner: alphanumeric, hyphens, single dots (not consecutive)
  // - Repo: alphanumeric, hyphens, underscores, dots
  const ownerRegex = /^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$/;
  const repoRegex = /^[a-zA-Z0-9._-]+$/;

  return ownerRegex.test(owner) && repoRegex.test(repo);
}

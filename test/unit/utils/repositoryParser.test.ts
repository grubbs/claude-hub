import { parseRepositoryFromText, isValidRepository } from '../../../src/utils/repositoryParser';

describe('repositoryParser', () => {
  describe('parseRepositoryFromText', () => {
    it('should parse explicit owner/repo from text', () => {
      const result = parseRepositoryFromText('DKG-Technology-LLC/the-rail some command');

      expect(result.owner).toBe('DKG-Technology-LLC');
      expect(result.repo).toBe('the-rail');
      expect(result.remainingText).toBe('some command');
      expect(result.isExplicit).toBe(true);
    });

    it('should handle repos with dots and underscores', () => {
      const result = parseRepositoryFromText('user.name/repo_name.js test');

      expect(result.owner).toBe('user.name');
      expect(result.repo).toBe('repo_name.js');
      expect(result.remainingText).toBe('test');
      expect(result.isExplicit).toBe(true);
    });

    it('should handle empty remaining text', () => {
      const result = parseRepositoryFromText('owner/repo');

      expect(result.owner).toBe('owner');
      expect(result.repo).toBe('repo');
      expect(result.remainingText).toBe('');
      expect(result.isExplicit).toBe(true);
    });

    it('should use defaults when no repo in text', () => {
      const result = parseRepositoryFromText('just some text', 'default-owner', 'default-repo');

      expect(result.owner).toBe('default-owner');
      expect(result.repo).toBe('default-repo');
      expect(result.remainingText).toBe('just some text');
      expect(result.isExplicit).toBe(false);
    });

    it('should handle DEFAULT_GITHUB_REPO with full path', () => {
      const originalRepo = process.env.DEFAULT_GITHUB_REPO;
      process.env.DEFAULT_GITHUB_REPO = 'DKG-Technology-LLC/the-rail';

      const result = parseRepositoryFromText('some command');

      expect(result.owner).toBe('DKG-Technology-LLC');
      expect(result.repo).toBe('the-rail');
      expect(result.remainingText).toBe('some command');
      expect(result.isExplicit).toBe(false);

      // Restore
      if (originalRepo) {
        process.env.DEFAULT_GITHUB_REPO = originalRepo;
      } else {
        delete process.env.DEFAULT_GITHUB_REPO;
      }
    });

    it('should handle repos with multiple slashes in default', () => {
      const result = parseRepositoryFromText('test', undefined, 'owner/project/subproject');

      expect(result.owner).toBe('owner');
      expect(result.repo).toBe('project/subproject');
      expect(result.remainingText).toBe('test');
      expect(result.isExplicit).toBe(false);
    });
  });

  describe('isValidRepository', () => {
    it('should accept valid repository names', () => {
      expect(isValidRepository('owner', 'repo')).toBe(true);
      expect(isValidRepository('owner-123', 'repo_name')).toBe(true);
      expect(isValidRepository('DKG-Technology-LLC', 'the-rail')).toBe(true);
      expect(isValidRepository('user', 'repo.js')).toBe(true);
    });

    it('should reject invalid repository names', () => {
      expect(isValidRepository('-owner', 'repo')).toBe(false);
      expect(isValidRepository('owner-', 'repo')).toBe(false);
      expect(isValidRepository('owner..name', 'repo')).toBe(false);
      expect(isValidRepository('owner', '')).toBe(false);
    });
  });
});

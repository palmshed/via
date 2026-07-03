const parseList = (input) =>
  (input || '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);

module.exports = {
  githubClientId: process.env.GITHUB_CLIENT_ID || '',
  githubClientSecret: process.env.GITHUB_CLIENT_SECRET || '',
  githubToken: process.env.GITHUB_TOKEN || '',
  sessionSecret: process.env.SESSION_SECRET || '',
  repoOwner: process.env.NOTES_REPO_OWNER || 'palmshed',
  repoName: process.env.NOTES_REPO_NAME || 'via',
  repoBranch: process.env.NOTES_REPO_BRANCH || 'gh-pages',
  notesPath: process.env.NOTES_FILE_PATH || 'docs/data/faith-notes.json',
  frontendOrigin: process.env.FRONTEND_ORIGIN || 'https://palmshed.github.io',
  allowedOrigins: parseList(process.env.ALLOWED_ORIGINS || 'https://palmshed.github.io,http://localhost:8000'),
  apiBase: process.env.API_BASE || '',
  adminUsers: parseList(process.env.ADMIN_USERS || '').map((v) => v.toLowerCase()),
};

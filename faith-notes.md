# faith notes

## vercel api
1. Import this repo in Vercel.
2. Set the project root to this branch/repo as usual.
3. Deploy so `/api/*` endpoints are live.

## environment
Set these in Vercel Project Settings -> Environment Variables:

- `API_BASE` = your Vercel URL, for example `https://browser-notes-api.vercel.app`
- `FRONTEND_ORIGIN` = `https://palmshed.github.io`
- `ALLOWED_ORIGINS` = `https://palmshed.github.io`
- `SESSION_SECRET` = long random secret
- `GITHUB_CLIENT_ID` = GitHub OAuth app client id
- `GITHUB_CLIENT_SECRET` = GitHub OAuth app client secret
- `ADMIN_USERS` = comma-separated GitHub usernames allowed to edit notes
- `GITHUB_TOKEN` = GitHub token with repo contents write access
- `NOTES_REPO_OWNER` = `palmshed`
- `NOTES_REPO_NAME` = `browser`
- `NOTES_REPO_BRANCH` = `gh-pages`
- `NOTES_FILE_PATH` = `data/faith-notes.json`

## github oauth
Use this callback URL in the GitHub OAuth app:

```text
https://<your-vercel-domain>/api/auth/github/callback
```

## frontend
In `book-of-faith.html`, set `window.NOTES_API_BASE` to the deployed Vercel URL.

## check
1. Open `https://palmshed.github.io/via/book-of-faith.html`.
2. Click **Login with GitHub**.
3. Confirm the admin section appears.
4. Edit notes and click **Save**.
5. Confirm `data/faith-notes.json` updates in `gh-pages`.

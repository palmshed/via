# Checklists

## Build and Test

- Run `./check.sh` for checks.
- Build desktop app with `flutter build macos`.
- Avoid committing `.env` or secrets.

## Docs Updates

- Keep examples current.
- Scan for broken links.
- Keep instructions consistent with scripts and workflows.

## Release Prep

- Bump `VERSION` to `X.Y.Z+N`.
- Run `./scripts/pubspec.sh`.
- Commit with `chore: bump version to X.Y.Z`.
- Use the release workflow or app automation for `desktop/app-X.Y.Z`.
- Title releases `Release X.Y.Z`.

## PR Quality Gate

- Validate `## Impact` before PR create/edit.
- Ensure every checked Impact box is backed by at least one `## Summary` bullet.
- Use GitHub auto-link keywords (`Resolves #...`, `Closes #...`).

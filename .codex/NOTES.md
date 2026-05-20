# Codex Notes

Use this file to capture project-specific context for Codex, such as:

- Architecture overviews
- Key conventions or guardrails
- Decisions and their rationale
- Known gotchas or edge cases

Keep entries short and dated when useful.

## Conventions

- Prefer small, focused PRs with clear titles and summaries.
- Follow PR title format: `type[scope] :: description`.
- Follow commit format: `type: description`.
- Do not bypass hooks (no `--no-verify`).
- Keep docs concise and action-oriented.

## Command Guidance

- Prefer `apply_patch` for manual file edits.

## Do / Don't

Use:
- Use `rg` for fast searches.
- Keep changes scoped to the request.
- Keep comments brief and useful.

Avoid:
- Revert unrelated local changes.
- Use destructive git commands unless explicitly requested.
- Add Codex-only guidance outside `.codex/` unless asked.

## Decision Log

- 2026-02-03: Added `.codex/` as a committed directory to centralize Codex guidance and templates.
- 2026-02-03: GitHub operations may require running `gh` locally if this sandbox lacks outbound access.

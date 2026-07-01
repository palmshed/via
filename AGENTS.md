# Agent Guidelines

This document describes the engineering conventions for contributing to Via.

## Principles

- Preserve existing behavior unless the task explicitly changes it.
- Prefer small, reviewable changes over large rewrites.
- Verify work before considering it complete.
- Improve clarity rather than reducing line count.
- Do not introduce abstractions unless they simplify ownership.

## Architecture

Via follows clear ownership boundaries.

### BrowserPage

`browser_page.dart` is the browser orchestrator.

It coordinates:

- browser lifecycle
- tab lifecycle
- WebView lifecycle
- navigation sequencing
- interaction between components

Do not place implementation details here unless they coordinate multiple browser responsibilities.

### Widgets

Widgets own presentation and user interaction.

Examples:

- browser_address_bar.dart
- browser_navigation_controls.dart
- browser_overflow_menu.dart
- torry_home_view.dart

Extend existing widgets before creating new ones.

### Models

Models own application state.

Keep state representation separate from presentation.

### Services

Services own browser behavior and infrastructure.

Examples include:

- navigation
- updates
- connectivity
- profile management
- password storage

Business logic belongs here rather than in UI code.

## Before Adding Code

Ask:

- Is this presentation?
- Is this state?
- Is this browser behavior?
- Is this orchestration?

Place the code where that responsibility already exists.

Avoid adding new feature implementations directly to `browser_page.dart`.

## Refactoring

Refactor only when it creates a clearer ownership boundary.

Good reasons:

- a component has multiple responsibilities
- logic belongs to an existing service
- a reusable UI component naturally emerges

Avoid refactoring solely to reduce file length.

## State Management

Prefer the existing architecture.

Avoid introducing additional state-management frameworks unless there is a compelling architectural reason.

## Pull Requests

### Title

Use:

```
type[scope] :: description
```

Examples:

```
feat[browser] :: support pinned tabs
fix[toolbar] :: preserve focus after navigation
refactor[ui] :: extract overflow menu
```

### Description

Include:

- Summary
- Impact
- Related items
- Notes for reviewers

Only check impact categories that are directly applicable.

## Commit Messages

Follow conventional commits.

Examples:

```
feat: support pinned tabs
fix: resolve toolbar focus
refactor: extract browser menu
docs: clarify architecture
```

Keep the subject concise.

Do not bypass repository hooks.

## Verification

Before opening a PR:

```bash
flutter analyze
flutter test
```

Run any additional project-specific validation required by the change.

## Reviews

Review for:

* correctness
* readability
* ownership
* maintainability
* consistency with the existing architecture

Prefer preserving established patterns over introducing new ones.

## Documentation

When changing architecture, public APIs, workflows, or developer experience, update the relevant documentation in the same pull request.

Keep AGENTS.md focused on engineering principles.

Move operational procedures, release guides, version bump instructions, and environment setup into the `docs/` directory.

## Long-Term Goal

Via should remain easy to understand.

* BrowserPage coordinates.
* Widgets render.
* Models represent state.
* Services implement behavior.

Every new feature should strengthen these boundaries rather than blur them.

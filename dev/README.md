# development

Small notes for local development.

## Setup

1. Install Flutter 3.44.4+: https://docs.flutter.dev/get-started/install
2. Clone the repo
3. Run `./check.sh` for the full suite (codegen, analyze, unit test, macOS build, workflow lint)
4. Use the scripts listed below when you need a smaller scope

## Scripts

- `scripts/version.sh`: bump version
- `scripts/pubspec.sh`: sync pubspec version
- `scripts/e2e.sh`: run e2e tests
- `scripts/test.sh`: run unit tests

## Workflows

- `flutter.yml`: Flutter build and test checks
- `ui-test.yml`: focused UI checks
- `e2e.yml`: macOS e2e checks
- `lint.yml`: workflow linting
- `version-bump.yml`: version bump automation
- `browser.yml`, `auto-label.yml`, and `project-board-sync.yml`: app-backed repository automation

# Repository Layout and Generated Files

This document describes how generated files are handled in the repository.

## Generated Files

`.gitattributes` marks generated files so GitHub hides them from diffs and stats. Common generated paths include:

- `build/**` and `.dart_tool/**`
- `lib/**/*.freezed.dart` and `lib/**/*.g.dart`
- Platform artifacts such as `android/**`, `ios/**`, `macos/**`, `linux/**`, and `windows/**`

When a specific file should be shown in diffs, add `-linguist-generated` to `.gitattributes` for that path.

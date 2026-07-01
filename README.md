# Via

A Flutter desktop browser for macOS, Windows, and Linux.

Features include tabbed browsing, bookmarks, history, encrypted local storage, and profile-based settings.

## Design principles

Via favors small, focused components with BrowserPage acting as the coordinator. New functionality should extend existing services or widgets before adding responsibilities to the coordinator.

## Quick start

Clone the repo, install dependencies, and launch the macOS bundle.

```bash
git clone https://github.com/palmshed/via.git
cd via
flutter pub get
cp .env.example .env
flutterfire configure --platforms macos
git checkout -- lib/firebase_options.dart
flutter run -d macos
```

Do not commit `.env`; it contains private Firebase keys.

## Firebase

Via reads Firebase configuration from `.env`.

```bash
cp .env.example .env
flutterfire configure --platforms macos
git checkout -- lib/firebase_options.dart
```

If you change Firebase projects later, rerun `flutterfire configure`.

## Development

Requirements:
- Flutter 3.44.0
- Desktop toolchains

Useful commands:
```bash
./check.sh
flutter analyze
flutter test
flutter build macos
```

## Keyboard shortcuts

Keys are defined in `lib/utils/keyboard_utils.dart`.

| macOS | Windows/Linux | Action |
| --- | --- | --- |
| `Cmd + [` | `Alt + Left` | Navigate backwards in history |
| `Cmd + ]` | `Alt + Right` | Navigate forwards in history |
| `Cmd + R` | `Ctrl + R` | Reload the current tab |
| `Cmd + T` | `Ctrl + T` | Open a new tab |
| `Cmd + W` | `Ctrl + W` | Close the current tab |
| `Cmd + F` | `Ctrl + F` | Focus the address bar |
| `Cmd + Shift + F` | `Ctrl + Shift + F` | Open the page font picker |
| `Cmd + Option + Left` | `Ctrl + Shift + Tab` | Move to the previous tab |
| `Cmd + Option + Right` | `Ctrl + Tab` | Move to the next tab |
| `Cmd + Enter` | `F11` | Toggle fullscreen |
| `Cmd + M` | `Meta + Down` | Minimize the window |
| `Escape` | `Escape` | Close dialogs or stop loading |

## macOS unsigned installs (no paid Developer ID)

Unsigned builds can show Gatekeeper warnings. The first launch can stay in Finder:

1. Drag `Via.app` to **Applications**.
2. Right-click `Via.app`, choose **Open**, and confirm the dialog.
3. Alternatively, open **System Settings → Privacy & Security** and click **Open Anyway** for `Via.app`.

For Terminal installs, clear the quarantine flag with:

```bash
xattr -rd com.apple.quarantine /Applications/Via.app
```

Only run the command if you trust the build source.

## Documentation

- `docs/` contains focused project notes, including [Releasing](docs/releasing.md) and [Repository Layout](docs/repository.md).
- `.codex/README.md` documents toolchains, skills, and local workflows.
- Report bugs or feature requests via [GitHub Issues](https://github.com/palmshed/via/issues).

## Contribute

Fork, create a branch, run the checks, then open a pull request with a short conventional commit-style summary.

Please discuss larger architectural changes before opening a pull request.

## License

This project is proprietary. See `LICENSE` for the full terms.

Copyright (c) 2026 Palmshed. All Rights Reserved.

Sample sample PR.

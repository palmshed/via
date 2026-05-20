# Xcode setup

## Accept Xcode license

After installing Xcode, accept the license agreement:

```bash
sudo xcodebuild -license
```

Scroll to the bottom and type `agree` to accept.

## Switch to Xcode

If both Xcode and Command Line Tools are installed, switch to Xcode:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Verify with:
```bash
xcodebuild -version
```

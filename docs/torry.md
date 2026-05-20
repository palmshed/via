# Torry home

## Overview
- The default `about:browser-home` tab renders a quiet Torry search view instead of a generic browser panel.
- A dedicated Torry search input targets `https://www.torry.io/search/?q=…` and reuses the current tab through `_performTorrySearch`.

## Experience
- The search field auto-focuses when empty and submits through `_performTorrySearch`, which encodes the query and delegates to `_loadUrl`.
- Quick actions open Torry’s onion directory and anonymous-view flow.
- The search input and actions use the app color scheme and responsive layout.

## Maintenance
- Torry search state is tracked per tab via `TabData.torrySearchController` and `TabData.torrySearchFocusNode`, and both are disposed when tabs are removed or the page is disposed to avoid leaks.
- Torry-related UI lives in `_buildTorryHomeView` so future home-screen experiments can swap in updated panels without touching the browser core logic.

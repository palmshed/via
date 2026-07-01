// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:passkeys/types.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../constants.dart';
import '../features/theme_utils.dart';
import '../features/bookmark_manager.dart';
import '../features/password_prompt.dart';
import '../features/password_storage.dart';
import 'clickable_icon.dart';
import 'browser_navigation_controls.dart';
import '../features/connectivity_service.dart';
import '../features/password_autofill.dart';
import '../features/login_detection.dart';
import '../features/webauthn_script.dart';
import '../features/webauthn_service.dart';
import '../browser_state.dart';
import '../main.dart' show profileManager;
import '../models/tab_data.dart';

import '../assets/page_scripts.dart';
import '../logging/logger.dart';
import '../logging/network_monitor.dart';
import '../utils/string_utils.dart';
import '../utils/keyboard_utils.dart';
import '../utils/url_utils.dart';
import '../utils/favicon_url_policy.dart';
import '../services/favicon_service.dart';
import '../services/history_service.dart';
import '../services/theme_probe_service.dart';
import '../services/fullscreen_service.dart';
import '../services/pointer_events_service.dart';
import '../utils/navigation_resolver.dart';
import '../utils/media_playback_state.dart';
import 'settings_dialog.dart';
import 'browser_address_bar.dart';
import 'package:pkg/ai_chat_widget.dart';
import 'package:pkg/ai_service.dart';
import 'network_debug_dialog.dart';
import 'save_password_prompt.dart';
import 'interaction_blocker.dart';
import 'torry_home_view.dart';
import 'browser_overflow_menu.dart';

export '../features/theme_color_parser.dart';
export '../utils/navigation_resolver.dart';
export '../utils/media_playback_state.dart';

const _userAgents = {
  TargetPlatform.android: {
    'modern':
        'Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36',
    'legacy':
        'Mozilla/5.0 (Linux; Android 10; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
  },
  TargetPlatform.iOS: {
    'modern':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
    'legacy':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
  },
  TargetPlatform.macOS: {
    'modern':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0.2 Safari/605.1.15',
    'legacy':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Safari/605.1.15',
  },
  TargetPlatform.windows: {
    'modern':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
    'legacy':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:91.0) Gecko/20100101 Firefox/91.0',
  },
  TargetPlatform.linux: {
    'modern':
        'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0',
    'legacy':
        'Mozilla/5.0 (X11; Linux x86_64; rv:91.0) Gecko/20100101 Firefox/91.0',
  },
};

String _getUserAgent(bool useLegacy) {
  final platformAgents =
      _userAgents[defaultTargetPlatform] ?? _userAgents[TargetPlatform.macOS]!;
  final agentType = useLegacy ? 'legacy' : 'modern';
  return platformAgents[agentType]!;
}



class _PageFontChoice {
  const _PageFontChoice(this.label, this.cssFamily);

  final String label;
  final String cssFamily;
}

const List<_PageFontChoice> _pageFontChoices = [
  _PageFontChoice('Default (Website)', ''),
  _PageFontChoice('Arial', 'Arial, Helvetica, sans-serif'),
  _PageFontChoice('Georgia', 'Georgia, serif'),
  _PageFontChoice('Times New Roman', '"Times New Roman", Times, serif'),
  _PageFontChoice('Verdana', 'Verdana, Geneva, sans-serif'),
  _PageFontChoice('Trebuchet MS', '"Trebuchet MS", sans-serif'),
  _PageFontChoice('Courier New', '"Courier New", Courier, monospace'),
  _PageFontChoice('Comic Sans MS', '"Comic Sans MS", cursive'),
];

class _FontPickerResult {
  const _FontPickerResult({
    required this.fontFamily,
    required this.applyToCurrentSite,
    this.clearCurrentSiteRule = false,
  });

  final String fontFamily;
  final bool applyToCurrentSite;
  final bool clearCurrentSiteRule;
}


class FocusUrlIntent extends Intent {}

class RefreshIntent extends Intent {}

class GoBackIntent extends Intent {}

class GoForwardIntent extends Intent {}

class NewTabIntent extends Intent {}

class CloseTabIntent extends Intent {}

class NewWindowIntent extends Intent {}

class PageFontIntent extends Intent {}


class BrowserPage extends StatefulWidget {
  const BrowserPage(
      {super.key,
      required this.initialUrl,
      this.hideAppBar = false,
      this.useModernUserAgent = false,
      this.privateBrowsing = false,
      this.adBlocking = false,
      this.strictMode = false,
      this.pageFontFamily = '',
      this.aiSearchSuggestionsEnabled = false,
      this.advancedCacheEnabled = false,
      this.ambientToolbarEnabled = false,
      this.autoHideAddressBarEnabled = false,
      this.urlAutocompleteSuggestionRemovalEnabled = false,
      this.themeMode = AppThemeMode.system,
      this.aiAvailable = true,
      this.onSettingsChanged,
      this.onPageThemeChanged,
      this.onThemePreviewChanged,
      this.onThemePreviewReset,
      this.onShowWhatsNew});

  final String initialUrl;
  final bool hideAppBar;
  final bool useModernUserAgent;
  final bool privateBrowsing;
  final bool adBlocking;
  final bool strictMode;
  final String pageFontFamily;
  final bool aiSearchSuggestionsEnabled;
  final bool advancedCacheEnabled;
  final bool ambientToolbarEnabled;
  final bool autoHideAddressBarEnabled;
  final bool urlAutocompleteSuggestionRemovalEnabled;
  final AppThemeMode themeMode;
  final bool aiAvailable;
  final void Function()? onSettingsChanged;
  final void Function(ThemeMode mode, Color? seedColor)? onPageThemeChanged;
  final void Function(AppThemeMode mode)? onThemePreviewChanged;
  final void Function()? onThemePreviewReset;
  final Future<void> Function()? onShowWhatsNew;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _BrowserPageState extends State<BrowserPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // WebKit cancellation signal seen on Apple platforms.
  static const int _wkErrorCancelled = -999;
  // Chromium aborted navigation code (net::ERR_ABORTED). On Android WebView
  // this may represent real failures (e.g. unsupported auth scheme), so we do
  // not blanket-ignore it.
  static const int _chromiumErrorAborted = -3;

  static const Set<String> _allowedNavigationSchemes = {
    'http',
    'https',
    'about',
    'blob',
    'data',
    'file',
  };

  static const int _urlAutocompleteRecentInteractionWindowMs = 250;
  static const int _urlAutocompleteShowCloseButtonThreshold = 5;
  static const double _urlAutocompleteOverlayOffset = 6;
  static const double _urlAutocompleteOverlayMargin = 12;
  static const double _urlAutocompleteOverlayMinWidth = 0;
  static const double _urlAutocompleteOverlayMaxWidthCap = 720;
  static const double _urlAutocompleteOverlayMinHeight = 0;
  static const double _urlAutocompleteOverlayMaxHeightCap = 240;
  static const double _urlAutocompleteOverlayFlipThreshold = 160;

  late TabController tabController;
  final List<TabData> tabs = [];
  final bookmarkManager = BookmarkManager();
  late int previousTabIndex;
  List<RegExp> adBlockerPatterns = [];
  bool _isOnline = true;
  final ConnectivityService _connectivityService = ConnectivityService();
  final PasswordStorageRepository _passwordRepository =
      PasswordStorageRepository(
    namespaceProvider: () => profileManager.activeProfileId ?? 'default',
  );
  StreamSubscription<bool>? _connectivitySubscription;
  late AnimationController _refreshIconController;
  AnimationController? _ambientController;
  OverlayEntry? _urlAutocompleteOverlayEntry;
  List<String> _urlAutocompleteOptions = const <String>[];
  double? _urlAutocompleteTargetWidth;
  bool _urlAutocompleteOverlayUpdateQueued = false;
  int _lastUrlAutocompleteOverlayPointerDownMs = 0;
  double _urlAutocompleteOverlayMaxWidth = _urlAutocompleteOverlayMaxWidthCap;
  double _urlAutocompleteOverlayMaxHeight = _urlAutocompleteOverlayMaxHeightCap;
  bool _urlAutocompleteShowAbove = false;
  final Set<String> _downloadableExtensions = {
    'dmg',
    'zip',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'xz',
    '7z',
    'rar',
    'exe',
    'msi',
    'pkg',
    'deb',
    'rpm',
    'apk',
    'iso',
    'pdf',
    'csv',
    'json',
    'xml',
    'mp3',
    'mp4',
    'm4a',
    'mov',
    'avi',
    'mkv',
  };
  final Set<String> _pendingHeaderChecks = {};
  bool _dragging = false;
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _reorderableTabs = false;
  String _pageFontFamily = '';
  final Map<String, String> _siteFontFamilies = {};
  static const double _kMacOsLeadingInsetWithTrafficLights = 16.0;
  static const double _kMacOsAddressBarLeftOffset = 60.0;
  static const double _kDefaultLeadingInset = 16.0;
  static const double _kMobileLeadingInset = 12.0;
  static const double _kMacOsTopToolbarInset = 8.0;
  static const String _legacyLayoutFixScriptAsset =
      'assets/legacy_layout_fix.js';

  AiService? _aiService;
  List<String>? _cachedAiSearchSuggestions;
  DateTime? _lastAiSuggestionFetchAt;
  final HistoryService _historyService = HistoryService();
  final MenuController _overflowMenuController = MenuController();
  Timer? _overflowMenuCloseTimer;
  bool _isOverflowTriggerHovered = false;
  bool _isOverflowMenuHovered = false;
  bool _overflowMenuOpen = false;
  final LayerLink _urlAutocompleteLayerLink = LayerLink();
  final GlobalKey _urlAutocompleteTargetKey = GlobalKey();
  bool _urlAutocompleteOpen = false;
  bool _modalInteractionBlockOpen = false;
  bool _quickUrlPromptOpen = false;
  bool _ignoreNextUrlFocusRestore = false;
  Widget? _androidFullscreenWidget;
  VoidCallback? _hideAndroidFullscreenWidget;
  bool _windowButtonsSyncRetryQueued = false;
  Timer? _windowButtonsSyncRetryTimer;
  final FaviconService _faviconService = FaviconService();
  final ThemeProbeService _themeProbeService = ThemeProbeService();
  final FullscreenService _fullscreenService = FullscreenService();
  final PointerEventsService _pointerEventsService = PointerEventsService();
  String? _legacyLayoutFixScript;
  int? _hoveredTabIndex;
  static const Duration _addressBarAutoHideDelay = Duration(seconds: 4);
  Timer? _addressBarAutoHideTimer;
  bool _isAddressBarHovered = false;

  String _displayUrl(String url) => url == defaultHomepageUrl ? '' : url;

  Future<void> _syncMacWindowButtonsVisibility({bool allowRetry = true}) async {
    if (defaultTargetPlatform != TargetPlatform.macOS || isIntegrationTest) {
      return;
    }
    if (!isWindowChromeReady) {
      if (allowRetry && !_windowButtonsSyncRetryQueued) {
        _windowButtonsSyncRetryQueued = true;
        _windowButtonsSyncRetryTimer?.cancel();
        _windowButtonsSyncRetryTimer =
            Timer.periodic(const Duration(milliseconds: 120), (timer) {
          if (!mounted) {
            _windowButtonsSyncRetryQueued = false;
            _windowButtonsSyncRetryTimer = null;
            timer.cancel();
            return;
          }
          if (!isWindowChromeReady) return;
          _windowButtonsSyncRetryQueued = false;
          _windowButtonsSyncRetryTimer = null;
          timer.cancel();
          _syncMacWindowButtonsVisibility(allowRetry: false);
        });
      }
      return;
    }
    _windowButtonsSyncRetryTimer?.cancel();
    _windowButtonsSyncRetryTimer = null;
    _windowButtonsSyncRetryQueued = false;
    try {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: !widget.hideAppBar,
      );
    } catch (e) {
      logger.w('Failed to update macOS window button visibility: $e');
    }
  }

  bool get _hasAmbientColor {
    if (tabs.isEmpty) return false;
    final index = tabController.index;
    if (index < 0 || index >= tabs.length) return false;
    final tab = tabs[index];
    return tab.ambientSeedColor != null || tab.detectedSeedColor != null;
  }

  bool get _ambientActive => widget.ambientToolbarEnabled && _hasAmbientColor;

  // void _syncAmbientAnimation() {
  //   // Disabled - causes hover flicker on macOS
  //   if (_ambientActive) {
  //     _ambientController ??= AnimationController(
  //       vsync: this,
  //       duration: const Duration(seconds: 14),
  //     )..repeat();
  //     return;
  //   }
  //   _ambientController?.dispose();
  //   _ambientController = null;
  // }

  void _syncAmbientAnimation() {
    // Disabled - causes hover flicker on macOS
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncMacWindowButtonsVisibility();
    });
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _refreshIconController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _syncAmbientAnimation();
    _pageFontFamily = widget.pageFontFamily;
    _loadReorderableTabs();
    _faviconService.loadTabFaviconBadgeEnabled(mounted: mounted, setState: setState);
    _loadFontOverrides();
    _historyService.loadNavigationCacheIndex(
      privateBrowsing: widget.privateBrowsing,
      advancedCacheEnabled: widget.advancedCacheEnabled,
      getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
    );
    tabs.add(_createTab(widget.initialUrl));
    tabController = TabController(length: 1, vsync: this);
    previousTabIndex = 0;
    tabController.addListener(_onTabChanged);
    _loadBookmarks();
    _historyService.loadHistory(
      privateBrowsing: widget.privateBrowsing,
      advancedCacheEnabled: widget.advancedCacheEnabled,
      getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
    );
    profileManager.addListener(_onProfileChanged);
    if (widget.adBlocking) {
      loadAdBlockers();
    }
    if (widget.aiAvailable && !isIntegrationTest) {
      _aiService = AiService();
    }
    _initConnectivity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && activeTab.currentUrl == defaultHomepageUrl) {
        activeTab.urlFocusNode.requestFocus();
      }
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Check if ANY text input is focused (including dialog fields)
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isTextInputFocused = primaryFocus != null &&
        primaryFocus.context != null &&
        primaryFocus.context!.widget is EditableText;

    // Check tab switching first (more specific: Cmd+Option+Arrow)
    if (KeyboardUtils.isPreviousTabKey(event)) {
      if (tabController.index > 0) {
        tabController.animateTo(tabController.index - 1);
      }
      return true;
    } else if (KeyboardUtils.isNextTabKey(event)) {
      if (tabController.index < tabs.length - 1) {
        tabController.animateTo(tabController.index + 1);
      }
      return true;
    }

    // Then check back/forward (Cmd+[ and Cmd+])
    if (!isTextInputFocused && KeyboardUtils.isBackKey(event)) {
      _goBack();
      return true;
    } else if (!isTextInputFocused && KeyboardUtils.isForwardKey(event)) {
      _goForward();
      return true;
    }

    if (KeyboardUtils.isNewTabKey(event)) {
      _addNewTab();
      return true;
    } else if (KeyboardUtils.isCloseTabKey(event)) {
      _closeTab(tabController.index);
      return true;
    } else if (KeyboardUtils.isFontPickerKey(event)) {
      _showFontPicker();
      return true;
    } else if (KeyboardUtils.isFocusUrlKey(event)) {
      activeTab.urlFocusNode.requestFocus();
      return true;
    } else if (KeyboardUtils.isEscapeKey(event)) {
      // Check if URL bar is focused
      if (activeTab.urlFocusNode.hasFocus) {
        // Close autocomplete first to avoid overlay disposal issues
        if (_urlAutocompleteOpen) {
          _setUrlAutocompleteOpen(false);
        }
        activeTab.urlFocusNode.unfocus();
        return true;
      }
      // For other text inputs in dialogs, unfocus but let event fall through
      if (isTextInputFocused) {
        FocusScope.of(context).unfocus();
        // Only quick URL prompt should allow Esc to dismiss the route.
        return !_quickUrlPromptOpen;
      }
      if (_androidFullscreenWidget != null) {
        final hideWidget = _hideAndroidFullscreenWidget;
        setState(() {
          _androidFullscreenWidget = null;
          _hideAndroidFullscreenWidget = null;
        });
        hideWidget?.call();
        return true;
      }
      if (activeTab.pageRequestedWindowFullscreen) {
        unawaited(_exitPageFullscreen(activeTab));
        unawaited(_setPageRequestedWindowFullscreen(activeTab, false));
        return true;
      }
      // Exit fullscreen on Esc
      unawaited(_exitFullscreenIfNeeded());
      return false;
    }

    // Window-level shortcuts should work even when text input is focused
    if (KeyboardUtils.isFullscreenKey(event)) {
      if (!_isDesktopPlatform) return false;
      _toggleFullscreen();
      return true;
    } else if (KeyboardUtils.isMinimizeKey(event)) {
      if (!_isDesktopPlatform) return false;
      windowManager.minimize();
      return true;
    }

    if (isTextInputFocused) return false;

    if (KeyboardUtils.isRefreshKey(event)) {
      _refresh();
      return true;
    }

    return false;
  }

  Future<void> _toggleFullscreen() => _fullscreenService.toggleFullscreen();

  Future<void> _exitFullscreenIfNeeded() => _fullscreenService.exitFullscreenIfNeeded();

  Future<void> _setPageRequestedWindowFullscreen(TabData tab, bool enabled) =>
      _fullscreenService.setPageRequestedWindowFullscreen(tab, enabled);

  Future<void> _handlePageFullscreenMessage(TabData tab, String message) =>
      _fullscreenService.handlePageFullscreenMessage(
        tab,
        message,
        activeTab: activeTab,
        mounted: mounted,
      );

  Future<void> _exitPageFullscreen(TabData tab) =>
      _fullscreenService.exitPageFullscreen(tab);

  Future<void> _installFullscreenBridge(TabData tab) =>
      _fullscreenService.installFullscreenBridge(tab);

  Future<void> _configurePlatformSpecificWebView(TabData tab) async {
    final controller = tab.webViewController;
    if (controller == null) return;

    await controller.setOnJavaScriptAlertDialog((request) async {
      if (!mounted || tab.isClosed) return;
      await _showWithModalInteractionBlock<void>(
        () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title:
                Text(_javaScriptDialogTitle(request.url, fallback: 'Message')),
            content: Text(request.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    });

    await controller.setOnJavaScriptConfirmDialog((request) async {
      if (!mounted || tab.isClosed) return false;
      final confirmed = await _showWithModalInteractionBlock<bool>(
        () => showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title:
                Text(_javaScriptDialogTitle(request.url, fallback: 'Confirm')),
            content: Text(request.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      return confirmed ?? false;
    });

    await controller.setOnJavaScriptTextInputDialog((request) async {
      if (!mounted || tab.isClosed) return request.defaultText ?? '';
      final textController =
          TextEditingController(text: request.defaultText ?? '');
      try {
        final response = await _showWithModalInteractionBlock<String>(
          () => showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title:
                  Text(_javaScriptDialogTitle(request.url, fallback: 'Input')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (request.message.trim().isNotEmpty) ...[
                    Text(request.message),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: textController,
                    autofocus: true,
                    onSubmitted: (value) {
                      Navigator.of(dialogContext).pop(value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(textController.text),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
        return response ?? '';
      } finally {
        textController.dispose();
      }
    });

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      await androidController.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget widget, VoidCallback onHidden) {
          if (!mounted) {
            onHidden();
            return;
          }
          setState(() {
            _androidFullscreenWidget = widget;
            _hideAndroidFullscreenWidget = onHidden;
          });
        },
        onHideCustomWidget: () {
          if (!mounted) return;
          setState(() {
            _androidFullscreenWidget = null;
            _hideAndroidFullscreenWidget = null;
          });
        },
      );
    }

    await _installFullscreenBridge(tab);
  }

  String _javaScriptDialogTitle(String sourceUrl, {required String fallback}) {
    final host = Uri.tryParse(sourceUrl)?.host.trim();
    if (host == null || host.isEmpty) {
      return fallback;
    }
    final compactHost = host.startsWith('www.') ? host.substring(4) : host;
    return '$compactHost says';
  }

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool _isValidHistoryUrl(String url) => _historyService.isValidHistoryUrl(url);

  void _initConnectivity() async {
    _isOnline = await _connectivityService.checkConnectivity();
    if (mounted) {
      setState(() {}); // Update UI with initial state
    }

    _connectivitySubscription =
        _connectivityService.onConnectivityChanged.listen((isOnline) {
      if (mounted && _isOnline != isOnline) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  TabData _createTab(String initialUrl) {
    final tab = TabData(initialUrl, displayUrl: _displayUrl(initialUrl));
    tab.urlFocusNode.addListener(() => _onUrlFocusChanged(tab));
    tab.urlController.addListener(() => _onUrlTextChanged(tab));
    return tab;
  }

  void _onUrlFocusChanged(TabData tab) {
    if (!mounted || tab.isClosed) return;
    if (!identical(tab, activeTab)) return;
    if (!tab.urlFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || tab.isClosed) return;
        if (tab.urlFocusNode.hasFocus) return;
        if (_ignoreNextUrlFocusRestore) {
          _ignoreNextUrlFocusRestore = false;
          return;
        }
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final interactedWithOverlayRecently =
            _urlAutocompleteOverlayEntry != null &&
                nowMs - _lastUrlAutocompleteOverlayPointerDownMs <
                    _urlAutocompleteRecentInteractionWindowMs;
        if (interactedWithOverlayRecently) {
          tab.urlFocusNode.requestFocus();
          return;
        }
        _removeUrlAutocompleteOverlay();
      });
      _syncPagePointerEvents(tab);
      _maybeScheduleAddressBarAutoHide(tab);
      return;
    }
    _cancelAddressBarAutoHide();
    _setActiveTabUrlObscured(false);
    _updateUrlAutocompleteOverlay(tab);
    _syncPagePointerEvents(tab);
  }

  void _onUrlTextChanged(TabData tab) {
    if (!mounted || tab.isClosed) return;
    if (!identical(tab, activeTab)) return;
    if (!tab.urlFocusNode.hasFocus) return;
    _updateUrlAutocompleteOverlay(tab);
  }

  void _selectUrlAutocompleteOption(String value) {
    _ignoreNextUrlFocusRestore = true;
    activeTab.urlFocusNode.unfocus();
    _removeUrlAutocompleteOverlay();
    _loadUrl(value);
  }

  void _removeUrlAutocompleteSuggestion(String value) {
    final normalized = _historyService.normalizeKey(value);
    _historyService.removeUrl(value);
    for (final tab in tabs) {
      tab.history
          .removeWhere((entry) => _historyService.normalizeKey(entry) == normalized);
    }

    _urlAutocompleteOptions =
        _historyService.urlSuggestions(activeTab.urlController.text)
            .toList(growable: false);

    unawaited(_historyService.saveHistory(privateBrowsing: widget.privateBrowsing));

    if (_urlAutocompleteOptions.isEmpty) {
      _removeUrlAutocompleteOverlay();
      return;
    }
    _urlAutocompleteOverlayEntry?.markNeedsBuild();
  }

  void _removeUrlAutocompleteOverlay({bool updatePointerEvents = true}) {
    _urlAutocompleteOptions = const <String>[];
    if (_urlAutocompleteOverlayEntry == null) {
      if (updatePointerEvents) {
        _setUrlAutocompleteOpen(false);
      } else {
        _urlAutocompleteOpen = false;
      }
      return;
    }
    _urlAutocompleteOverlayEntry?.remove();
    _urlAutocompleteOverlayEntry = null;
    if (updatePointerEvents) {
      _setUrlAutocompleteOpen(false);
    } else {
      _urlAutocompleteOpen = false;
    }
  }

  void _updateUrlAutocompleteOverlay(TabData tab) {
    if (_urlAutocompleteOverlayUpdateQueued) return;
    _urlAutocompleteOverlayUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _urlAutocompleteOverlayUpdateQueued = false;
      if (!mounted || tab.isClosed || !identical(tab, activeTab)) return;
      if (!tab.urlFocusNode.hasFocus) {
        _removeUrlAutocompleteOverlay();
        return;
      }
      final targetBox =
          _urlAutocompleteTargetKey.currentContext?.findRenderObject();
      if (targetBox is RenderBox && targetBox.hasSize) {
        _urlAutocompleteTargetWidth = targetBox.size.width;
        final overlayBox =
            Overlay.of(context, rootOverlay: true).context.findRenderObject();
        if (overlayBox is RenderBox && overlayBox.hasSize) {
          final overlayTopLeft = overlayBox.localToGlobal(Offset.zero);
          final targetTopLeft = targetBox.localToGlobal(Offset.zero);
          final dx = targetTopLeft.dx - overlayTopLeft.dx;
          final dy = targetTopLeft.dy - overlayTopLeft.dy;
          const minMargin = _urlAutocompleteOverlayMargin;
          final spaceBelow = overlayBox.size.height -
              (dy + targetBox.size.height + _urlAutocompleteOverlayOffset) -
              minMargin;
          final spaceAbove = dy - minMargin;
          final showAbove = spaceBelow < _urlAutocompleteOverlayFlipThreshold &&
              spaceAbove > spaceBelow;
          _urlAutocompleteShowAbove = showAbove;
          _urlAutocompleteOverlayMaxWidth =
              (overlayBox.size.width - dx - minMargin).clamp(
                  _urlAutocompleteOverlayMinWidth,
                  _urlAutocompleteOverlayMaxWidthCap);
          final maxHeight = (showAbove ? spaceAbove : spaceBelow)
              .clamp(_urlAutocompleteOverlayMinHeight,
                  _urlAutocompleteOverlayMaxHeightCap)
              .toDouble();
          _urlAutocompleteOverlayMaxHeight = maxHeight;
        }
      }
      final options = _historyService.urlSuggestions(tab.urlController.text)
          .toList(growable: false);
      if (options.isEmpty) {
        _removeUrlAutocompleteOverlay();
        return;
      }
      _urlAutocompleteOptions = options;
      _setUrlAutocompleteOpen(true);

      if (_urlAutocompleteOverlayEntry == null) {
        _urlAutocompleteOverlayEntry = OverlayEntry(
          builder: (overlayContext) {
            final theme = Theme.of(overlayContext);
            final optionList = _urlAutocompleteOptions;
            final suggestionRemovalEnabled =
                widget.urlAutocompleteSuggestionRemovalEnabled;
            if (optionList.isEmpty) {
              return const SizedBox.shrink();
            }
            final maxWidth = _urlAutocompleteOverlayMaxWidth;
            final minWidth = (_urlAutocompleteTargetWidth ?? 300.0)
                .clamp(_urlAutocompleteOverlayMinWidth, maxWidth)
                .toDouble();
            final overlayContent = Material(
              elevation: 6,
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _urlAutocompleteOverlayMaxHeight,
                  minWidth: minWidth,
                  maxWidth: maxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (suggestionRemovalEnabled &&
                        optionList.length >=
                            _urlAutocompleteShowCloseButtonThreshold)
                      SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            iconSize: 18,
                            splashRadius: 18,
                            onPressed: _removeUrlAutocompleteOverlay,
                            icon: const Icon(
                              Icons.close,
                              semanticLabel: 'Close suggestions',
                            ),
                          ),
                        ),
                      ),
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        itemCount: optionList.length,
                        itemBuilder: (context, index) {
                          final option = optionList[index];
                          final suggestionWidget = InkWell(
                            onTap: () => _selectUrlAutocompleteOption(option),
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                option,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: suggestionRemovalEnabled
                                ? Row(
                                    children: [
                                      Expanded(child: suggestionWidget),
                                      const SizedBox(width: 8),
                                      Semantics(
                                        button: true,
                                        label: 'Remove from history',
                                        child: IconButton(
                                          iconSize: 18,
                                          splashRadius: 18,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                            width: 32,
                                            height: 32,
                                          ),
                                          onPressed: () =>
                                              _removeUrlAutocompleteSuggestion(
                                                  option),
                                          icon: Icon(
                                            Icons.remove_circle_outline,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : suggestionWidget,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
            return Stack(
              children: [
                InteractionBlocker(
                  onTap: () {
                    activeTab.urlFocusNode.unfocus();
                    _removeUrlAutocompleteOverlay();
                  },
                ),
                CompositedTransformFollower(
                  link: _urlAutocompleteLayerLink,
                  showWhenUnlinked: false,
                  targetAnchor: _urlAutocompleteShowAbove
                      ? Alignment.topLeft
                      : Alignment.bottomLeft,
                  followerAnchor: _urlAutocompleteShowAbove
                      ? Alignment.bottomLeft
                      : Alignment.topLeft,
                  offset: Offset(
                    0,
                    _urlAutocompleteShowAbove
                        ? -_urlAutocompleteOverlayOffset
                        : _urlAutocompleteOverlayOffset,
                  ),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _lastUrlAutocompleteOverlayPointerDownMs =
                          DateTime.now().millisecondsSinceEpoch;
                    },
                    child: overlayContent,
                  ),
                ),
              ],
            );
          },
        );
        Overlay.of(context, rootOverlay: true)
            .insert(_urlAutocompleteOverlayEntry!);
      } else {
        _urlAutocompleteOverlayEntry?.markNeedsBuild();
      }
    });
  }

  void _setUrlAutocompleteOpen(bool open) {
    if (_urlAutocompleteOpen == open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _urlAutocompleteOpen == open) return;
      setState(() => _urlAutocompleteOpen = open);
      _syncPointerEventsForAllTabs();
    });
  }

  void _setModalInteractionBlockOpen(bool open) {
    if (_modalInteractionBlockOpen == open) return;
    if (mounted) {
      setState(() {
        _modalInteractionBlockOpen = open;
      });
    } else {
      _modalInteractionBlockOpen = open;
    }
    _syncPointerEventsForAllTabs();
  }

  void _setOverflowMenuOpen(bool open) {
    if (_overflowMenuOpen == open) return;
    _overflowMenuOpen = open;
    _syncPointerEventsForAllTabs();
  }

  void _syncPointerEventsForAllTabs() {
    _pointerEventsService.syncPointerEventsForAllTabs(
      tabs,
      activeTab: activeTab,
      urlAutocompleteOpen: _urlAutocompleteOpen,
      modalInteractionBlockOpen: _modalInteractionBlockOpen,
      overflowMenuOpen: _overflowMenuOpen,
    );
  }

  Future<T?> _showWithModalInteractionBlock<T>(
      Future<T?> Function() showModal) async {
    _setModalInteractionBlockOpen(true);
    try {
      return await showModal();
    } finally {
      _setModalInteractionBlockOpen(false);
    }
  }

  void _syncPagePointerEvents(TabData tab) {
    _pointerEventsService.syncPagePointerEvents(
      tab,
      activeTab: activeTab,
      urlAutocompleteOpen: _urlAutocompleteOpen,
      modalInteractionBlockOpen: _modalInteractionBlockOpen,
      overflowMenuOpen: _overflowMenuOpen,
    );
  }

  @override
  void didUpdateWidget(covariant BrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl) {
      _syncHomeUrlChange(oldWidget.initialUrl, widget.initialUrl);
    }
    if (oldWidget.hideAppBar != widget.hideAppBar) {
      _syncMacWindowButtonsVisibility();
    }
    if (oldWidget.ambientToolbarEnabled != widget.ambientToolbarEnabled ||
        oldWidget.hideAppBar != widget.hideAppBar) {
      _syncAmbientAnimation();
    }
    if (oldWidget.ambientToolbarEnabled != widget.ambientToolbarEnabled) {
      _resetAmbientProbeState();
      if (widget.ambientToolbarEnabled) {
        _updateAmbientFromTab(activeTab);
      }
    }
    if (oldWidget.pageFontFamily != widget.pageFontFamily) {
      _pageFontFamily = widget.pageFontFamily;
      _applyFontOverrideToAllTabs();
    }
    if (oldWidget.advancedCacheEnabled != widget.advancedCacheEnabled &&
        widget.advancedCacheEnabled) {
      _historyService.prewarmNavigationCache(
        getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
      );
    }
    if (oldWidget.useModernUserAgent != widget.useModernUserAgent) {
      _applyUserAgentToAllTabs();
    }
    if (oldWidget.themeMode != widget.themeMode) {
      if (widget.themeMode == AppThemeMode.adjust) {
        _applyThemeForTab(activeTab);
      } else {
        widget.onPageThemeChanged?.call(ThemeMode.system, null);
      }
    }
    if (oldWidget.privateBrowsing && !widget.privateBrowsing) {
      _loadBookmarks();
      _historyService.loadHistory(
        privateBrowsing: widget.privateBrowsing,
        advancedCacheEnabled: widget.advancedCacheEnabled,
        getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
      );
    }
    if (!oldWidget.privateBrowsing && widget.privateBrowsing) {
      bookmarkManager.clear();
      _historyService.clearAll();
    }
    if (oldWidget.autoHideAddressBarEnabled !=
        widget.autoHideAddressBarEnabled) {
      if (!widget.autoHideAddressBarEnabled) {
        _cancelAddressBarAutoHide();
        _setActiveTabUrlObscured(false);
      } else {
        _maybeScheduleAddressBarAutoHide(activeTab, revealImmediately: true);
      }
    }
  }

  void _syncHomeUrlChange(String oldHomeUrl, String newHomeUrl) {
    if (!mounted) return;

    var changed = false;
    for (final tab in tabs) {
      if (tab.currentUrl == oldHomeUrl) {
        changed = true;
        tab.currentUrl = newHomeUrl;
        tab.pageTitle = null;
        tab.urlController.value = TextEditingValue(
          text: _displayUrl(newHomeUrl),
          selection: TextSelection.collapsed(
            offset: _displayUrl(newHomeUrl).length,
          ),
        );
        tab.faviconUrl = _faviconService.defaultFaviconUrlFor(newHomeUrl);
        tab.state = BrowserState.success(newHomeUrl);
        if (newHomeUrl == defaultHomepageUrl) {
          tab.webViewController = null;
          tab.hideStaleWebViewUntilPageFinish = false;
        }
      }
      if (tab.forwardUrl == oldHomeUrl) {
        changed = true;
        tab.forwardUrl = newHomeUrl;
      }
    }

    if (changed) {
      setState(() {});
    }
  }

  Future<void> _applyUserAgentToAllTabs() async {
    final userAgent = _getUserAgent(widget.useModernUserAgent);
    for (final tab in tabs) {
      final controller = tab.webViewController;
      if (controller == null) continue;
      try {
        await controller.setUserAgent(userAgent);
        await controller.reload();
      } on PlatformException catch (e, s) {
        if (!_isMissingPluginException(e)) {
          logger.w('Unexpected PlatformException on user-agent update',
              error: e, stackTrace: s);
        }
      }
    }
  }

  Future<void> _loadInitialRequestForTab(TabData tab) async {
    final controller = tab.webViewController;
    if (controller == null) return;
    try {
      await controller.setUserAgent(_getUserAgent(widget.useModernUserAgent));
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on setUserAgent',
            error: e, stackTrace: s);
      }
    }

    try {
      await controller.loadRequest(Uri.parse(tab.currentUrl));
    } on FormatException {
      logger.w('Invalid URL: ${tab.currentUrl}');
      _handleLoadError(tab, 'Invalid URL format');
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on initial loadRequest',
            error: e, stackTrace: s);
      }
    }
  }

  bool _isMissingPluginException(PlatformException e) {
    return e.code == 'MissingPluginException';
  }

  bool _isLiveTab(TabData tab) {
    return mounted && !tab.isClosed && tabs.contains(tab);
  }

  void _applyThemeForTab(TabData tab) {
    if (widget.themeMode != AppThemeMode.adjust) return;
    if (tab.currentUrl == defaultHomepageUrl || tab.state is BrowserError) {
      widget.onPageThemeChanged?.call(ThemeMode.system, null);
      return;
    }
    if (tab.detectedBrightness != null) {
      widget.onPageThemeChanged?.call(
        tab.detectedBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        tab.detectedSeedColor,
      );
      return;
    }
    _updateThemeFromTab(tab);
  }

  Future<void> _updateThemeFromTab(TabData tab) async {
    await _themeProbeService.updateThemeFromTab(
      tab,
      themeMode: widget.themeMode,
      strictMode: widget.strictMode,
      onPageThemeChanged: widget.onPageThemeChanged,
      mounted: mounted,
      setState: setState,
    );
  }

  Future<void> _updateAmbientFromTab(TabData tab) async {
    await _themeProbeService.updateAmbientFromTab(
      tab,
      ambientToolbarEnabled: widget.ambientToolbarEnabled,
      strictMode: widget.strictMode,
      activeTab: activeTab,
      mounted: mounted,
      setState: setState,
    );
  }

  void _resetAmbientProbeState() {
    _themeProbeService.resetAmbientProbeState(
      tabs,
      mounted: mounted,
      setState: setState,
    );
  }

  Future<void> _applyFontOverride(TabData tab) async {
    if (widget.strictMode) return;
    final controller = tab.webViewController;
    if (controller == null) return;
    final normalizedFont = _resolveFontForTab(tab).trim();
    try {
      if (normalizedFont.isEmpty) {
        await controller.runJavaScript(removeFontOverrideScript);
        return;
      }
      await controller.runJavaScript(buildFontOverrideScript(normalizedFont));
    } catch (e, s) {
      logger.w('Failed to apply page font override', error: e, stackTrace: s);
    }
  }

  Future<void> _clearUnwantedInitialPageFocus(TabData tab) async {
    if (widget.strictMode) return;
    if (await _isPageUserInteracted(tab)) return;
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return;
    try {
      await controller.runJavaScript(clearInitialFocusScript);
    } catch (e, s) {
      quietLogger.w(
        'Failed to clear initial page focus',
        error: e,
        stackTrace: s,
      );
    }
  }

  bool _parseJsBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = FaviconUrlPolicy.normalizeJsResult(value).trim().toLowerCase();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw == '1') return true;
    if (raw == '0') return false;
    return false;
  }

  Future<bool> _isPageUserInteracted(TabData tab) async {
    if (tab.hasUserInteractedWithPage) return true;
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return false;
    try {
      final result = await controller.runJavaScriptReturningResult(isPageUserInteractedScript);
      final interacted = _parseJsBool(result);
      if (interacted) {
        tab.hasUserInteractedWithPage = true;
      }
      return interacted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _installInitialFocusInterceptor(TabData tab) async {
    if (widget.strictMode) return;
    if (await _isPageUserInteracted(tab)) return;
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return;
    try {
      await controller.runJavaScript(installInitialFocusInterceptorScript);
    } catch (e, s) {
      quietLogger.w(
        'Failed to install initial focus interceptor',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _ensurePageTapListenerInstalled(TabData tab) async {
    if (widget.strictMode) return;
    if (await _isPageUserInteracted(tab)) return;
    final controller = tab.webViewController;
    if (controller == null || tab.isClosed) return;
    try {
      await controller.runJavaScript(ensurePageTapListenerScript);
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<String?> _loadLegacyLayoutFixScript() async {
    if (_legacyLayoutFixScript != null) {
      return _legacyLayoutFixScript;
    }
    try {
      _legacyLayoutFixScript =
          await rootBundle.loadString(_legacyLayoutFixScriptAsset);
      return _legacyLayoutFixScript;
    } catch (e, s) {
      logger.w('Failed to load legacy layout fix script',
          error: e, stackTrace: s);
      return null;
    }
  }

  Future<void> _applyLegacyLayoutFix(TabData tab) async {
    if (!widget.useModernUserAgent || widget.strictMode) return;
    final controller = tab.webViewController;
    if (controller == null) return;
    final script = await _loadLegacyLayoutFixScript();
    if (script == null || script.trim().isEmpty) return;
    try {
      await controller.runJavaScript(script);
    } catch (e, s) {
      logger.w('Failed to apply legacy layout fix', error: e, stackTrace: s);
    }
  }

  Future<void> _applyFontOverrideToAllTabs() async {
    for (final tab in tabs) {
      await _applyFontOverride(tab);
    }
  }

  String _resolveFontForTab(TabData tab) {
    final host = _faviconService.hostFromUrl(tab.currentUrl);
    if (host != null && _siteFontFamilies.containsKey(host)) {
      return _siteFontFamilies[host] ?? '';
    }
    return _pageFontFamily;
  }

  Future<void> _loadFontOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final rawOverrides = prefs
        .getString(profileManager.getScopedStorageKey(pageFontOverridesKey));
    if (rawOverrides == null || rawOverrides.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(rawOverrides);
      if (decoded is! Map<String, dynamic>) return;
      _siteFontFamilies
        ..clear()
        ..addEntries(
          decoded.entries.where((entry) => entry.key.trim().isNotEmpty).map(
              (entry) => MapEntry(entry.key.toLowerCase(), '${entry.value}')),
        );
      await _applyFontOverrideToAllTabs();
    } catch (e, s) {
      logger.w('Failed to load font overrides', error: e, stackTrace: s);
    }
  }

  Future<void> _persistFontOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      profileManager.getScopedStorageKey(pageFontOverridesKey),
      jsonEncode(_siteFontFamilies),
    );
  }

  Future<void> loadAdBlockers() async {
    try {
      final jsonString = await rootBundle.loadString('assets/ad_blockers.json');
      final List<dynamic> rules = jsonDecode(jsonString);
      adBlockerPatterns =
          rules.map((rule) => RegExp(rule['urlFilter'])).toList();
    } catch (e) {
      logger.w('Failed to load or compile ad blockers: $e');
    }
  }

  void _onTabChanged() {
    final oldIndex = previousTabIndex;
    _removeUrlAutocompleteOverlay();
    if (oldIndex != tabController.index &&
        oldIndex >= 0 &&
        oldIndex < tabs.length) {
      final previousTab = tabs[oldIndex];
      if (previousTab.pageRequestedWindowFullscreen) {
        unawaited(_exitPageFullscreen(previousTab));
        unawaited(_setPageRequestedWindowFullscreen(previousTab, false));
      }
    }
    previousTabIndex = tabController.index;
    _syncPointerEventsForAllTabs();
    _applyThemeForTab(tabs[tabController.index]);
    _updateAmbientFromTab(tabs[tabController.index]);
    _setActiveTabUrlObscured(false);
    _maybeScheduleAddressBarAutoHide(activeTab, revealImmediately: true);
    if (activeTab.currentUrl == defaultHomepageUrl) {
      activeTab.urlFocusNode.requestFocus();
    }
    if (mounted) {
      setState(() {});
    }
  }

  TabData get activeTab => tabs[tabController.index];

  void _cancelAddressBarAutoHide() {
    _addressBarAutoHideTimer?.cancel();
    _addressBarAutoHideTimer = null;
  }

  bool _shouldAutoHideAddressBar(TabData tab) {
    if (!widget.autoHideAddressBarEnabled) return false;
    if (!_isDesktopPlatform) return false;
    if (widget.hideAppBar) return false;
    if (_isAddressBarHovered) return false;
    if (tab.urlFocusNode.hasFocus) return false;
    if (_urlAutocompleteOpen) return false;
    if (_quickUrlPromptOpen) return false;
    if (tab.currentUrl == defaultHomepageUrl) return false;
    if (tab.state is BrowserError) return false;
    return true;
  }

  void _setActiveTabUrlObscured(bool obscured) {
    final tab = activeTab;
    if (tab.isUrlObscured == obscured) return;
    if (obscured) {
      _removeUrlAutocompleteOverlay();
      tab.urlFocusNode.unfocus();
    }
    if (!mounted) {
      tab.isUrlObscured = obscured;
      return;
    }
    setState(() {
      tab.isUrlObscured = obscured;
    });
  }

  void _maybeScheduleAddressBarAutoHide(
    TabData tab, {
    bool revealImmediately = false,
  }) {
    if (!mounted) return;
    if (!_isDesktopPlatform) return;
    if (!identical(tab, activeTab)) return;

    _cancelAddressBarAutoHide();
    if (revealImmediately) {
      _setActiveTabUrlObscured(false);
    }
    if (!_shouldAutoHideAddressBar(tab)) return;

    final scheduledIndex = tabController.index;
    _addressBarAutoHideTimer = Timer(_addressBarAutoHideDelay, () {
      if (!mounted) return;
      if (tab.isClosed) return;
      if (tabController.index != scheduledIndex) return;
      if (!identical(tab, activeTab)) return;
      if (!_shouldAutoHideAddressBar(tab)) return;
      _setActiveTabUrlObscured(true);
    });
  }

  void _handleAddressBarHoverChanged(bool hovered) {
    if (!_isDesktopPlatform) return;
    if (_isAddressBarHovered == hovered) return;
    _isAddressBarHovered = hovered;
    if (!mounted) return;
    if (hovered) {
      _cancelAddressBarAutoHide();
      _setActiveTabUrlObscured(false);
      return;
    }
    _maybeScheduleAddressBarAutoHide(activeTab);
  }

  Future<void> _handlePasswordPromptAction(SavePasswordAction action) async {
    final promptData = activeTab.pendingPasswordPrompt;
    if (promptData == null) return;

    setState(() {
      activeTab.pendingPasswordPrompt = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final policy = SitePasswordPolicy(prefs: prefs);

    switch (action) {
      case SavePasswordAction.save:
        try {
          final repository = PasswordStorageRepository(
            namespaceProvider: () =>
                profileManager.activeProfileId ?? 'default',
          );
          final credential = PasswordCredential.create(
            origin: promptData.origin,
            username: promptData.username,
            password: promptData.password,
          );
          await repository.saveCredential(credential);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password saved')),
          );
        } catch (e, s) {
          logger.e('Failed to save password', error: e, stackTrace: s);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password could not be saved on this build'),
            ),
          );
        }
        break;
      case SavePasswordAction.neverForSite:
        await policy.setNeverSave(promptData.origin);
        break;
      case SavePasswordAction.notNow:
        // Do nothing, just dismiss
        break;
    }
  }

  Future<void> _attemptAutofill(TabData tab) async {
    if (widget.privateBrowsing) return;

    final prefs = await SharedPreferences.getInstance();
    final passwordManagerEnabled = prefs.getBool(
          profileManager.getScopedStorageKey(passwordManagerEnabledKey),
        ) ??
        false;
    if (!passwordManagerEnabled) return;

    try {
      // Get actual URL from WebView controller, not tab.currentUrl (can be spoofed)
      if (tab.webViewController == null || tab.isClosed) return;
      final actualUrl = await tab.webViewController!.currentUrl();
      if (actualUrl == null) return;

      final autofillService = PasswordAutofillService(
        repository: PasswordStorageRepository(
          namespaceProvider: () => profileManager.activeProfileId ?? 'default',
        ),
      );
      final matches = await autofillService.getMatchingCredentials(actualUrl);

      if (matches.isEmpty) return;

      // Use the most recently updated credential
      final credential = matches.first;
      final script = autofillService.generateAutofillScript(
        credential.username,
        credential.password,
      );

      await tab.webViewController!.runJavaScript(script);
    } catch (e, s) {
      logger.w('Failed to autofill credentials', error: e, stackTrace: s);
    }
  }

  Future<void> _handleWebAuthnMessage(TabData tab, String message) async {
    String? type;
    int? requestId;
    try {
      // Skip status messages - they're internal initialization noise
      if (!message.startsWith('{')) {
        return;
      }

      final data = jsonDecode(message) as Map<String, dynamic>;
      type = data['type'] as String;
      requestId = data['requestId'] as int;
      final options = data['options'] as Map<String, dynamic>;

      final webAuthnService = WebAuthnService();

      if (type == 'create') {
        await _handleWebAuthnCreate(tab, requestId, options, webAuthnService);
      } else if (type == 'get') {
        await _handleWebAuthnGet(tab, requestId, options, webAuthnService);
      } else {
        // Unknown type - reject to prevent hanging
        throw Exception('Unknown WebAuthn request type: $type');
      }
    } catch (e, s) {
      logger.e('Failed to handle WebAuthn message', error: e, stackTrace: s);

      if (requestId != null && tab.webViewController != null) {
        final errorMsg = jsonEncode(e.toString());
        await tab.webViewController!.runJavaScript('''
          if (window.resolveWebAuthnRequest) {
            window.resolveWebAuthnRequest($requestId, false, $errorMsg);
          }
          true;
        ''');
      }
    }
  }

  Future<void> _handleWebAuthnCreate(
    TabData tab,
    int requestId,
    Map<String, dynamic> options,
    WebAuthnService service,
  ) async {
    try {
      // Validate RP ID against page origin
      final pageUrl = await tab.webViewController?.currentUrl();
      if (pageUrl == null) {
        throw Exception('Cannot determine page origin');
      }
      final pageOrigin = Uri.parse(pageUrl);
      final rpId = options['rp']['id'] as String;

      if (!_isValidRpId(rpId, pageOrigin.host)) {
        throw Exception(
            'RP ID validation failed: $rpId does not match origin ${pageOrigin.host}');
      }

      final challenge = _base64UrlEncode(List<int>.from(options['challenge']));
      final rp = options['rp'] as Map<String, dynamic>;
      final user = options['user'] as Map<String, dynamic>;
      final userId = _base64UrlEncode(List<int>.from(user['id']));

      final request = RegisterRequestType(
        challenge: challenge,
        relyingParty: RelyingPartyType(
          name: rp['name'] as String,
          id: rp['id'] as String,
        ),
        user: UserType(
          name: user['name'] as String,
          id: userId,
          displayName: user['displayName'] as String,
        ),
        excludeCredentials: const [],
      );

      final response = await service.register(request);

      if (response != null && tab.webViewController != null) {
        // Decode base64url strings to bytes
        final rawIdBytes = base64Url.decode(response.rawId.padRight(
            response.rawId.length + (4 - response.rawId.length % 4) % 4, '='));
        final clientDataBytes = base64Url.decode(response.clientDataJSON
            .padRight(
                response.clientDataJSON.length +
                    (4 - response.clientDataJSON.length % 4) % 4,
                '='));
        final attestationBytes = base64Url.decode(response.attestationObject
            .padRight(
                response.attestationObject.length +
                    (4 - response.attestationObject.length % 4) % 4,
                '='));

        final jsResponse = '''
          {
            id: '${response.id}',
            rawId: new Uint8Array([${rawIdBytes.join(',')}]),
            response: {
              clientDataJSON: new Uint8Array([${clientDataBytes.join(',')}]),
              attestationObject: new Uint8Array([${attestationBytes.join(',')}])
            },
            type: 'public-key'
          }
        ''';

        await tab.webViewController!.runJavaScript('''
          if (window.resolveWebAuthnRequest) {
            window.resolveWebAuthnRequest($requestId, true, $jsResponse);
          }
          true;
        ''');
      } else {
        await _rejectWebAuthnRequest(
            tab, requestId, 'User cancelled or error occurred');
      }
    } catch (e, s) {
      logger.e('WebAuthn create failed', error: e, stackTrace: s);
      await _rejectWebAuthnRequest(tab, requestId, e.toString());
    }
  }

  Future<void> _handleWebAuthnGet(
    TabData tab,
    int requestId,
    Map<String, dynamic> options,
    WebAuthnService service,
  ) async {
    try {
      // Validate RP ID against page origin
      final pageUrl = await tab.webViewController?.currentUrl();
      if (pageUrl == null) {
        throw Exception('Cannot determine page origin');
      }
      final pageOrigin = Uri.parse(pageUrl);
      final rpId = options['rpId'] as String;

      if (!_isValidRpId(rpId, pageOrigin.host)) {
        throw Exception(
            'RP ID validation failed: $rpId does not match origin ${pageOrigin.host}');
      }

      final challenge = _base64UrlEncode(List<int>.from(options['challenge']));

      final allowCredentials = options['allowCredentials'] as List<dynamic>?;
      final credentials = allowCredentials?.map((c) {
        final id = List<int>.from(c['id']);
        return CredentialType(
          id: _base64UrlEncode(id),
          type: c['type'] as String? ?? 'public-key',
          transports: const [],
        );
      }).toList();

      final request = AuthenticateRequestType(
        challenge: challenge,
        relyingPartyId: rpId,
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: true,
        allowCredentials: credentials,
      );

      final response = await service.authenticate(request);

      if (response != null && tab.webViewController != null) {
        // Decode base64url strings to bytes
        final rawIdBytes = base64Url.decode(response.rawId.padRight(
            response.rawId.length + (4 - response.rawId.length % 4) % 4, '='));
        final clientDataBytes = base64Url.decode(response.clientDataJSON
            .padRight(
                response.clientDataJSON.length +
                    (4 - response.clientDataJSON.length % 4) % 4,
                '='));
        final authDataBytes = base64Url.decode(response.authenticatorData
            .padRight(
                response.authenticatorData.length +
                    (4 - response.authenticatorData.length % 4) % 4,
                '='));
        final signatureBytes = base64Url.decode(response.signature.padRight(
            response.signature.length + (4 - response.signature.length % 4) % 4,
            '='));

        final userHandleBytes = response.userHandle.isNotEmpty
            ? base64Url.decode(response.userHandle.padRight(
                response.userHandle.length +
                    (4 - response.userHandle.length % 4) % 4,
                '='))
            : null;

        final jsResponse = '''
          {
            id: '${response.id}',
            rawId: new Uint8Array([${rawIdBytes.join(',')}]),
            response: {
              clientDataJSON: new Uint8Array([${clientDataBytes.join(',')}]),
              authenticatorData: new Uint8Array([${authDataBytes.join(',')}]),
              signature: new Uint8Array([${signatureBytes.join(',')}]),
              userHandle: ${userHandleBytes != null ? "new Uint8Array([${userHandleBytes.join(',')}])" : 'null'}
            },
            type: 'public-key'
          }
        ''';

        await tab.webViewController!.runJavaScript('''
          if (window.resolveWebAuthnRequest) {
            window.resolveWebAuthnRequest($requestId, true, $jsResponse);
          }
          true;
        ''');
      } else {
        await _rejectWebAuthnRequest(
            tab, requestId, 'User cancelled or error occurred');
      }
    } catch (e, s) {
      logger.e('WebAuthn get failed', error: e, stackTrace: s);
      await _rejectWebAuthnRequest(tab, requestId, e.toString());
    }
  }

  Future<void> _rejectWebAuthnRequest(
      TabData tab, int requestId, String error) async {
    if (tab.webViewController == null) return;

    final errorMsg = jsonEncode(error);
    await tab.webViewController!.runJavaScript('''
      if (window.resolveWebAuthnRequest) {
        window.resolveWebAuthnRequest($requestId, false, $errorMsg);
      }
      true;
    ''');
  }

  String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  bool _isAllowedNavigationUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return _allowedNavigationSchemes.contains(uri.scheme.toLowerCase());
  }

  bool _isValidRpId(String rpId, String originHost) {
    // RP ID must be exactly the origin host or a registrable domain suffix
    if (rpId == originHost) {
      return true;
    }

    // Check if rpId is a valid suffix of originHost
    if (originHost.endsWith('.$rpId')) {
      // Prevent public suffix attacks (basic check)
      final parts = rpId.split('.');
      if (parts.length >= 2) {
        return true;
      }
    }

    return false;
  }

  String _sanitizeUrlForLog(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return '';
    }
    try {
      final uri = Uri.parse(rawUrl);
      final hasQuery = uri.hasQuery;
      final hasFragment = uri.fragment.isNotEmpty;
      if (!hasQuery && !hasFragment) {
        return rawUrl;
      }
      return uri
          .replace(
            query: hasQuery ? '<REDACTED>' : null,
            fragment: hasFragment ? '<REDACTED>' : null,
          )
          .toString();
    } catch (_) {
      var sanitized = rawUrl;
      final queryIndex = sanitized.indexOf('?');
      if (queryIndex != -1) {
        sanitized = '${sanitized.substring(0, queryIndex)}?<REDACTED>';
      }
      final fragmentIndex = sanitized.indexOf('#');
      if (fragmentIndex != -1) {
        sanitized = '${sanitized.substring(0, fragmentIndex)}#<REDACTED>';
      }
      return sanitized;
    }
  }

  void _logBlockedNavigation(TabData tab, String requestedUrl) {
    final currentTabIndex = tabs.indexOf(tab);
    logger.w(jsonEncode({
      'event': 'blocked_scheme',
      'requested_url': _sanitizeUrlForLog(requestedUrl),
      'current_url': _sanitizeUrlForLog(tab.currentUrl),
      'tab_index': currentTabIndex,
      'timestamp': DateTime.now().toIso8601String(),
    }));
  }

  Future<void> _handlePermissionRequest(
    TabData tab,
    WebViewPermissionRequest request,
  ) async {
    const allowedMediaPermissions = {
      WebViewPermissionResourceType.camera,
      WebViewPermissionResourceType.microphone,
    };
    final requestedTypes = request.types;
    final granted = requestedTypes.isNotEmpty &&
        requestedTypes.every(allowedMediaPermissions.contains);
    if (granted) {
      await request.grant();
      return;
    }
    await request.deny();
  }

  bool _shouldIgnoreWebResourceError(WebResourceError error) {
    // Subresource failures should not replace the full page with an error view.
    if (error.isForMainFrame == false) {
      return true;
    }
    if (error.errorCode == _wkErrorCancelled) {
      return true;
    }
    if (error.errorCode == _chromiumErrorAborted) {
      return false;
    }
    final description = error.description.toLowerCase();
    return description.contains('cancelled') ||
        description.contains('canceled') ||
        description.contains('interrupted');
  }

  bool _shouldIgnoreHttpError(TabData tab, HttpResponseError error) {
    final requestUrl = error.request?.uri.toString();
    if (requestUrl == null || requestUrl.isEmpty) {
      return false;
    }

    final currentUrl = tab.currentUrl;
    if (_urlsMatchIgnoringFragmentAndTrailingSlash(requestUrl, currentUrl)) {
      return false;
    }
    if (_urlsMatchIgnoringFragmentAndTrailingSlash(
      requestUrl,
      tab.pendingNavigationUrl,
    )) {
      return false;
    }

    final sharesCurrentSite = urlsShareSite(requestUrl, currentUrl);
    final sharesPendingSite =
        urlsShareSite(requestUrl, tab.pendingNavigationUrl);
    if ((sharesCurrentSite || sharesPendingSite) &&
        !_isLikelySubresourceHttpErrorUrl(requestUrl)) {
      return false;
    }

    return true;
  }

  bool _isLikelySubresourceHttpErrorUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return false;
    final fileName = pathSegments.last.toLowerCase();
    if (fileName == 'favicon.ico' ||
        fileName == 'site.webmanifest' ||
        fileName == 'manifest.json') {
      return true;
    }
    final extensionIndex = fileName.lastIndexOf('.');
    if (extensionIndex < 0 || extensionIndex == fileName.length - 1) {
      return false;
    }
    final extension = fileName.substring(extensionIndex + 1);
    const subresourceExtensions = {
      'apng',
      'avif',
      'bmp',
      'css',
      'gif',
      'ico',
      'jpeg',
      'jpg',
      'js',
      'json',
      'map',
      'mjs',
      'otf',
      'png',
      'svg',
      'ttf',
      'webmanifest',
      'webp',
      'woff',
      'woff2',
    };
    return subresourceExtensions.contains(extension);
  }

  bool _urlsMatchIgnoringFragmentAndTrailingSlash(
    String? firstUrl,
    String? secondUrl,
  ) {
    if (firstUrl == null || secondUrl == null) return false;
    try {
      final first = Uri.parse(firstUrl).removeFragment();
      final second = Uri.parse(secondUrl).removeFragment();
      return _normalizeComparableUrl(first) == _normalizeComparableUrl(second);
    } catch (_) {
      return firstUrl == secondUrl;
    }
  }

  String _normalizeComparableUrl(Uri uri) {
    final normalized = uri.toString();
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) {
      return false;
    }
    final lastSegment = uri.pathSegments.last;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == lastSegment.length - 1) {
      return false;
    }
    final extension = lastSegment.substring(dotIndex + 1).toLowerCase();
    return _downloadableExtensions.contains(extension);
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) {
      return 'download';
    }
    final lastSegment = uri.pathSegments.last;
    final decoded = Uri.decodeComponent(lastSegment);
    return decoded.isEmpty ? 'download' : decoded;
  }

  bool _looksLikeBinaryContentType(String? contentType) {
    if (contentType == null) return false;
    final lower = contentType.toLowerCase();
    if (lower.startsWith('text/')) return false;
    if (lower.contains('application/json')) return false;
    if (lower.contains('application/xml')) return false;
    if (lower.contains('application/xhtml+xml')) return false;
    return lower.contains('application') ||
        lower.contains('audio') ||
        lower.contains('video') ||
        lower.contains('image');
  }

  bool _isAttachmentHeader(String? contentDisposition) {
    if (contentDisposition == null) return false;
    final lower = contentDisposition.toLowerCase();
    return lower.contains('attachment') || lower.contains('filename=');
  }

  Future<bool> _hasDownloadHeaders(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final stopwatch = Stopwatch()..start();
    try {
      final head = await http.head(uri);
      NetworkMonitor().logRequest(
        url: url,
        method: 'HEAD',
        statusCode: head.statusCode,
        duration: stopwatch.elapsed,
      );
      if (_isAttachmentHeader(head.headers['content-disposition']) ||
          _looksLikeBinaryContentType(head.headers['content-type'])) {
        return true;
      }
      if (head.statusCode != 405 && head.statusCode != 403) {
        return false;
      }
    } catch (e) {
      NetworkMonitor().onRequestFailed(
        url: url,
        method: 'HEAD',
        error: e is Exception ? e : Exception(e.toString()),
        duration: stopwatch.elapsed,
      );
    }

    try {
      final client = http.Client();
      final stopwatch = Stopwatch()..start();
      try {
        final request = http.Request('GET', uri);
        request.headers['Range'] = 'bytes=0-0';
        final response = await client.send(request);
        NetworkMonitor().logRequest(
          url: url,
          method: 'GET',
          statusCode: response.statusCode,
          duration: stopwatch.elapsed,
        );
        final isDownload =
            _isAttachmentHeader(response.headers['content-disposition']) ||
                _looksLikeBinaryContentType(response.headers['content-type']);
        await response.stream.drain();
        return isDownload;
      } finally {
        client.close();
      }
    } catch (e) {
      NetworkMonitor().onRequestFailed(
        url: url,
        method: 'GET',
        error: e is Exception ? e : Exception(e.toString()),
        duration: Duration.zero,
      );
      return false;
    }
  }

  Future<void> _maybeDownloadByHeaders(String url) async {
    if (_pendingHeaderChecks.contains(url)) return;
    _pendingHeaderChecks.add(url);
    try {
      final shouldDownload = await _hasDownloadHeaders(url);
      if (shouldDownload) {
        await _downloadFile(url);
      }
    } finally {
      _pendingHeaderChecks.remove(url);
    }
  }

  Future<void> _downloadFile(String url) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Downloading...')),
    );

    try {
      final fileName = _fileNameFromUrl(url);
      final saveLocation = await getSaveLocation(suggestedName: fileName);
      if (!mounted) return;
      if (saveLocation == null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Download canceled')),
        );
        return;
      }
      final filePath = saveLocation.path;
      final stopwatch = Stopwatch()..start();
      final response = await http.get(Uri.parse(url));
      NetworkMonitor().logRequest(
        url: url,
        method: 'GET',
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
      );
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        if (!mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('Saved to Downloads: $fileName')),
        );
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  void _addNewTab() {
    if (mounted) {
      setState(() {
        tabs.add(_createTab(widget.initialUrl));
        tabController
            .dispose(); // Dispose the old controller to prevent memory leaks.
        tabController = TabController(
            length: tabs.length, vsync: this, initialIndex: tabs.length - 1);
        tabController.addListener(_onTabChanged);
      });
      previousTabIndex = tabController.index;
    }
  }

  void _closeTab(int index) {
    if (tabs.length > 1) {
      final closingTab = tabs[index];
      if (closingTab.pageRequestedWindowFullscreen) {
        unawaited(_exitPageFullscreen(closingTab));
        unawaited(_setPageRequestedWindowFullscreen(closingTab, false));
      }
      closingTab.webViewController?.loadRequest(Uri.parse('about:blank'));
      setState(() {
        closingTab.isClosed = true;
        closingTab.urlController.dispose();
        closingTab.urlFocusNode.dispose();
        closingTab.torrySearchController.dispose();
        closingTab.torrySearchFocusNode.dispose();
        tabs.removeAt(index);

        // Clear cache and cookies for private browsing
        if (widget.privateBrowsing) {
          _clearAllCaches();
        }

        // Determine the new index before disposing the old controller.
        int newIndex = tabController.index;
        if (newIndex >= tabs.length) {
          newIndex = tabs.length - 1;
        }

        // Dispose the old controller and create a new one.
        tabController.dispose();
        tabController = TabController(
            length: tabs.length, vsync: this, initialIndex: newIndex);
        tabController.addListener(_onTabChanged);
      });
      previousTabIndex = tabController.index;
    }
  }

  void _reorderTab(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final currentIndex = tabController.index;
      final tab = tabs.removeAt(oldIndex);
      tabs.insert(newIndex, tab);

      // Update controller index
      if (currentIndex == oldIndex) {
        tabController.index = newIndex;
      } else if (currentIndex > oldIndex && currentIndex <= newIndex) {
        tabController.index = currentIndex - 1;
      } else if (currentIndex < oldIndex && currentIndex >= newIndex) {
        tabController.index = currentIndex + 1;
      }
    });
  }

  String _normalizeTabTitle(String? title) {
    final normalized = title?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return normalized;
  }

  String _tabFallbackTitleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.scheme == 'file') {
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
      return 'File';
    }
    if (uri.scheme == 'about') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'About';
    }
    final host = uri.host;
    if (host.isEmpty) return url;
    return host.toLowerCase().startsWith('www.') ? host.substring(4) : host;
  }

  String _tabTitleForDisplay(TabData tab) {
    final normalized = _normalizeTabTitle(tab.pageTitle);
    if (normalized.isNotEmpty) return normalized;
    if (tab.currentUrl == defaultHomepageUrl) return '';
    if (tab.state is BrowserError) {
      return _tabFallbackTitleFromUrl(tab.currentUrl);
    }
    if (tab.isResolvingPageTitle ||
        tab.pendingNavigationUrl != null ||
        tab.state is Loading) {
      return '';
    }
    return _tabFallbackTitleFromUrl(tab.currentUrl);
  }

  String? _stringFromJsResult(dynamic result) {
    if (result == null) return null;
    if (result is String) {
      final unescaped = FaviconUrlPolicy.unescapeWrappedJson(result);
      return unescaped.trim();
    }
    return result.toString().trim();
  }

  Future<void> _updateTabTitle(TabData tab, {String? hintedTitle}) async {
    if (!mounted || tab.isClosed) return;
    final controller = tab.webViewController;
    if (controller == null) {
      if (tab.isResolvingPageTitle && mounted && !tab.isClosed) {
        setState(() {
          tab.isResolvingPageTitle = false;
        });
      }
      return;
    }

    final sourceUrl = tab.currentUrl;
    var candidate = _normalizeTabTitle(hintedTitle);
    if (candidate.isEmpty) {
      try {
        candidate = _normalizeTabTitle(await controller.getTitle());
        if (!mounted || tab.isClosed || tab.currentUrl != sourceUrl) return;
      } catch (_) {
        // Best effort only.
      }
    }
    if (!mounted || tab.isClosed || tab.currentUrl != sourceUrl) return;
    if (candidate.isEmpty) {
      try {
        candidate = _normalizeTabTitle(
          _stringFromJsResult(
            await controller.runJavaScriptReturningResult('document.title'),
          ),
        );
        if (!mounted || tab.isClosed || tab.currentUrl != sourceUrl) return;
      } catch (_) {
        // Best effort only.
      }
    }

    if (!mounted || tab.isClosed || tab.currentUrl != sourceUrl) return;
    if (candidate.isEmpty) {
      if (tab.isResolvingPageTitle) {
        setState(() {
          tab.isResolvingPageTitle = false;
        });
      }
      return;
    }
    if (candidate == tab.pageTitle) {
      if (tab.isResolvingPageTitle) {
        setState(() {
          tab.isResolvingPageTitle = false;
        });
      }
      return;
    }
    setState(() {
      tab.pageTitle = candidate;
      tab.isResolvingPageTitle = false;
    });
  }

  Widget _buildTabItem(TabData tab, int index, bool isSelected,
      {bool showDragHandle = false}) {
    final theme = Theme.of(context);
    final canHoverTabs = _isDesktopPlatform;
    final shouldShowClose = tabs.length > 1 &&
        (!canHoverTabs || isSelected || _hoveredTabIndex == index);

    return MouseRegion(
      onEnter: (_) {
        if (!mounted || !canHoverTabs) return;
        if (_hoveredTabIndex == index) return;
        setState(() {
          _hoveredTabIndex = index;
        });
      },
      onExit: (_) {
        if (!mounted || !canHoverTabs) return;
        if (_hoveredTabIndex != index) return;
        setState(() {
          _hoveredTabIndex = null;
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            Icon(
              Icons.drag_indicator,
              size: 16,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
          ],
          _buildTabFavicon(tab, theme),
          const SizedBox(width: 8),
          Text(
            _tabTitleForDisplay(tab).truncate(18),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (tabs.length > 1) ...[
            const SizedBox(width: 6),
            IgnorePointer(
              ignoring: !shouldShowClose,
              child: AnimatedOpacity(
                opacity: shouldShowClose ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: GestureDetector(
                  onTap: () => _closeTab(index),
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget faviconImage({
    required String url,
    required double width,
    required double height,
    required BoxFit fit,
    required Widget fallback,
  }) {
    return ClipRRect(
                borderRadius: BorderRadius.circular(2),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _buildTabFavicon(TabData tab, ThemeData theme) {
    final fallback = ClipRRect(
                borderRadius: BorderRadius.circular(2),
      child: Image.asset(
        'assets/icons/app_icon.png',
        width: 15,
        height: 15,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.public,
            size: 15,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          );
        },
      ),
    );
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    final faviconUrl = tab.faviconUrl;
    final showFallback = faviconUrl == null || faviconUrl.trim().isEmpty;

    if (isIntegrationTest || isFlutterTest) {
      if (!_faviconService.tabFaviconBadgeEnabled) return fallback;
      return SizedBox(
        width: 15,
        height: 15,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          child: Center(child: fallback),
        ),
      );
    }

    if (!_faviconService.tabFaviconBadgeEnabled) {
      if (showFallback) return fallback;
      return faviconImage(
        url: faviconUrl,
        width: 15,
        height: 15,
        fit: BoxFit.cover,
        fallback: fallback,
      );
    }

    final content = showFallback
        ? fallback
        : faviconImage(
            url: faviconUrl,
            width: 13,
            height: 13,
            fit: BoxFit.contain,
            fallback: fallback,
          );

    return SizedBox(
      width: 15,
      height: 15,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Center(child: content),
      ),
    );
  }

  Future<void> _loadReorderableTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = prefs.getBool(
          profileManager.getScopedStorageKey(reorderableTabsKey),
        ) ??
        false;
    if (!mounted) return;
    setState(() {
      _reorderableTabs = resolved;
    });
  }

  Future<void> _reloadAllSettings() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    String scopedKey(String key) => profileManager.getScopedStorageKey(key);

    if (!mounted) return;
    setState(() {
      _reorderableTabs = prefs.getBool(scopedKey(reorderableTabsKey)) ?? false;
      _faviconService.reloadSettings(prefs, scopedKey);
    });
  }

  Future<void> _setWindowMovable(bool movable) async {
    if (isIntegrationTest) return;
    try {
      await windowManager.setMovable(movable);
    } catch (e) {
      logger.w('Failed to update window movability: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveBookmarks();
      _historyService.saveHistory(privateBrowsing: widget.privateBrowsing);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _connectivitySubscription?.cancel();
    _hideAndroidFullscreenWidget?.call();
    _refreshIconController.dispose();
    _ambientController?.dispose();
    _removeUrlAutocompleteOverlay(updatePointerEvents: false);
    _overflowMenuCloseTimer?.cancel();
    _windowButtonsSyncRetryTimer?.cancel();
    _addressBarAutoHideTimer?.cancel();
    profileManager.removeListener(_onProfileChanged);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.dispose();
    for (final tab in tabs) {
      tab.urlController.dispose();
      tab.urlFocusNode.dispose();
      tab.torrySearchController.dispose();
      tab.torrySearchFocusNode.dispose();
    }
    tabController.dispose();
    _saveBookmarks();
    _historyService.saveHistory(privateBrowsing: widget.privateBrowsing);
    super.dispose();
  }

  void _cancelOverflowMenuClose() {
    _overflowMenuCloseTimer?.cancel();
    _overflowMenuCloseTimer = null;
  }

  void _scheduleOverflowMenuClose() {
    if (isIntegrationTest) {
      return;
    }
    _cancelOverflowMenuClose();
    _overflowMenuCloseTimer = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      if (_isOverflowTriggerHovered || _isOverflowMenuHovered) return;
      _overflowMenuController.close();
    });
  }

  Future<void> _loadBookmarks() async {
    if (widget.privateBrowsing) return;
    final bookmarksKey = profileManager.bookmarksKey;
    final prefs = await SharedPreferences.getInstance();
    if (profileManager.bookmarksKey != bookmarksKey) return;
    final bookmarksJson = prefs.getString(bookmarksKey);
    if (bookmarksJson != null) {
      try {
        bookmarkManager.load(bookmarksJson);
      } catch (e, s) {
        logger.w('Failed to load bookmarks', error: e, stackTrace: s);
        if (profileManager.bookmarksKey == bookmarksKey) {
          await prefs.remove(bookmarksKey);
        }
      }
    }
  }

  Future<void> _saveBookmarks() async {
    if (widget.privateBrowsing) return;
    final bookmarksKey = profileManager.bookmarksKey;
    final data = bookmarkManager.save();
    final prefs = await SharedPreferences.getInstance();
    if (profileManager.bookmarksKey != bookmarksKey) return;
    await prefs.setString(bookmarksKey, data);
  }

  void _onProfileChanged() {
    if (!mounted) return;
    bookmarkManager.clear();
    _historyService.clearAll();
    _siteFontFamilies.clear();
    _loadBookmarks();
    _historyService.loadHistory(
      privateBrowsing: widget.privateBrowsing,
      advancedCacheEnabled: widget.advancedCacheEnabled,
      getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
    );
    unawaited(_loadReorderableTabs());
    unawaited(_loadFontOverrides());
    unawaited(_historyService.loadNavigationCacheIndex(
      privateBrowsing: widget.privateBrowsing,
      advancedCacheEnabled: widget.advancedCacheEnabled,
      getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
    ));
    setState(() {});
  }

  void _handleLoadError(TabData tab, String newErrorMessage) {
    final now = DateTime.now();
    final httpStatus = () {
      final match = RegExp(r'^HTTP\s+(\d{3})\b').firstMatch(newErrorMessage);
      if (match == null) return null;
      return int.tryParse(match.group(1) ?? '');
    }();
    final duplicateWindowMs = httpStatus == 429 ? 30000 : 1500;
    final isDuplicate = tab.lastErrorMessage == newErrorMessage &&
        tab.lastErrorAt != null &&
        now.difference(tab.lastErrorAt!).inMilliseconds < duplicateWindowMs;
    if (!isDuplicate) {
      quietLogger.w('Web view load error: $newErrorMessage');
      tab.lastErrorMessage = newErrorMessage;
      tab.lastErrorAt = now;
    }
    if (mounted) {
      setState(() {
        tab.state = BrowserState.error(newErrorMessage);
      });
    }
    if (widget.themeMode == AppThemeMode.adjust && tab == activeTab) {
      widget.onPageThemeChanged?.call(ThemeMode.system, null);
    }
  }

  void _addBookmark() async {
    if (widget.privateBrowsing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bookmarks are not saved in private browsing mode')),
      );
      return;
    }
    String category = 'General';
    final theme = Theme.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Add Bookmark',
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
        ),
        content: TextField(
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          onChanged: (value) => category = value.isEmpty ? 'General' : value,
          decoration: InputDecoration(
            labelText: 'Category',
            isDense: true,
            filled: false,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              bookmarkManager.add(activeTab.currentUrl, category);
              _saveBookmarks();
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _goBack() async {
    try {
      final shouldReturnHome = shouldReturnHomeOnBack(
        currentUrl: activeTab.currentUrl,
        homeUrl: widget.initialUrl,
        homeLaunchedSiteFamily: activeTab.homeLaunchedSiteFamily,
      );
      final canGoBack = await activeTab.webViewController?.canGoBack() ?? false;
      if (shouldReturnHome) {
        if (mounted) {
          setState(() {
            activeTab.forwardUrl = activeTab.currentUrl;
            activeTab.homeLaunchedSiteFamily = null;
            activeTab.currentUrl = widget.initialUrl;
            activeTab.pageTitle = null;
            final homeDisplayUrl = _displayUrl(widget.initialUrl);
            activeTab.urlController.value = TextEditingValue(
              text: homeDisplayUrl,
              selection: TextSelection.collapsed(
                offset: homeDisplayUrl.length,
              ),
            );
            activeTab.faviconUrl = _faviconService.defaultFaviconUrlFor(widget.initialUrl);
            activeTab.webViewController = null;
            activeTab.hideStaleWebViewUntilPageFinish = false;
            activeTab.state = BrowserState.success(widget.initialUrl);
          });
        }
        return;
      }
      if (canGoBack) {
        await activeTab.webViewController?.goBack();
        activeTab.forwardUrl =
            null; // Clear forward URL when using WebView history
      } else {
        // If can't go back, show the home page and save current URL for forward
        if (mounted) {
          setState(() {
            // Only save forward URL if we're not already on home page
            if (activeTab.currentUrl != widget.initialUrl) {
              activeTab.forwardUrl = activeTab.currentUrl;
            }
            activeTab.currentUrl = widget.initialUrl;
            activeTab.pageTitle = null;
            final homeDisplayUrl = _displayUrl(widget.initialUrl);
            activeTab.urlController.value = TextEditingValue(
              text: homeDisplayUrl,
              selection: TextSelection.collapsed(
                offset: homeDisplayUrl.length,
              ),
            );
            activeTab.faviconUrl = _faviconService.defaultFaviconUrlFor(widget.initialUrl);
            activeTab.webViewController = null;
            activeTab.hideStaleWebViewUntilPageFinish = false;
            activeTab.state = BrowserState.success(widget.initialUrl);
          });
        }
      }
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on goBack',
            error: e, stackTrace: s);
      }
    }
  }

  Future<void> _goForward() async {
    try {
      // If on home page and have a forward URL, load it
      if (activeTab.currentUrl == widget.initialUrl &&
          activeTab.forwardUrl != null) {
        _loadUrl(activeTab.forwardUrl!);
        activeTab.forwardUrl = null;
      } else if (await activeTab.webViewController?.canGoForward() ?? false) {
        await activeTab.webViewController?.goForward();
      }
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on goForward',
            error: e, stackTrace: s);
      }
    }
  }

  Future<void> _refresh() async {
    _refreshIconController.forward(from: 0.0);
    if (activeTab.currentUrl == defaultHomepageUrl) {
      if (mounted) {
        setState(() {
          activeTab.ambientSeedColor = null;
          activeTab.pageTitle = null;
          final homeDisplayUrl = _displayUrl(defaultHomepageUrl);
          activeTab.urlController.value = TextEditingValue(
            text: homeDisplayUrl,
            selection: TextSelection.collapsed(
              offset: homeDisplayUrl.length,
            ),
          );
          activeTab.state = BrowserState.success(defaultHomepageUrl);
        });
      }
      return;
    }
    try {
      await activeTab.webViewController?.reload();
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on reload',
            error: e, stackTrace: s);
      }
    }
  }

  Future<void> _toggleMute() async {
    activeTab.isMuted = !activeTab.isMuted;
    await _syncTabMediaState(activeTab);
    if (mounted) setState(() {});
  }

  Future<void> _syncTabMediaState(TabData tab) async {
    if (tab.webViewController == null) return;
    try {
      await tab.webViewController!.runJavaScript(
        buildMediaBridgeScript(muted: tab.isMuted),
      );
    } catch (_) {}
  }

  void _showBookmarks() async {
    if (widget.privateBrowsing) {
      await _showWithModalInteractionBlock<void>(
        () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bookmarks'),
            content: const Text(
                'Bookmarks are not accessible in private browsing mode'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _showWithModalInteractionBlock<void>(
      () => showDialog(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final dialogTheme = theme.copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          );
          return Theme(
            data: dialogTheme,
            child: AlertDialog(
              title: Text(
                'Bookmarks',
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
              ),
              content: StatefulBuilder(
                builder: (context, innerSetState) => bookmarkManager
                        .bookmarks.isEmpty
                    ? const Text('No bookmarks')
                    : SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: ListView(
                          children: bookmarkManager.bookmarks.entries
                              .map((entry) => ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    shape: const Border(),
                                    collapsedShape: const Border(),
                                    title: Text(
                                      entry.key,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(fontSize: 13),
                                    ),
                                    children: entry.value
                                        .map((url) => ListTile(
                                              dense: true,
                                              visualDensity:
                                                  const VisualDensity(
                                                      horizontal: -2,
                                                      vertical: -2),
                                              title: Text(
                                                url,
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(fontSize: 12),
                                              ),
                                              hoverColor: Colors.transparent,
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _loadUrl(url);
                                              },
                                              trailing: MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    final confirm =
                                                        await showDialog<bool>(
                                                      context: context,
                                                      builder: (context) =>
                                                          AlertDialog(
                                                        title: const Text(
                                                            'Delete Bookmark?'),
                                                        content: Text(
                                                            'Remove "$url" from ${entry.key}?'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        context)
                                                                    .pop(false),
                                                            child: const Text(
                                                                'Cancel'),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                        context)
                                                                    .pop(true),
                                                            child: const Text(
                                                                'Delete'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm == true) {
                                                      innerSetState(() {
                                                        bookmarkManager.remove(
                                                            url, entry.key);
                                                      });
                                                      _saveBookmarks();
                                                    }
                                                  },
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    child: Icon(Icons.delete,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant),
                                                  ),
                                                ),
                                              ),
                                            ))
                                        .toList(),
                                  ))
                              .toList(),
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      bookmarkManager.clear();
                    });
                    _saveBookmarks();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear All'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _clearAllCaches() async {
    try {
      final cookieManager = WebViewCookieManager();
      await cookieManager.clearCookies();
      for (final tab in tabs) {
        await tab.webViewController?.clearCache();
        await tab.webViewController?.runJavaScript(clearStorageScript);
      }
      _historyService.navigationCacheIndex.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs
          .remove(profileManager.getScopedStorageKey(navigationCacheIndexKey));
      await prefs.remove(navigationCacheIndexKey);
    } catch (e, s) {
      logger.w('Failed to clear caches', error: e, stackTrace: s);
    }
  }

  Future<void> _clearAllDiskData([bool factoryReset = false]) async {
    try {
      await _clearAllCaches();
      await _passwordRepository.clearAllCredentials();
      final prefs = await SharedPreferences.getInstance();
      int keysCleared = 0;
      if (factoryReset) {
        final allProfiles = profileManager.profiles.toList();
        final profilesToDelete =
            allProfiles.where((p) => p.id != 'default').toList();
        final defaultPrefix = 'default_';
        final defaultKeysToRemove = prefs
            .getKeys()
            .where((key) => key.startsWith(defaultPrefix))
            .toList();
        if (profilesToDelete.isEmpty && defaultKeysToRemove.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Already at factory defaults')),
            );
            Navigator.of(context).pop(true);
          }
          return;
        }
        for (final profile in profilesToDelete) {
          await profileManager.deleteProfile(profile.id);
        }
        keysCleared += defaultKeysToRemove.length;
        for (final key in defaultKeysToRemove) {
          await prefs.remove(key);
        }
        await prefs.remove('user_profiles');
        await prefs.remove('active_profile_id');
        await profileManager.initialize();
      } else {
        final activeProfileId = profileManager.activeProfileId;
        if (activeProfileId != null) {
          final prefix = '${activeProfileId}_';
          final keysToRemove =
              prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
          keysCleared += keysToRemove.length;
          for (final key in keysToRemove) {
            await prefs.remove(key);
          }
        }
        final globalKeysToRemoveList = [
          navigationCacheIndexKey,
          useModernUserAgentKey,
          aiSearchSuggestionsEnabledKey,
          advancedCacheEnabledKey,
          privateBrowsingKey,
          adBlockingKey,
          strictModeKey,
        ];
        final globalKeysToRemove = prefs
            .getKeys()
            .where((key) => globalKeysToRemoveList.contains(key))
            .toList();
        keysCleared += globalKeysToRemove.length;
        for (final key in globalKeysToRemove) {
          await prefs.remove(key);
        }
      }
      await prefs.reload();
      if (mounted) {
        final message = factoryReset
            ? 'Factory reset complete'
            : (keysCleared > 0 ? 'All data cleared' : 'Nothing to clear');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        Navigator.of(context).pop(true);
        widget.onSettingsChanged?.call();
      }
    } catch (e, s) {
      logger.w('Failed to clear all disk data', error: e, stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  void _showSettings() async {
    final saved = await _showWithModalInteractionBlock<bool>(
      () => showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Settings',
        barrierColor: _ambientActive ? Colors.transparent : Colors.black54,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
          final theme = Theme.of(context);
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              type: MaterialType.transparency,
              color: _ambientActive
                  ? theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.95)
                  : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: SettingsDialog(
                onSettingsChanged: () {
                  _reloadAllSettings();
                  widget.onSettingsChanged?.call();
                },
                onClearCaches: _clearAllCaches,
                onClearAllData: _clearAllDiskData,
                onThemePreviewChanged: widget.onThemePreviewChanged,
                currentTheme: widget.themeMode,
                aiSearchSuggestionsEnabled: widget.aiSearchSuggestionsEnabled,
                advancedCacheEnabled: widget.advancedCacheEnabled,
                aiAvailable: widget.aiAvailable,
                ambientToolbarEnabled: widget.ambientToolbarEnabled,
                autoHideAddressBarEnabled: widget.autoHideAddressBarEnabled,
                onOpenHelp: () => _loadUrl(
                    'https://Palmshed.github.io/browser/features.html'),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: child,
            ),
          );
        },
      ),
    );
    if (saved != true) {
      widget.onThemePreviewReset?.call();
    }
  }

  Future<void> _showFontPicker() async {
    const customOptionValue = '__custom__';
    final noHoverOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      return states.contains(WidgetState.hovered) ? Colors.transparent : null;
    });
    final currentHost = _faviconService.hostFromUrl(activeTab.currentUrl);
    final hasSiteRule =
        currentHost != null && _siteFontFamilies.containsKey(currentHost);
    var applyToCurrentSite = hasSiteRule;
    final initialFont =
        hasSiteRule ? _siteFontFamilies[currentHost] ?? '' : _pageFontFamily;
    final hasPreset = _pageFontChoices.any(
      (choice) => choice.cssFamily == initialFont,
    );
    var selectedValue = hasPreset ? initialFont : customOptionValue;
    final customFontController = TextEditingController(
      text: hasPreset ? '' : initialFont,
    );

    final result = await _showWithModalInteractionBlock<_FontPickerResult>(
      () => showGeneralDialog<_FontPickerResult>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Page Font',
        barrierColor: Colors.transparent,
        pageBuilder: (context, _, __) {
          final dialogTheme = Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
          );
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                const InteractionBlocker(),
                Align(
                  alignment: Alignment.center,
                  child: Theme(
                    data: dialogTheme,
                    child: StatefulBuilder(
                      builder: (context, setStateDialog) => AlertDialog(
                        title: const Text('Page Font'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentHost != null) ...[
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<bool>(
                                  segments: [
                                    const ButtonSegment<bool>(
                                      value: false,
                                      label: Text('Global'),
                                    ),
                                    ButtonSegment<bool>(
                                      value: true,
                                      label: Text(currentHost),
                                    ),
                                  ],
                                  selected: {applyToCurrentSite},
                                  style:
                                      ButtonStyle(overlayColor: noHoverOverlay),
                                  onSelectionChanged: (selection) {
                                    setStateDialog(() {
                                      applyToCurrentSite = selection.first;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 220),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      ..._pageFontChoices.map(
                                        (choice) => ListTile(
                                          dense: true,
                                          visualDensity: const VisualDensity(
                                              horizontal: -2, vertical: -2),
                                          hoverColor: Colors.transparent,
                                          title: Text(choice.label),
                                          trailing:
                                              selectedValue == choice.cssFamily
                                                  ? const Icon(Icons.check,
                                                      size: 18)
                                                  : null,
                                          onTap: () {
                                            setStateDialog(() {
                                              selectedValue = choice.cssFamily;
                                            });
                                          },
                                        ),
                                      ),
                                      ListTile(
                                        dense: true,
                                        visualDensity: const VisualDensity(
                                            horizontal: -2, vertical: -2),
                                        hoverColor: Colors.transparent,
                                        title: const Text(
                                            'Custom CSS Font Family'),
                                        trailing: selectedValue ==
                                                customOptionValue
                                            ? const Icon(Icons.check, size: 18)
                                            : null,
                                        onTap: () {
                                          setStateDialog(() {
                                            selectedValue = customOptionValue;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (selectedValue == customOptionValue) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: customFontController,
                                decoration: const InputDecoration(
                                  labelText: 'Custom font-family value',
                                  hintText:
                                      'e.g. "Fira Sans", Arial, sans-serif',
                                ),
                              ),
                            ],
                          ],
                        ),
                        actions: [
                          TextButton(
                            style: ButtonStyle(overlayColor: noHoverOverlay),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          if (currentHost != null &&
                              hasSiteRule &&
                              applyToCurrentSite)
                            TextButton(
                              style: ButtonStyle(overlayColor: noHoverOverlay),
                              onPressed: () {
                                Navigator.of(context).pop(
                                  const _FontPickerResult(
                                    fontFamily: '',
                                    applyToCurrentSite: true,
                                    clearCurrentSiteRule: true,
                                  ),
                                );
                              },
                              child: const Text('Clear Site Rule'),
                            ),
                          TextButton(
                            style: ButtonStyle(overlayColor: noHoverOverlay),
                            onPressed: () {
                              final chosenFont =
                                  selectedValue == customOptionValue
                                      ? customFontController.text.trim()
                                      : selectedValue;
                              Navigator.of(context).pop(
                                _FontPickerResult(
                                  fontFamily: chosenFont,
                                  applyToCurrentSite:
                                      currentHost != null && applyToCurrentSite,
                                ),
                              );
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    customFontController.dispose();

    if (!mounted || result == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (result.applyToCurrentSite && currentHost != null) {
      if (result.clearCurrentSiteRule) {
        if (!_siteFontFamilies.containsKey(currentHost)) return;
        setState(() {
          _siteFontFamilies.remove(currentHost);
        });
        await _persistFontOverrides();
      } else {
        if ((_siteFontFamilies[currentHost] ?? '') == result.fontFamily) return;
        setState(() {
          _siteFontFamilies[currentHost] = result.fontFamily;
        });
        await _persistFontOverrides();
      }
    } else {
      if (result.fontFamily == _pageFontFamily) return;
      await prefs.setString(
        profileManager.getScopedStorageKey(pageFontFamilyKey),
        result.fontFamily,
      );
      setState(() {
        _pageFontFamily = result.fontFamily;
      });
    }

    await _applyFontOverrideToAllTabs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.clearCurrentSiteRule
              ? 'Site font rule removed'
              : result.fontFamily.isEmpty
                  ? 'Font override disabled'
                  : 'Page font updated',
        ),
      ),
    );
  }

  void _showNetworkDebug() async {
    await _showWithModalInteractionBlock<void>(
      () => showDialog(
        context: context,
        builder: (context) => const NetworkDebugDialog(),
      ),
    );
  }

  Future<void> _handleMenuSelection(String value) async {
    switch (value) {
      case 'add_bookmark':
        _addBookmark();
        break;
      case 'view_bookmarks':
        _showBookmarks();
        break;
      case 'history':
        _showHistory();
        break;
      case 'ai_chat':
        _showAiChat();
        break;
      case 'settings':
        _showSettings();
        break;
      case 'page_font':
        _showFontPicker();
        break;
      case 'network_debug':
        _showNetworkDebug();
        break;
      case 'whats_new':
        if (widget.onShowWhatsNew != null) {
          await _showWithModalInteractionBlock<void>(widget.onShowWhatsNew!);
        }
        break;
      case 'onion_directory':
        _loadUrl('https://www.torry.io/learn/directory/');
        break;
      case 'anonymous_view':
        _loadUrl('https://www.torry.io/anonymous-view/');
        break;
    }
  }

  Widget _buildMenuButton({
    double iconSize = 20,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8),
  }) {
    return BrowserOverflowMenu(
      controller: _overflowMenuController,
      aiAvailable: widget.aiAvailable,
      menuOpen: _overflowMenuOpen,
      iconSize: iconSize,
      padding: padding,
      onOpenChanged: (open) {
        _setOverflowMenuOpen(open);
      },
      onSelection: (value) async {
        _overflowMenuController.close();
        await _handleMenuSelection(value);
      },
      onTriggerHoverChanged: (hovered) {
        _isOverflowTriggerHovered = hovered;
        if (hovered) {
          _cancelOverflowMenuClose();
        } else {
          _scheduleOverflowMenuClose();
        }
      },
      onMenuHoverChanged: (hovered) {
        _isOverflowMenuHovered = hovered;
        if (hovered) {
          _cancelOverflowMenuClose();
        } else {
          _scheduleOverflowMenuClose();
        }
      },
    );
  }

  Future<void> _showAiChat() async {
    if (!widget.aiAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI is not available in this build')));
      return;
    }
    final activeTab = tabs[tabController.index];
    String? pageTitle;
    String? pageUrl;
    try {
      final titleResult = await activeTab.webViewController
          ?.runJavaScriptReturningResult('document.title');
      if (titleResult != null && titleResult is String) {
        pageTitle = titleResult;
      }
      final urlResult = await activeTab.webViewController
          ?.runJavaScriptReturningResult('window.location.href');
      if (urlResult != null && urlResult is String) {
        pageUrl = urlResult;
      }
    } catch (e) {
      debugPrint('Error fetching page info: $e');
    }
    await _showWithModalInteractionBlock<void>(
      () => showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'AI Chat',
        barrierColor: _ambientActive
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.16)
            : Colors.black54,
        transitionDuration: const Duration(milliseconds: 150),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.035),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.975, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          final topOffset = widget.hideAppBar ? 18.0 : 78.0;
          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, topOffset, 24, 12),
                child: AiChatWidget(
                  pageTitle: pageTitle,
                  pageUrl: pageUrl,
                  ambientEnabled: _ambientActive,
                  accentColor:
                      activeTab.ambientSeedColor ?? activeTab.detectedSeedColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<String> _fallbackSearchSuggestions() {
    return const [
      'best hidden travel places in 2026',
      'latest space discoveries this week',
      'beginner friendly side project ideas',
      'healthy 20 minute dinner recipes',
      'best documentaries to watch this month',
      'top open source tools for productivity',
    ];
  }

  List<String> _parseAiSuggestions(String raw) {
    final seen = <String>{};
    final output = <String>[];
    final lines = raw.split('\n');
    for (final line in lines) {
      var cleaned = line.trim();
      if (cleaned.isEmpty) continue;
      cleaned = cleaned.replaceAll(RegExp(r'^[-*•\d\.\)\s]+'), '').trim();
      if (cleaned.length < 4) continue;
      if (_isDisallowedAiSuggestion(cleaned)) continue;
      if (seen.add(cleaned.toLowerCase())) {
        output.add(cleaned);
      }
      if (output.length >= 6) break;
    }
    return output;
  }

  bool _isDisallowedAiSuggestion(String suggestion) {
    return suggestion.trim().toLowerCase().startsWith('file://');
  }

  Future<List<String>> _fetchAiSearchSuggestions() async {
    final now = DateTime.now();
    final isCacheFresh = _cachedAiSearchSuggestions != null &&
        _lastAiSuggestionFetchAt != null &&
        now.difference(_lastAiSuggestionFetchAt!) < const Duration(minutes: 20);
    if (isCacheFresh) {
      return _cachedAiSearchSuggestions!;
    }

    List<String> suggestions;
    if (!widget.aiAvailable) {
      suggestions = _fallbackSearchSuggestions();
    } else {
      try {
        final response = await _aiService?.generateResponse(
              'Suggest 6 short, interesting web search ideas for a general audience. '
              'Return only one idea per line. No numbering. No extra text.',
            ) ??
            '';
        final parsed = _parseAiSuggestions(response);
        suggestions = parsed.isEmpty ? _fallbackSearchSuggestions() : parsed;
      } catch (_) {
        suggestions = _fallbackSearchSuggestions();
      }
    }

    _cachedAiSearchSuggestions = suggestions;
    _lastAiSuggestionFetchAt = now;
    return suggestions;
  }

  Future<void> _showAiSearchSuggestionsSheet() async {
    final theme = Theme.of(context);
    final suggestionsFuture = _fetchAiSearchSuggestions();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FutureBuilder<List<String>>(
          future: suggestionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final suggestions = snapshot.data ?? _fallbackSearchSuggestions();
            return SizedBox(
              key: const Key('browser.ai_suggestions_sheet'),
              height: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                    child: Text(
                      key: const Key('browser.ai_suggestions_title'),
                      'Explore with AI',
                      style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        return ListTile(
                          dense: true,
                          visualDensity:
                              const VisualDensity(horizontal: -2, vertical: -2),
                          hoverColor: Colors.transparent,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          minLeadingWidth: 18,
                          leading: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(
                            suggestion,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 13),
                          ),
                          onTap: () async {
                            activeTab.urlFocusNode.unfocus();
                            _setUrlAutocompleteOpen(false);
                            if (_isDisallowedAiSuggestion(suggestion)) {
                              Navigator.of(context).pop();
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Blocked unsafe local file suggestion',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }
                            Navigator.of(context).pop();
                            await Future<void>.delayed(Duration.zero);
                            if (!mounted) return;
                            FocusManager.instance.primaryFocus?.unfocus();
                            activeTab.urlFocusNode.unfocus();
                            await _loadUrl(suggestion);
                            if (!mounted) return;
                            activeTab.urlController.selection =
                                TextSelection.collapsed(
                              offset: activeTab.urlController.text.length,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showHistory() async {
    if (widget.privateBrowsing) {
      await _showWithModalInteractionBlock<void>(
        () => showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('History'),
            content:
                const Text('History is not saved in private browsing mode'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final history = _historyService.history;
    await _showWithModalInteractionBlock<void>(
      () => showDialog(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final dialogTheme = theme.copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          );
          return Theme(
            data: dialogTheme,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final displayHistory = history.reversed.toList(growable: false);
                return AlertDialog(
                  title: Text(
                    'History',
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                  ),
                  content: history.isEmpty
                      ? const Text('No history')
                      : SizedBox(
                          width: double.maxFinite,
                          height: 300,
                          child: ListView.builder(
                            itemCount: displayHistory.length,
                            itemBuilder: (context, index) {
                              final entry = displayHistory[index];
                              return ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                    horizontal: -2, vertical: -2),
                                title: Text(
                                  entry,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontSize: 12),
                                ),
                                hoverColor: Colors.transparent,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _loadUrl(entry);
                                },
                                trailing: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        final removeIndex =
                                            history.length - 1 - index;
                                        if (removeIndex >= 0 &&
                                            removeIndex < history.length) {
                                          history.removeAt(removeIndex);
                                        }
                                      });
                                      setDialogState(() {});
                                      _historyService.saveHistory(privateBrowsing: widget.privateBrowsing);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(Icons.delete,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          history.clear();
                          for (final tab in tabs) {
                            tab.history.clear();
                          }
                        });
                        setDialogState(() {});
                        _historyService.saveHistory(privateBrowsing: widget.privateBrowsing);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Clear All'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQuickUrlPrompt() async {
    var inputValue =
        activeTab.currentUrl == defaultHomepageUrl ? '' : activeTab.currentUrl;
    var dialogClosed = false;
    final theme = Theme.of(context);
    _quickUrlPromptOpen = true;
    final submittedValue = await (() async {
      try {
        return await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) {
            void closeDialog([String? value]) {
              if (dialogClosed) return;
              dialogClosed = true;
              Navigator.of(dialogContext).pop(value);
            }

            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: inputValue,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'enter url or search',
                      hintStyle: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      isDense: true,
                      filled: false,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      inputValue = value;
                    },
                    onFieldSubmitted: (value) {
                      Future<void>.delayed(Duration.zero, () {
                        closeDialog(value);
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => closeDialog(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => closeDialog(inputValue),
                  child: const Text('Go'),
                ),
              ],
            );
          },
        );
      } finally {
        _quickUrlPromptOpen = false;
      }
    })();

    final value = submittedValue?.trim();
    if (value == null || value.isEmpty) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _loadUrl(value);
  }

  Future<void> _loadUrl(String url) async {
    if (_urlAutocompleteOpen && mounted) {
      setState(() => _urlAutocompleteOpen = false);
      _syncPagePointerEvents(activeTab);
    }

    // Clear forward URL when loading a new URL
    activeTab.forwardUrl = null;

    // Handle about: URLs with strict allowlist
    if (url.startsWith('about:')) {
      // Only allow trusted internal about: URLs
      const allowedAboutUrls = {
        'about:browser-home',
        'about:blank',
      };

      if (!allowedAboutUrls.contains(url)) {
        logger.w('Blocked invalid about: URL: $url');
        if (mounted) {
          setState(() {
            activeTab.currentUrl = url;
            activeTab.urlController.text = url;
            activeTab.state = const BrowserState.error('Invalid internal URL.');
          });
        }
        return;
      }

      // Only about:browser-home is internal-only; about:blank loads in WebView
      if (url == 'about:browser-home') {
        if (mounted) {
          setState(() {
            activeTab.homeLaunchedSiteFamily = null;
            activeTab.currentUrl = url;
            activeTab.pageTitle = null;
            activeTab.isResolvingPageTitle = false;
            activeTab.pendingNavigationUrl = null;
            activeTab.pendingNavigationSourceUrl = null;
            activeTab.urlController.text = _displayUrl(url);
            activeTab.faviconUrl = _faviconService.defaultFaviconUrlFor(url);
            activeTab.webViewController = null;
            activeTab.state = BrowserState.success(url);
          });
        }
        return;
      }
      // about:blank falls through to normal WebView load
    }

    final wasOnHome = activeTab.currentUrl == defaultHomepageUrl;
    final processedUrl = UrlUtils.processUrl(url);

    if (!UrlUtils.isValidUrl(processedUrl)) {
      logger.w('Invalid or unsafe URL: $processedUrl');
      if (mounted) {
        setState(() {
          activeTab.pendingNavigationUrl = null;
          activeTab.pendingNavigationSourceUrl = null;
          activeTab.currentUrl = url;
          activeTab.pageTitle = null;
          activeTab.isResolvingPageTitle = false;
          activeTab.urlController.text = url;
          activeTab.state =
              const BrowserState.error('That address does not look valid.');
        });
      }
      return;
    }
    final previousUrl = activeTab.currentUrl;
    if (mounted) {
      setState(() {
        if (wasOnHome) {
          activeTab.homeLaunchedSiteFamily = siteFamilyKeyForUrl(processedUrl);
        }
        activeTab.pendingNavigationUrl = processedUrl;
        activeTab.pendingNavigationSourceUrl = previousUrl;
        activeTab.currentUrl = processedUrl;
        activeTab.pageTitle = null;
        activeTab.isResolvingPageTitle = true;
        activeTab.urlController.text = _displayUrl(processedUrl);
        activeTab.faviconUrl = _faviconService.cachedFaviconForUrl(processedUrl);
        activeTab.hideStaleWebViewUntilPageFinish = wasOnHome;
      });
    }
    if ((activeTab.webViewController == null || wasOnHome) && mounted) {
      // Schedule navigation after the frame that creates/mounts the WebView
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || activeTab.isClosed ||
              activeTab.webViewController == null) {
            return;
          }
          unawaited(() async {
            await _configurePlatformSpecificWebView(activeTab);
            if (!mounted || activeTab.isClosed) return;
            await _loadInitialRequestForTab(activeTab);
          }());
        });
      });
      return;
    }
    try {
      if (processedUrl.startsWith('file:///') ||
          processedUrl.startsWith('file://')) {
        final path = processedUrl.replaceFirst('file://', '');
        await _loadLocalFile(path);
      } else {
        activeTab.webViewController?.loadRequest(Uri.parse(processedUrl));
      }
    } on PlatformException catch (e, s) {
      if (!_isMissingPluginException(e)) {
        logger.w('Unexpected PlatformException on loadUrl',
            error: e, stackTrace: s);
      }
    }
  }

  Future<void> _loadLocalFile(String path) async {
    final controller = activeTab.webViewController;
    if (controller == null) return;

    if (defaultTargetPlatform == TargetPlatform.macOS &&
        controller.platform is WebKitWebViewController) {
      final webKitController = controller.platform as WebKitWebViewController;
      final parentPath = File(path).parent.path;
      await webKitController.loadFileWithParams(
        WebKitLoadFileParams(
          absoluteFilePath: path,
          readAccessPath: parentPath,
        ),
      );
      return;
    }

    await controller.loadFile(path);
  }



  Widget _buildTorryHomeView(TabData tab) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final useAmbient = _ambientActive;

    return TorryHomeView(
      theme: theme,
      colorScheme: colorScheme,
      useAmbient: useAmbient,
    );
  }

  Widget _buildErrorView(TabData tab) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final errorActionColor = colorScheme.onSurface;
    final noHoverOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      return states.contains(WidgetState.hovered) ? Colors.transparent : null;
    });
    final errorMessage = tab.state is BrowserError
        ? (tab.state as BrowserError).message
        : 'We could not load that page.';
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.public_off,
                size: 42,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Via',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sorry, we can’t open this page.',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontSize: 24,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              errorMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (tab.webViewController != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ).copyWith(
                      overlayColor: noHoverOverlay,
                      elevation: WidgetStateProperty.resolveWith<double?>(
                        (states) =>
                            states.contains(WidgetState.hovered) ? 0 : null,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        tab.state = const BrowserState.idle();
                      });
                      tab.webViewController?.reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: errorActionColor,
                    side: BorderSide(
                      color: errorActionColor.withValues(alpha: 0.45),
                    ),
                    visualDensity: VisualDensity.compact,
                  ).copyWith(overlayColor: noHoverOverlay),
                  onPressed: () {
                    if (widget.hideAppBar) {
                      _showQuickUrlPrompt();
                    } else {
                      tab.urlFocusNode.requestFocus();
                    }
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit URL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody(TabData tab) {
    if (tab.currentUrl == defaultHomepageUrl) {
      return _buildTorryHomeView(tab);
    }
    if (tab.state is BrowserError) {
      return _buildErrorView(tab);
    }
    if (defaultTargetPlatform == TargetPlatform.macOS && isIntegrationTest) {
      return const Center(
        child: Text('WebView disabled in integration tests.'),
      );
    }

    if (tab.webViewController == null) {
      final shouldHookPermissions = defaultTargetPlatform != TargetPlatform.iOS;
      PlatformWebViewControllerCreationParams params =
          const PlatformWebViewControllerCreationParams();
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams
            .fromPlatformWebViewControllerCreationParams(
          params,
          allowsInlineMediaPlayback: true,
        );
      }
      tab.webViewController = WebViewController.fromPlatformCreationParams(
        params,
        onPermissionRequest: shouldHookPermissions
            ? (request) {
                unawaited(_handlePermissionRequest(tab, request));
              }
            : null,
      );
      tab.webViewController!.setJavaScriptMode(widget.strictMode
          ? JavaScriptMode.disabled
          : JavaScriptMode.unrestricted);
      // Note: webview_flutter does not support built-in private browsing.
      // Cache is not stored for private tabs (LOAD_NO_CACHE equivalent not available).
      // Cookies are shared globally; private browsing does not clear them.
      // This is a limitation compared to flutter_inappwebview.
      // Partial workaround for SPA history: listen for popstate events via JS.
      tab.webViewController!.addJavaScriptChannel('HistoryChannel',
          onMessageReceived: (JavaScriptMessage message) {
        if (tab.webViewController == null) return;
        final payload = message.message;
        var url = payload;
        String? title;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            final decodedUrl = decoded['url'];
            if (decodedUrl is String && decodedUrl.trim().isNotEmpty) {
              url = decodedUrl;
            }
            final decodedTitle = decoded['title'];
            if (decodedTitle is String && decodedTitle.trim().isNotEmpty) {
              title = decodedTitle;
            }
          }
        } catch (_) {
          // Backwards-compatible: treat payload as a raw URL.
        }
        // Validate URL to prevent LFI and spoofing attacks
        if (!_isValidHistoryUrl(url)) {
          logger.w(
            'Blocked invalid URL from HistoryChannel: ${_sanitizeUrlForLog(url)}',
          );
          return;
        }
        _historyService.recordHistory(
          tab,
          url,
          privateBrowsing: widget.privateBrowsing,
          advancedCacheEnabled: widget.advancedCacheEnabled,
          getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
        );
        // Update the URL bar for SPA navigation
        if (!tab.isClosed && mounted) {
          setState(() {
            if (tab.currentUrl != url) {
              tab.currentUrl = url;
              tab.urlController.text = url;
            }
            final normalizedTitle = _normalizeTabTitle(title);
            if (normalizedTitle.isNotEmpty) {
              tab.pageTitle = normalizedTitle;
              tab.isResolvingPageTitle = false;
            }
          });
        }
        unawaited(_updateTabTitle(tab, hintedTitle: title));
        unawaited(_syncTabMediaState(tab));
        _updateThemeFromTab(tab);
        _updateAmbientFromTab(tab);
      });
      tab.webViewController!.addJavaScriptChannel('TitleChangeChannel',
          onMessageReceived: (JavaScriptMessage message) {
        if (tab.webViewController == null) return;
        final payload = message.message;
        String? title;
        String? url;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            final decodedTitle = decoded['title'];
            if (decodedTitle is String && decodedTitle.trim().isNotEmpty) {
              title = decodedTitle;
            }
            final decodedUrl = decoded['url'];
            if (decodedUrl is String && decodedUrl.trim().isNotEmpty) {
              url = decodedUrl;
            }
          }
        } catch (_) {
          title = payload;
        }
        if (url != null && !_isValidHistoryUrl(url)) {
          logger.w(
            'Blocked invalid URL from TitleChangeChannel: ${_sanitizeUrlForLog(url)}',
          );
          return;
        }
        final normalizedTitle = _normalizeTabTitle(title);
        if (normalizedTitle.isEmpty || tab.isClosed || !mounted) return;
        setState(() {
          if (url != null && tab.currentUrl != url) {
            tab.currentUrl = url;
            tab.urlController.text = url;
          }
          tab.pageTitle = normalizedTitle;
          tab.isResolvingPageTitle = false;
        });
      });
      tab.webViewController!.addJavaScriptChannel('PageTapChannel',
          onMessageReceived: (JavaScriptMessage message) {
        if (!mounted || tab.isClosed) return;
        tab.hasUserInteractedWithPage = true;
        if (tab.urlFocusNode.hasFocus) {
          tab.urlFocusNode.unfocus();
        }
        if (_urlAutocompleteOpen) {
          _setUrlAutocompleteOpen(false);
        }
      });
      tab.webViewController!.addJavaScriptChannel('FullscreenChannel',
          onMessageReceived: (JavaScriptMessage message) {
        unawaited(_handlePageFullscreenMessage(tab, message.message));
      });
      tab.webViewController!.addJavaScriptChannel('LoginDetector',
          onMessageReceived: (JavaScriptMessage message) async {
        final prefs = await SharedPreferences.getInstance();
        final passwordManagerEnabled = prefs.getBool(
              profileManager.getScopedStorageKey(passwordManagerEnabledKey),
            ) ??
            false;
        if (!passwordManagerEnabled) return;

        try {
          final data = jsonDecode(message.message) as Map<String, dynamic>;
          final credentials = LoginCredentials.fromJson(data);

          // Verify origin matches current tab URL to prevent spoofing
          final tabUri = Uri.parse(tab.currentUrl);
          final credentialUri = Uri.parse(credentials.origin);
          if (tabUri.origin != credentialUri.origin) return;

          final policy = SitePasswordPolicy(prefs: prefs);
          if (await policy.isNeverSave(credentials.origin)) return;

          if (mounted && !tab.isClosed) {
            setState(() {
              tab.pendingPasswordPrompt = SavePasswordPromptData(
                origin: credentials.origin,
                username: credentials.username,
                password: credentials.password,
              );
            });
          }
        } catch (e, s) {
          logger.w('Failed to parse login credentials from JS',
              error: e, stackTrace: s);
        }
      });
      tab.webViewController!.addJavaScriptChannel('WebAuthnChannel',
          onMessageReceived: (JavaScriptMessage message) async {
        _handleWebAuthnMessage(tab, message.message);
      });
      tab.webViewController!.addJavaScriptChannel('ScrollOffsetChannel',
          onMessageReceived: (JavaScriptMessage message) {
        if (!mounted || tab.isClosed) return;
        final offset = double.tryParse(message.message) ?? 0;
        if (tab.scrollOffset != offset) {
          setState(() {
            tab.scrollOffset = offset;
          });
        }
      });
      tab.webViewController!.addJavaScriptChannel('MediaStateChannel',
          onMessageReceived: (JavaScriptMessage message) {
        final playbackState = parseMediaPlaybackStateMessage(message.message);
        if (playbackState == null || !mounted || tab.isClosed) {
          return;
        }
        if (tab.hasMediaPlaying == playbackState.hasPlayingMedia) {
          return;
        }
        setState(() {
          tab.hasMediaPlaying = playbackState.hasPlayingMedia;
        });
      });
      tab.webViewController!.setNavigationDelegate(NavigationDelegate(
        onUrlChange: (change) {
          if (tab.webViewController == null) return;
          if (_isLiveTab(tab) && change.url != null) {
            final actualUrl = resolveNavigationEventUrl(
              eventUrl: change.url!,
              controllerUrl: null,
              pendingUrl: tab.pendingNavigationUrl,
              previousUrl: tab.pendingNavigationSourceUrl,
            );
            setState(() {
              tab.currentUrl = actualUrl;
              tab.urlController.text = actualUrl;
              if (urlsShareSite(actualUrl, tab.pendingNavigationUrl)) {
                tab.pendingNavigationUrl = null;
                tab.pendingNavigationSourceUrl = null;
              }
            });
          }
          unawaited(_syncTabMediaState(tab));
        },
        onPageStarted: (url) async {
          if (tab.webViewController == null) return;
          if (_isLiveTab(tab) && identical(tab, activeTab)) {
            unawaited(_setPageRequestedWindowFullscreen(tab, false));
          }
          if (!_isLiveTab(tab)) return;
          final controllerUrl = await tab.webViewController?.currentUrl();
          if (!_isLiveTab(tab)) return;
          final actualUrl = resolveNavigationEventUrl(
            eventUrl: url,
            controllerUrl: controllerUrl,
            pendingUrl: tab.pendingNavigationUrl,
            previousUrl: tab.pendingNavigationSourceUrl,
          );
          setState(() {
            tab.currentUrl = actualUrl;
            tab.urlController.text = tab.currentUrl;
            tab.state = const BrowserState.loading();
            tab.pageTitle = null;
            tab.isResolvingPageTitle = true;
            tab.hasUserInteractedWithPage = false;
            tab.hasMediaPlaying = false;
            tab.isMuted = false;
            tab.detectedBrightness = null;
            tab.detectedSeedColor = null;
            tab.ambientSeedColor = null;
            tab.lastAmbientProbeAt = null;
            tab.faviconUrl = _faviconService.cachedFaviconForUrl(actualUrl);
                _historyService.recordHistory(
              tab,
              tab.currentUrl,
              privateBrowsing: widget.privateBrowsing,
              advancedCacheEnabled: widget.advancedCacheEnabled,
              getUserAgent: (url) => _getUserAgent(widget.useModernUserAgent),
            );
          });
          _syncPagePointerEvents(tab);
          _ensurePageTapListenerInstalled(tab);
          _installInitialFocusInterceptor(tab);
          _clearUnwantedInitialPageFocus(tab);
        },
        onPageFinished: (url) async {
          if (tab.webViewController == null) return;
          if (!_isLiveTab(tab)) return;
          final controllerUrl = await tab.webViewController?.currentUrl();
          if (!_isLiveTab(tab)) return;
          final actualUrl = resolveNavigationEventUrl(
            eventUrl: url,
            controllerUrl: controllerUrl,
            pendingUrl: tab.pendingNavigationUrl,
            previousUrl: tab.pendingNavigationSourceUrl,
          );
          tab.hideStaleWebViewUntilPageFinish = false;
          unawaited(_syncTabMediaState(tab));
          setState(() {
            tab.currentUrl = actualUrl;
            tab.urlController.text = actualUrl;
            tab.pendingNavigationUrl = null;
            tab.pendingNavigationSourceUrl = null;
            if (tab.state is! BrowserError) {
              tab.state = BrowserState.success(actualUrl);
            }
          });
          if (_isLiveTab(tab) && identical(tab, activeTab)) {
            _setActiveTabUrlObscured(false);
            _maybeScheduleAddressBarAutoHide(tab, revealImmediately: true);
          }
          // Add listeners for SPA navigations: popstate, pushState, replaceState
          if (_isLiveTab(tab) && tab.webViewController != null) {
            tab.webViewController!.runJavaScript(spaNavigationScript);
            unawaited(_installFullscreenBridge(tab));
            // Inject login detection script
            tab.webViewController!.runJavaScript(loginDetectionScript);
            // Inject WebAuthn script
            tab.webViewController!.runJavaScript(webAuthnScript);
            _applyLegacyLayoutFix(tab);
            _applyFontOverride(tab);
            _faviconService.updateTabFavicon(tab, mounted: mounted, setState: setState);
            // Attempt autofill if credentials available
            _attemptAutofill(tab);
          }
          _syncPagePointerEvents(tab);
          unawaited(_updateTabTitle(tab));
          _updateThemeFromTab(tab);
          _updateAmbientFromTab(tab);
          _installInitialFocusInterceptor(tab);
          _clearUnwantedInitialPageFocus(tab);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!_isLiveTab(tab)) return;
            _installInitialFocusInterceptor(tab);
            _clearUnwantedInitialPageFocus(tab);
            _updateThemeFromTab(tab);
            _updateAmbientFromTab(tab);
          });
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (!_isLiveTab(tab)) return;
            _installInitialFocusInterceptor(tab);
            _clearUnwantedInitialPageFocus(tab);
            _updateThemeFromTab(tab);
            _updateAmbientFromTab(tab);
          });
        },
        onNavigationRequest: (request) {
          if (!_isAllowedNavigationUrl(request.url)) {
            _logBlockedNavigation(tab, request.url);
            return NavigationDecision.prevent;
          }
          if (_isDownloadUrl(request.url)) {
            _downloadFile(request.url);
            return NavigationDecision.prevent;
          }
          _maybeDownloadByHeaders(request.url);
          if (widget.adBlocking &&
              adBlockerPatterns
                  .any((pattern) => pattern.hasMatch(request.url.toString()))) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          if (_shouldIgnoreWebResourceError(error)) {
            quietLogger.w(
              'Ignoring benign web resource error: ${error.errorCode} ${error.description}',
            );
            if (mounted && tab.state is Loading) {
              setState(() {
                tab.state = BrowserState.success(tab.currentUrl);
              });
            }
            return;
          }
          _handleLoadError(tab, error.description);
        },
        onHttpError: (error) {
          if (_shouldIgnoreHttpError(tab, error)) {
            quietLogger.w(
              'Ignoring subresource HTTP error: '
              '${error.response?.statusCode} '
              '${_sanitizeUrlForLog(error.request?.uri.toString())}',
            );
            return;
          }
          _handleLoadError(tab, 'HTTP ${error.response?.statusCode}');
        },
      ));
      _syncPagePointerEvents(tab);
      if (tab.pendingNavigationUrl == null) {
        unawaited(() async {
          await _configurePlatformSpecificWebView(tab);
          if (!mounted || tab.isClosed) return;
          await _loadInitialRequestForTab(tab);
        }());
      }
    }

    try {
      return KeepAliveWrapper(
        child: Stack(
          children: [
            WebViewWidget(controller: tab.webViewController!),
            if (tab.hideStaleWebViewUntilPageFinish)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: tab.state is Loading && !_modalInteractionBlockOpen
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: TweenAnimationBuilder<double>(
                    key: ObjectKey(tab),
                    tween: Tween(begin: 0.25, end: 1.0),
                    duration: const Duration(milliseconds: 2000),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.75),
                      );
                    },
                  ),
                ),
              ),
            if (tab.pendingPasswordPrompt != null && activeTab == tab)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SavePasswordPrompt(
                  origin: tab.pendingPasswordPrompt!.origin,
                  username: tab.pendingPasswordPrompt!.username,
                  onAction: (action) => _handlePasswordPromptAction(action),
                ),
              ),
            if (_androidFullscreenWidget != null)
              Positioned.fill(child: _androidFullscreenWidget!),
          ],
        ),
      );
    } catch (e, s) {
      logger.e('Error creating WebView: $e\n$s');
      return const Center(
        child: Text('Failed to load browser.'),
      );
    }
  }

  Color _resolveAmbientToolbarTint(BuildContext context) {
    final theme = Theme.of(context);
    final seed = activeTab.ambientSeedColor ?? activeTab.detectedSeedColor;
    final base = seed ?? theme.colorScheme.primary;
    final blendTarget =
        theme.brightness == Brightness.dark ? Colors.black : Colors.white;
    final blendAmount = theme.brightness == Brightness.dark ? 0.12 : 0.08;
    return Color.lerp(base, blendTarget, blendAmount) ?? base;
  }

  Widget _buildAmbientBackground(BuildContext context) {
    final controller = _ambientController;
    final base = _resolveAmbientToolbarTint(context);
    if (controller == null) {
      return _buildAmbientBackgroundFrame(context, 0.0, base);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildAmbientBackgroundFrame(
        context,
        controller.value,
        base,
      ),
    );
  }

  Widget _buildAmbientBackgroundFrame(
    BuildContext context,
    double t,
    Color base,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = t * 2 * math.pi;
    final dx = math.cos(phase);
    final dy = math.sin(phase);
    final begin = Alignment(-0.9 + 0.5 * dx, -1.0 + 0.2 * dy);
    final end = Alignment(0.9 - 0.5 * dx, 1.0 - 0.2 * dy);

    final glowA = base.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.42 : 0.34,
    );
    final glowB = (Color.lerp(base, scheme.secondary, 0.35) ?? base).withValues(
      alpha: theme.brightness == Brightness.dark ? 0.28 : 0.22,
    );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background layer with both gradients
          Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [glowA, glowB, Colors.transparent],
                    stops: const [0.0, 0.55, 1.2],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0 + 0.3 * dx, -1.1 + 0.25 * dy),
                    radius: 2.2,
                    colors: [
                      base.withValues(
                        alpha:
                            theme.brightness == Brightness.dark ? 0.24 : 0.18,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Blur everything below (both gradients)
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: const SizedBox.expand(),
          ),
          // Subtle surface tint overlay on top of the blur
          ColoredBox(
            color: scheme.surface.withValues(alpha: 0.08),
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarPill({
    required Widget child,
    required BorderRadius borderRadius,
    required Color tintColor,
    required bool frosted,
    BoxBorder? border,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final highlight = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: frosted
              ? [Colors.transparent, Colors.transparent, Colors.transparent]
              : [
                  Colors.white.withValues(alpha: isDark ? 0.06 : 0.10),
                  Colors.transparent,
                  Colors.black.withValues(alpha: isDark ? 0.08 : 0.03),
                ],
          stops: frosted ? null : const [0.0, 0.6, 1.0],
        ),
      ),
    );

    if (!frosted) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tintColor,
          borderRadius: borderRadius,
          border: border,
        ),
        child: child,
      );
    }

    final shadow = frosted
        ? BoxShadow(
            color: Colors.black.withValues(alpha: 0.0),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(0, 0),
          )
        : BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
            blurRadius: 22,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [shadow],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: const SizedBox(),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tintColor,
                borderRadius: borderRadius,
                border: border,
              ),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(child: IgnorePointer(child: highlight)),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMacDesktop = defaultTargetPlatform == TargetPlatform.macOS;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final leadingInset = (isMacDesktop && !widget.hideAppBar)
        ? _kMacOsLeadingInsetWithTrafficLights
        : isMobilePlatform
            ? _kMobileLeadingInset
            : _kDefaultLeadingInset;
    final addressBarLeftOffset = (isMacDesktop && !widget.hideAppBar)
        ? _kMacOsAddressBarLeftOffset
        : 0.0;
    final double topToolbarInset =
        (isMacDesktop && !widget.hideAppBar) ? _kMacOsTopToolbarInset : 0.0;
    final useAmbient = _ambientActive;
    final scrollOffset = activeTab.scrollOffset;
    final hasScrolled = scrollOffset > 50;
    final scrollProgress =
        hasScrolled ? ((scrollOffset - 50) / 100).clamp(0.0, 1.0) : 0.0;
    final toolbarPillColor = useAmbient
        ? theme.colorScheme.surfaceContainerHigh
            .withValues(alpha: 0.65 + (scrollProgress * 0.35))
        : theme.colorScheme.surfaceContainerHigh;
    final addressPillColor = useAmbient
        ? theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.65 + (scrollProgress * 0.35))
        : theme.colorScheme.surfaceContainerHighest;
    final toolbarForeground = useAmbient
        ? theme.colorScheme.onSurface.withValues(alpha: 0.90)
        : theme.colorScheme.onSurfaceVariant;
    final toolbarDividerColor = useAmbient
        ? Colors.transparent
        : theme.colorScheme.outline.withValues(alpha: 0.12);

    final PreferredSizeWidget? appBarWidget = widget.hideAppBar
        ? null
        : AppBar(
            primary: isMobilePlatform,
            toolbarHeight: isMobilePlatform ? 56 : 52,
            titleSpacing: isMobilePlatform ? 8 : null,
            backgroundColor: useAmbient
                ? Colors.transparent
                : theme.appBarTheme.backgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: useAmbient && hasScrolled
                ? Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.secondary.withValues(
                            alpha: 0.25 * scrollProgress,
                          ),
                          blurRadius: 30,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                  )
                : null,
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildToolbarPill(
                  borderRadius: BorderRadius.circular(12),
                  tintColor: toolbarPillColor,
                  frosted: useAmbient,
                  border: null,
                  child: BrowserNavigationControls(
                    toolbarForeground: toolbarForeground,
                    isMobilePlatform: isMobilePlatform,
                    onBackTap: _goBack,
                    onForwardTap: _goForward,
                    onHomeTap: () {},
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ClickableIcon(
                icon: Icons.add,
                size: 20,
                color: toolbarForeground,
                padding: EdgeInsets.all(isMobilePlatform ? 7 : 8),
                onTap: _addNewTab,
              ),
              const SizedBox(width: 4),
              _buildMenuButton(
                padding: EdgeInsets.all(isMobilePlatform ? 7 : 8),
              ),
              const SizedBox(width: 4),
            ],
            title: Container(
              margin: EdgeInsets.only(left: addressBarLeftOffset, right: 4),
              child: _buildToolbarPill(
                borderRadius: BorderRadius.circular(16),
                tintColor: addressPillColor,
                frosted: useAmbient,
                border: null,
                child: BrowserAddressBar(
                  tab: activeTab,
                  toolbarForeground: toolbarForeground,
                  leadingInset: leadingInset,
                  aiSearchSuggestionsEnabled: widget.aiSearchSuggestionsEnabled,
                  useAmbient: useAmbient,
                  urlFieldLayerLink: _urlAutocompleteLayerLink,
                  urlFieldTargetKey: _urlAutocompleteTargetKey,
                  refreshTurns: _refreshIconController,
                  onSearchTap: () {
                    final text = activeTab.urlController.text;
                    final decision = resolveUrlSubmission(
                      submittedValue: text,
                      aiSearchSuggestionsEnabled:
                          widget.aiSearchSuggestionsEnabled,
                    );
                    if (decision.shouldShowAiSuggestions) {
                      _showAiSearchSuggestionsSheet();
                    }
                    if (decision.shouldLoadUrl) {
                      _removeUrlAutocompleteOverlay();
                      activeTab.urlFocusNode.unfocus();
                      _loadUrl(decision.normalizedInput);
                    }
                  },
                  onRefreshTap: _refresh,
                  onToggleMuteTap: _toggleMute,
                  onUrlChanged: (_) => _updateUrlAutocompleteOverlay(activeTab),
                  onUrlTap: () {
                    _cancelAddressBarAutoHide();
                    _setActiveTabUrlObscured(false);
                    if (widget.aiSearchSuggestionsEnabled &&
                        activeTab.urlController.text.trim().isEmpty) {
                      _showAiSearchSuggestionsSheet();
                    } else {
                      _updateUrlAutocompleteOverlay(activeTab);
                    }
                  },
                  onUrlSubmitted: (value) {
                    _removeUrlAutocompleteOverlay();
                    activeTab.urlFocusNode.unfocus();
                    final decision = resolveUrlSubmission(
                      submittedValue: value,
                      aiSearchSuggestionsEnabled:
                          widget.aiSearchSuggestionsEnabled,
                    );
                    if (decision.shouldShowAiSuggestions) {
                      _showAiSearchSuggestionsSheet();
                    }
                    if (decision.shouldLoadUrl) {
                      _loadUrl(decision.normalizedInput);
                    }
                  },
                  onAddressBarHoverChanged: _handleAddressBarHoverChanged,
                  hasMediaPlaying: activeTab.hasMediaPlaying,
                  isMuted: activeTab.isMuted,
                ),
              ),
            ),
          );

    final scaffold = Scaffold(
      backgroundColor:
          useAmbient ? Colors.transparent : theme.scaffoldBackgroundColor,
      appBar: topToolbarInset > 0 && appBarWidget != null
          ? PreferredSize(
              preferredSize: Size.fromHeight(52.0 + topToolbarInset),
              child: Column(
                children: [
                  SizedBox(height: topToolbarInset),
                  appBarWidget,
                ],
              ),
            )
          : appBarWidget,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 32,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: useAmbient
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surface,
                  border: useAmbient
                      ? null
                      : _reorderableTabs
                          ? Border(
                              bottom: BorderSide(
                                color: toolbarDividerColor,
                                width: 1,
                              ),
                            )
                          : null,
                ),
                child: MouseRegion(
                  onEnter: (_) {
                    if (defaultTargetPlatform == TargetPlatform.macOS &&
                        widget.hideAppBar &&
                        _reorderableTabs) {
                      _setWindowMovable(false);
                    }
                  },
                  onExit: (_) {
                    if (defaultTargetPlatform == TargetPlatform.macOS &&
                        widget.hideAppBar &&
                        _reorderableTabs) {
                      _setWindowMovable(true);
                    }
                  },
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (widget.hideAppBar && _reorderableTabs) {
                        _setWindowMovable(false);
                      }
                    },
                    onPointerUp: (_) {
                      if (widget.hideAppBar && _reorderableTabs) {
                        _setWindowMovable(true);
                      }
                    },
                    onPointerCancel: (_) {
                      if (widget.hideAppBar && _reorderableTabs) {
                        _setWindowMovable(true);
                      }
                    },
                    child: _reorderableTabs
                        ? ReorderableListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: tabs.length,
                            // ignore: deprecated_member_use
                            onReorder: _reorderTab,
                            onReorderStart: (_) {
                              _setWindowMovable(false);
                            },
                            onReorderEnd: (_) {
                              _setWindowMovable(true);
                            },
                            buildDefaultDragHandles: false,
                            itemBuilder: (context, index) {
                              final tab = tabs[index];
                              final isSelected = tabController.index == index;
                              return ReorderableDragStartListener(
                                key: ObjectKey(tab),
                                index: index,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => setState(
                                        () => tabController.index = index),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isSelected && !_modalInteractionBlockOpen
                                            ? Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: useAmbient ? 0.5 : 1.0)
                                            : Colors.transparent,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isSelected &&
                                                    !useAmbient &&
                                                    !_modalInteractionBlockOpen
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.2)
                                                : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: _buildTabItem(
                                          tab, index, isSelected,
                                          showDragHandle: true),
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Theme(
                            data: Theme.of(context).copyWith(
                              hoverColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                            ),
                            child: TabBar(
                              controller: tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              padding: EdgeInsets.zero,
                              dividerHeight: useAmbient ? 0.0 : 1.0,
                              overlayColor:
                                  WidgetStateProperty.all(Colors.transparent),
                              indicatorColor: _modalInteractionBlockOpen ||
                                      widget.themeMode == AppThemeMode.adjust
                                  ? Colors.transparent
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.15),
                              dividerColor: useAmbient
                                  ? Colors.transparent
                                  : toolbarDividerColor,
                              labelColor:
                                  Theme.of(context).colorScheme.onSurface,
                              unselectedLabelColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                              tabs: tabs.asMap().entries.map((entry) {
                                final index = entry.key;
                                final tab = entry.value;
                                final isSelected = tabController.index == index;
                                return Tab(
                                  height: 28,
                                  child: _buildTabItem(tab, index, isSelected),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  ignoring:
                      activeTab.urlFocusNode.hasFocus || _urlAutocompleteOpen,
                  child: _reorderableTabs
                      ? IndexedStack(
                          index: tabController.index,
                          children:
                              tabs.map((tab) => _buildTabBody(tab)).toList(),
                        )
                      : TabBarView(
                          controller: tabController,
                          children:
                              tabs.map((tab) => _buildTabBody(tab)).toList(),
                        ),
                ),
              ),
            ],
          ),
          if (widget.hideAppBar)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrowserNavigationControls(
                      toolbarForeground: toolbarForeground,
                      isMobilePlatform: isMobilePlatform,
                      onBackTap: _goBack,
                      onForwardTap: _goForward,
                      onHomeTap: _showQuickUrlPrompt,
                      showHomeButton: true,
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _addNewTab,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.add,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _showSettings,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.settings,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ),
                    ),
                    _buildMenuButton(iconSize: 18),
                  ],
                ),
              ),
            ),
          if (_dragging)
            Container(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_open,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Drop file to open',
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isOnline)
            Positioned(
              top: widget.hideAppBar ? 60 : 0,
              left: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 16,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No internet connection',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return DropTarget(
      onDragEntered: (details) => setState(() => _dragging = true),
      onDragExited: (details) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          final path = 'file://${file.path}';
          if (tabs.isEmpty) {
            _addNewTab();
          }
          _loadUrl(path);
        }
      },
      child: useAmbient
          ? Stack(
              children: [
                Positioned.fill(child: _buildAmbientBackground(context)),
                scaffold,
              ],
            )
          : scaffold,
    );
  }
}

const String disablePagePointerEventsScript = r'''
(() => {
  try {
    const blockerId = '__browserPointerBlockerStyle';
    if (!document.getElementById(blockerId)) {
      const style = document.createElement('style');
      style.id = blockerId;
      style.textContent = 'html, body, body * { pointer-events: none !important; }';
      document.documentElement.appendChild(style);
    }
    return true;
  } catch (_) {
    return false;
  }
})();
''';

const String restorePagePointerEventsScript = r'''
(() => {
  try {
    document.getElementById('__browserPointerBlockerStyle')?.remove();
    return true;
  } catch (_) {
    return false;
  }
})();
''';

const String themeProbeScript = r'''
(() => {
  const isTransparent = (color) => {
    if (!color) return true;
    const normalized = color.toLowerCase().replace(/\s+/g, '');
    return normalized === 'transparent' || normalized === 'rgba(0,0,0,0)';
  };
  const getBg = (el) => {
    if (!el) return null;
    const style = window.getComputedStyle(el);
    return style ? style.backgroundColor : null;
  };
  const normalizeColor = (raw) => {
    if (!raw || typeof raw !== 'string') return null;
    const candidate = raw.trim();
    if (!candidate) return null;
    const probe = document.createElement('div');
    probe.style.color = '';
    probe.style.color = candidate;
    if (!probe.style.color) return null;
    return probe.style.color;
  };
  const getEffectiveBg = (el) => {
    let current = el;
    let depth = 0;
    while (current && depth < 20) {
      const color = getBg(current);
      if (color && !isTransparent(color)) return color;
      current = current.parentElement;
      depth += 1;
    }
    return null;
  };
  const centerEl = document.elementFromPoint(
    window.innerWidth / 2,
    window.innerHeight / 2
  );
  const sampleBg = getEffectiveBg(centerEl);
  const bg = getEffectiveBg(document.documentElement) ||
    getEffectiveBg(document.body) || null;
  const themeColorMeta = Array.from(
    document.querySelectorAll('meta[name="theme-color"]')
  );
  const preferredThemeColor = themeColorMeta.find((meta) => {
    const media = meta.getAttribute('media');
    if (!media) return true;
    return window.matchMedia ? window.matchMedia(media).matches : false;
  }) || themeColorMeta[0] || null;
  const themeColor = normalizeColor(preferredThemeColor
    ?.getAttribute('content') || null);
  const metaColorScheme = document.querySelector('meta[name="color-scheme"]')
    ?.getAttribute('content') || null;
  const colorScheme = window.getComputedStyle(document.documentElement)
    .colorScheme || null;
  const textColor = window.getComputedStyle(document.body || document.documentElement)
    .color || null;
  const accentHintEl = document.querySelector(
    'header, nav, [role="banner"], [class*="header"], [class*="navbar"]'
  ) || document.querySelector(
    'a, button, [role="button"], [class*="btn"], [class*="link"]'
  );
  const accentHint = accentHintEl
    ? (getEffectiveBg(accentHintEl) ||
      window.getComputedStyle(accentHintEl).color || null)
    : null;
  const prefersDark = window.matchMedia &&
    window.matchMedia('(prefers-color-scheme: dark)').matches;
  return JSON.stringify({
    bg,
    sampleBg,
    themeColor,
    accentHint,
    metaColorScheme,
    colorScheme,
    textColor,
    prefersDark
  });
})()
''';

const String exitFullscreenScript = r'''
(function() {
  const exit =
    document.exitFullscreen ||
    document.webkitExitFullscreen ||
    document.mozCancelFullScreen ||
    document.msExitFullscreen;
  if (exit) {
    exit.call(document);
  }
  const videos = document.querySelectorAll('video');
  for (const video of videos) {
    if (video.webkitDisplayingFullscreen && video.webkitExitFullscreen) {
      video.webkitExitFullscreen();
    }
  }
  return true;
})();
''';

const String installFullscreenBridgeScript = r'''
(function() {
  if (window.__browserFullscreenBridgeInstalled) {
    return true;
  }
  window.__browserFullscreenBridgeInstalled = true;

  function notifyFullscreenState(isFullscreen) {
    try {
      FullscreenChannel.postMessage(isFullscreen ? 'enter' : 'exit');
    } catch (_) {}
  }

  function syncDocumentFullscreenState() {
    const activeElement =
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement ||
      document.msFullscreenElement;
    notifyFullscreenState(!!activeElement);
  }

  function bindVideoElement(video) {
    if (!video || video.__browserFullscreenVideoBound) {
      return;
    }
    video.__browserFullscreenVideoBound = true;
    video.addEventListener('webkitbeginfullscreen', function() {
      notifyFullscreenState(true);
    });
    video.addEventListener('webkitendfullscreen', function() {
      notifyFullscreenState(false);
    });
  }

  function bindExistingVideos() {
    const videos = document.querySelectorAll('video');
    for (const video of videos) {
      bindVideoElement(video);
    }
  }

  document.addEventListener('fullscreenchange', syncDocumentFullscreenState, true);
  document.addEventListener('webkitfullscreenchange', syncDocumentFullscreenState, true);
  document.addEventListener('mozfullscreenchange', syncDocumentFullscreenState, true);
  document.addEventListener('MSFullscreenChange', syncDocumentFullscreenState, true);

  const observer = new MutationObserver(bindExistingVideos);
  observer.observe(document.documentElement || document.body, {
    childList: true,
    subtree: true,
  });

  bindExistingVideos();
  syncDocumentFullscreenState();
  return true;
})();
''';

const String removeFontOverrideScript = r'''
(() => {
  const style = document.getElementById('browser-font-override-style');
  if (style) {
    style.remove();
  }
  return true;
})();
''';

String buildFontOverrideScript(String fontFamily) {
  return '''
(() => {
  const fontFamily = $fontFamily;
  const styleId = 'browser-font-override-style';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent =
    'html, body, body * { font-family: ' + fontFamily + ' !important; }';
  return true;
})();
''';
}

const String clearInitialFocusScript = r'''
(() => {
  try {
    const el = document.activeElement;
    if (!el || el === document.body || el === document.documentElement) {
      return true;
    }
    const tag = (el.tagName || '').toLowerCase();
    if (!tag) return true;
    const isEditable =
      el.isContentEditable ||
      tag === 'input' ||
      tag === 'textarea' ||
      tag === 'select';
    if (isEditable) return true;
    if (typeof el.blur === 'function') el.blur();
    return true;
  } catch (_) {
    return false;
  }
})();
''';

const String isPageUserInteractedScript = r'''
(() => {
  try { return !!window.__browserUserInteracted; } catch (_) { return false; }
})();
''';

const String installInitialFocusInterceptorScript = r'''
(() => {
  try {
    const flag = '__browserInitialFocusInterceptorInstalled';
    if (window[flag]) return true;
    window[flag] = true;

    const interactFlag = '__browserUserInteracted';
    if (window[interactFlag] == null) window[interactFlag] = false;

    const isEditable = (el) => {
      if (!el) return false;
      const tag = (el.tagName || '').toLowerCase();
      if (el.isContentEditable) return true;
      return tag === 'input' || tag === 'textarea' || tag === 'select';
    };

    const styleId = '__browser-initial-focus-style';
    const ensureSuppressionStyle = () => {
      let style = document.getElementById(styleId);
      if (style) return style;
      style = document.createElement('style');
      style.id = styleId;
      style.textContent = `
*:focus:not(input):not(textarea):not(select):not([contenteditable="true"]),
*:focus-visible:not(input):not(textarea):not(select):not([contenteditable="true"]) {
  outline: none !important;
  box-shadow: none !important;
}`;
      (document.head || document.documentElement).appendChild(style);
      return style;
    };

    const removeSuppressionStyle = () => {
      const style = document.getElementById(styleId);
      if (style) style.remove();
    };

    ensureSuppressionStyle();

    const blurIfUnwanted = (el) => {
      if (window[interactFlag]) return;
      if (!el || el === document.body || el === document.documentElement) return;
      if (isEditable(el)) return;
      if (typeof el.blur === 'function') el.blur();
    };

    const onFocusIn = (e) => {
      blurIfUnwanted(e && e.target ? e.target : document.activeElement);
    };
    document.addEventListener('focusin', onFocusIn, true);

    const onPointerDown = () => {
      window[interactFlag] = true;
      removeSuppressionStyle();
      document.removeEventListener('focusin', onFocusIn, true);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown, true);
    };

    const onKeyDown = (e) => {
      if (!e) return;
      window[interactFlag] = true;
      removeSuppressionStyle();
      document.removeEventListener('focusin', onFocusIn, true);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown, true);
    };

    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('keydown', onKeyDown, true);

    blurIfUnwanted(document.activeElement);

    const WINDOW_MS = 1500;
    setTimeout(() => {
      if (window[interactFlag]) return;
      removeSuppressionStyle();
      document.removeEventListener('focusin', onFocusIn, true);
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown, true);
      window[interactFlag] = true;
    }, WINDOW_MS);
    return true;
  } catch (_) {
    return false;
  }
})();
''';

const String ensurePageTapListenerScript = r'''
(() => {
  try {
    if (window.pageTapListenerAdded) return true;
    const notifyTap = function() {
      try { PageTapChannel.postMessage('tap'); } catch (_) {}
      try { window.__browserUserInteracted = true; } catch (_) {}
    };
    window.addEventListener('pointerdown', notifyTap, true);
    window.pageTapListenerAdded = true;
    return true;
  } catch (_) {
    return false;
  }
})();
''';

const String faviconDetectionScript = r'''
(() => {
  const toAbs = (href) => {
    try { return new URL(href, window.location.href).href; } catch (_) { return null; }
  };
  const relScore = (rel) => {
    if (rel === 'icon' || rel === 'shortcut icon') return 0;
    if (rel.includes('apple-touch-icon')) return 1;
    if (rel.includes('icon')) return 2;
    return 9;
  };
  const extScore = (href) => {
    const h = href.toLowerCase();
    if (h.endsWith('.ico')) return 0;
    if (h.endsWith('.png')) return 1;
    if (h.endsWith('.jpg') || h.endsWith('.jpeg')) return 2;
    if (h.endsWith('.gif') || h.endsWith('.webp')) return 3;
    if (h.endsWith('.svg')) return 9;
    return 4;
  };

  const links = Array.from(document.querySelectorAll('link[rel][href]'));
  const candidates = links
    .map((link) => {
      const rel = (link.getAttribute('rel') || '').toLowerCase().trim();
      const href = (link.getAttribute('href') || '').trim();
      if (!href || href.startsWith('data:')) return null;
      if (rel.includes('mask-icon')) return null;
      if (!rel.includes('icon')) return null;
      const abs = toAbs(href);
      if (!abs) return null;
      return { abs, rel, relOrder: relScore(rel), extOrder: extScore(abs) };
    })
    .filter(Boolean)
    .sort((a, b) => {
      if (a.extOrder !== b.extOrder) return a.extOrder - b.extOrder;
      return a.relOrder - b.relOrder;
    });

  if (candidates.length > 0) return candidates[0].abs;
  return null;
})();
''';

const String spaNavigationScript = r'''
if (!window.historyListenerAdded) {
  const postHistoryUpdate = function() {
    HistoryChannel.postMessage(JSON.stringify({
      url: window.location.href,
      title: document.title || ''
    }));
  };
  const postTitleUpdate = function() {
    TitleChangeChannel.postMessage(JSON.stringify({
      url: window.location.href,
      title: document.title || ''
    }));
  };
  const scheduleHistoryUpdate = function() {
    postHistoryUpdate();
    setTimeout(postTitleUpdate, 0);
    requestAnimationFrame(postTitleUpdate);
    setTimeout(postTitleUpdate, 150);
  };
  window.addEventListener('popstate', function(event) {
    scheduleHistoryUpdate();
  });
  // Override pushState and replaceState to capture programmatic changes
  window.originalPushState = window.history.pushState;
  window.history.pushState = function(state, title, url) {
    window.originalPushState.call(this, state, title, url);
    scheduleHistoryUpdate();
  };
  window.originalReplaceState = window.history.replaceState;
  window.history.replaceState = function(state, title, url) {
    window.originalReplaceState.call(this, state, title, url);
    scheduleHistoryUpdate();
  };
  const titleTarget = document.querySelector('title') || document.head;
  if (titleTarget && !window.titleObserverAdded) {
    new MutationObserver(function() {
      postTitleUpdate();
    }).observe(titleTarget, {
      childList: true,
      subtree: true,
      characterData: true,
    });
    window.titleObserverAdded = true;
  }
  postTitleUpdate();
  window.historyListenerAdded = true;
}
if (!window.pageTapListenerAdded) {
  const notifyTap = function() {
    try { PageTapChannel.postMessage('tap'); } catch (_) {}
  };
  window.addEventListener('pointerdown', notifyTap, true);
  window.pageTapListenerAdded = true;
}
if (!window.scrollOffsetListenerAdded) {
  let lastScrollOffset = 0;
  const notifyScroll = function() {
    const offset = window.pageYOffset || document.documentElement.scrollTop || 0;
    if (Math.abs(offset - lastScrollOffset) > 5) {
      lastScrollOffset = offset;
      try { ScrollOffsetChannel.postMessage(String(offset)); } catch (_) {}
    }
  };
  window.addEventListener('scroll', notifyScroll, { passive: true });
  window.scrollOffsetListenerAdded = true;
}
true;
''';

const String clearStorageScript = r'''
localStorage.clear(); sessionStorage.clear(); true;
''';

String buildMediaBridgeScript({required bool muted}) {
  final mutedLiteral = muted ? 'true' : 'false';
  return '''
    (function() {
      const desiredMuted = $mutedLiteral;
      window.__browserMutedPreference = desiredMuted;
      if (window.__browserMuteEnforcerInterval &&
          window.__browserMutedPreference !== true) {
        clearInterval(window.__browserMuteEnforcerInterval);
        window.__browserMuteEnforcerInterval = null;
      }

      const getMediaElements = function(root) {
        if (!root) return [];
        if (root.matches && root.matches('video, audio')) {
          return [root];
        }
        if (!root.querySelectorAll) return [];
        return Array.from(root.querySelectorAll('video, audio'));
      };

      const applyMutePreference = function(media) {
        if (!media) return;
        const shouldMute = window.__browserMutedPreference === true;
        media.muted = shouldMute;
        if ('defaultMuted' in media) {
          media.defaultMuted = shouldMute;
        }
      };

      const applyMutePreferenceToAll = function(root) {
        getMediaElements(root).forEach(applyMutePreference);
      };

      const reportPlaybackState = function() {
        const mediaElements = getMediaElements(document);
        const hasPlayingMedia = mediaElements.some(function(media) {
          return !media.paused && !media.ended && media.currentSrc !== '';
        });
        try {
          MediaStateChannel.postMessage(JSON.stringify({
            type: 'playback',
            hasPlayingMedia: hasPlayingMedia
          }));
        } catch (_) {}
      };

      const attachMedia = function(media) {
        if (!media || media.__browserMediaBridgeAttached) return;
        media.__browserMediaBridgeAttached = true;
        applyMutePreference(media);
        ['play', 'playing', 'pause', 'ended', 'emptied', 'loadstart', 'loadedmetadata', 'volumechange'].forEach(function(eventName) {
          media.addEventListener(eventName, function() {
            applyMutePreference(media);
            reportPlaybackState();
          });
        });
      };

      const attachAllMedia = function(root) {
        getMediaElements(root).forEach(attachMedia);
      };

      if (!window.__browserMediaBridgeObserver) {
        window.__browserMediaBridgeObserver = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            mutation.addedNodes.forEach(function(node) {
              attachAllMedia(node);
            });
            if (mutation.type === 'attributes') {
              attachAllMedia(mutation.target);
              applyMutePreferenceToAll(mutation.target);
            }
          });
          reportPlaybackState();
        });
        window.__browserMediaBridgeObserver.observe(document.documentElement || document, {
          attributes: true,
          attributeFilter: ['src'],
          childList: true,
          subtree: true
        });
      }

      attachAllMedia(document);
      applyMutePreferenceToAll(document);
      if (window.__browserMutedPreference === true && !window.__browserMuteEnforcerInterval) {
        window.__browserMuteEnforcerInterval = setInterval(function() {
          applyMutePreferenceToAll(document);
          reportPlaybackState();
        }, 250);
      }
      reportPlaybackState();
      return true;
    })();
  ''';
}

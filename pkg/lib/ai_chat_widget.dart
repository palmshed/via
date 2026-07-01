// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'ai_service.dart';
import 'callout_box.dart';

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({required this.role, required this.content});

  final _ChatRole role;
  final String content;
}

class AiChatWidget extends HookWidget {
  const AiChatWidget({
    super.key,
    this.pageTitle,
    this.pageUrl,
    this.ambientEnabled = false,
    this.accentColor,
  });

  final String? pageTitle;
  final String? pageUrl;
  final bool ambientEnabled;
  final Color? accentColor;

  static final RegExp _leadingTrailingEmoji = RegExp(
    r'^[\p{So}\p{Sk}\p{Cs}\s]+|[\p{So}\p{Sk}\p{Cs}\s]+$',
    unicode: true,
  );
  static final RegExp _trailingSeparators = RegExp(r'[:\-\u2013\u2014|/.\s]+$');
  static final RegExp _symbolOnlySuffix = RegExp(
    r':\s*([\p{So}\p{Sk}\p{Cs}]+)\s*$',
    unicode: true,
  );
  static String? _normalizeContextLabel(String? raw, String? fallback) {
    final trimmedRaw = raw?.trim() ?? '';
    final symbolSuffixMatch = _symbolOnlySuffix.firstMatch(trimmedRaw);
    final preservedSymbolSuffix = symbolSuffixMatch?.group(1)?.trim();
    final cleaned = trimmedRaw.replaceAll(_leadingTrailingEmoji, '');
    final normalized = cleaned.replaceAll(_trailingSeparators, '').trim();
    if (normalized.isNotEmpty && normalized.toLowerCase() != 'null') {
      if (preservedSymbolSuffix != null && preservedSymbolSuffix.isNotEmpty) {
        return '$normalized $preservedSymbolSuffix';
      }
      return normalized;
    }
    final fallbackClean = fallback?.trim();
    if (fallbackClean != null &&
        fallbackClean.isNotEmpty &&
        fallbackClean.toLowerCase() != 'null') {
      return fallbackClean;
    }
    return null;
  }

  static List<String> _starterPromptsForContext(String? pageUrl) {
    final host = Uri.tryParse(pageUrl ?? '')?.host.toLowerCase() ?? '';
    if (host == 'github.com' || host == 'www.github.com') {
      return const [
        'Summarize repo',
        'Explain structure',
        'What to read first',
      ];
    }
    return const ['Summarize this', 'Key points', 'Explain this page'];
  }

  static String? _starterPromptInstruction({
    required String prompt,
    required String? pageTitle,
    required String? pageUrl,
  }) {
    final normalizedPrompt = prompt.trim().toLowerCase();
    final title = pageTitle?.trim().isNotEmpty == true
        ? pageTitle!.trim()
        : 'unknown';
    final url = pageUrl?.trim().isNotEmpty == true
        ? pageUrl!.trim()
        : 'unknown';
    final pageContext = 'Current page title: "$title". Current page URL: $url.';

    switch (normalizedPrompt) {
      case 'summarize repo':
        return '$pageContext Summarize the repository this GitHub page belongs '
            'to using only the repository context visible or directly implied '
            'by the current page. If the current page is an issue, pull request, '
            'or subpage, still summarize the repository rather than the issue or '
            'thread. Do not guess the language, stack, or architecture if it is '
            'not visible from the current page. Be concise and say when details '
            'are not visible.';
      case 'explain structure':
        return '$pageContext Explain the repository structure only from what is '
            'visible on the current GitHub page. If the file tree is not visible, '
            'say that the structure cannot be determined from this view instead of '
            'guessing.';
      case 'what to read first':
        return '$pageContext Recommend what to read first in this repository '
            'based only on the current GitHub page context. Prefer visible items '
            'such as README, pinned files, directories, issues, or pull requests. '
            'Do not invent files or project details that are not shown.';
      case 'summarize this':
        return '$pageContext Summarize the current page based only on the visible '
            'page context. Do not assume details that are not shown.';
      case 'key points':
        return '$pageContext List the key points from the current page based only '
            'on the visible page context.';
      case 'explain this page':
        return '$pageContext Explain what this current page is showing and why it '
            'matters, based only on the visible page context.';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.width < 720;
    final messages = useState<List<_ChatMessage>>([]);
    final controller = useTextEditingController();
    final composerFocusNode = useFocusNode();
    final scrollController = useScrollController();
    final isLoading = useState(false);
    final aiService = useMemoized(() => AiService(), []);

    final pageUri = Uri.tryParse(pageUrl ?? '');
    final hostname = pageUri?.host;
    final compactUrl = hostname != null && hostname.isNotEmpty
        ? (hostname.startsWith('www.') ? hostname.substring(4) : hostname)
        : null;
    final contextLabel = _normalizeContextLabel(pageTitle, compactUrl);
    final starterPrompts = _starterPromptsForContext(pageUrl);
    final pageContext =
        'Current page: ${pageTitle != null ? 'Title: "$pageTitle"' : 'Title unknown'}, URL: ${pageUrl ?? 'unknown'}. ';
    String buildPrompt(String text) {
      final lowerText = text.toLowerCase();
      if (lowerText.contains('page') ||
          lowerText.contains('website') ||
          lowerText.contains('repo') ||
          lowerText.contains('repository') ||
          lowerText.contains('structure') ||
          lowerText.contains('read first') ||
          lowerText.contains('key points') ||
          lowerText.contains('summarize') ||
          lowerText.contains('summary') ||
          lowerText.contains('tell me about') ||
          lowerText.contains('what is this') ||
          lowerText.contains('current site')) {
        return pageContext + text;
      }
      return text;
    }

    Future<void> sendMessage([String? presetText]) async {
      final text = (presetText ?? controller.text).trim();
      if (text.isEmpty || isLoading.value) return;

      messages.value = [
        ...messages.value,
        _ChatMessage(role: _ChatRole.user, content: text),
      ];
      controller.clear();
      isLoading.value = true;
      composerFocusNode.requestFocus();

      try {
        final promptToSend =
            _starterPromptInstruction(
              prompt: text,
              pageTitle: pageTitle,
              pageUrl: pageUrl,
            ) ??
            buildPrompt(text);
        final response = await aiService.generateResponse(promptToSend);
        messages.value = [
          ...messages.value,
          _ChatMessage(role: _ChatRole.assistant, content: response),
        ];
      } catch (e) {
        messages.value = [
          ...messages.value,
          _ChatMessage(role: _ChatRole.assistant, content: 'Error: $e'),
        ];
      } finally {
        isLoading.value = false;
      }

      if (messages.value.length > 50) {
        messages.value = messages.value.sublist(messages.value.length - 50);
      }
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
      return null;
    }, [messages.value.length, isLoading.value]);

    final effectiveAccent = accentColor ?? colorScheme.primary;
    final shellColor = ambientEnabled
        ? colorScheme.surface.withValues(alpha: 0.97)
        : colorScheme.surface;
    final shellBorderColor = colorScheme.outline.withValues(
      alpha: ambientEnabled ? 0.08 : 0.12,
    );
    final panelColor =
        Color.lerp(
          colorScheme.surfaceContainerHigh,
          colorScheme.surface,
          0.72,
        ) ??
        colorScheme.surfaceContainerHigh;
    final userBubbleColor =
        Color.lerp(effectiveAccent, colorScheme.tertiary, 0.20) ??
        effectiveAccent;
    final assistantBubbleColor =
        Color.lerp(
          colorScheme.surfaceContainerHighest,
          colorScheme.secondaryContainer,
          0.32,
        ) ??
        colorScheme.surfaceContainerHighest;
    final dialogWidth = isCompact
        ? (screenSize.width - 24).clamp(320.0, 560.0)
        : (screenSize.width * 0.34).clamp(520.0, 680.0);
    final dialogMaxHeight = isCompact
        ? (screenSize.height - 24).clamp(520.0, 780.0)
        : (screenSize.height - 110).clamp(420.0, 620.0);

    final textVal = useValueListenable(controller);
    final hasText = textVal.text.trim().isNotEmpty;
    final isFocused = useState(false);

    useEffect(() {
      void listener() {
        isFocused.value = composerFocusNode.hasFocus;
      }
      composerFocusNode.addListener(listener);
      return () => composerFocusNode.removeListener(listener);
    }, [composerFocusNode]);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 12 : 36,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogMaxHeight,
          minHeight: isCompact ? 480 : 420,
        ),
        decoration: BoxDecoration(
          color: shellColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: shellBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: ambientEnabled ? 0.10 : 0.16,
              ),
              blurRadius: ambientEnabled ? 24 : 36,
              spreadRadius: -10,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: Stack(
            children: [
              if (ambientEnabled) ...[
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: const SizedBox(),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.1, -1.0),
                        radius: 1.8,
                        colors: [
                          effectiveAccent.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.24
                                : 0.16,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Column(
                children: [
                  _ChromePanel(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    tintColor: panelColor.withValues(
                      alpha: ambientEnabled ? 0.96 : 1.0,
                    ),
                    frosted: ambientEnabled,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withValues(
                          alpha: ambientEnabled ? 0.07 : 0.09,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Assistant',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                  ),
                                ),
                                if (contextLabel != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    contextLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: messages.value.isEmpty
                        ? _EmptyChatState(
                            starterPrompts: starterPrompts,
                            onPromptSelected: sendMessage,
                            accentColor: effectiveAccent,
                            compactMode: true,
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                            itemCount:
                                messages.value.length +
                                (isLoading.value ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= messages.value.length) {
                                return _TypingBubble(
                                  accentColor: effectiveAccent,
                                  ambientEnabled: ambientEnabled,
                                );
                              }
                              return _MessageBubble(
                                message: messages.value[index],
                                userBubbleColor: userBubbleColor,
                                assistantBubbleColor: assistantBubbleColor,
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(
                          alpha: ambientEnabled ? 0.94 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isFocused.value
                              ? effectiveAccent.withValues(alpha: 0.8)
                              : colorScheme.outline.withValues(alpha: 0.16),
                          width: isFocused.value ? 1.5 : 1.0,
                        ),
                        boxShadow: isFocused.value
                            ? [
                                BoxShadow(
                                  color: effectiveAccent.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              focusNode: composerFocusNode,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              textAlignVertical: TextAlignVertical.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                height: 1.25,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ask a question...',
                                hintStyle: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.55),
                                    ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: hasText
                                  ? effectiveAccent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: IconButton(
                              onPressed: isLoading.value
                                  ? null
                                  : () => sendMessage(),
                              hoverColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              splashColor: Colors.transparent,
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.arrow_upward_rounded,
                                size: 16,
                                color: hasText
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({
    required this.starterPrompts,
    required this.onPromptSelected,
    required this.accentColor,
    this.compactMode = false,
  });

  final List<String> starterPrompts;
  final ValueChanged<String> onPromptSelected;
  final Color accentColor;
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    'assets/icons/menu_bar_icon.png',
                    width: 20,
                    height: 20,
                    color: colorScheme.primary.withValues(alpha: 0.65),
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.assistant_navigation,
                      size: 18,
                      color: colorScheme.primary.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Via Assistant',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ask questions about the current page, summarize content, or chat freely.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: starterPrompts.map((prompt) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.10),
                            width: 0.5,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onPromptSelected(prompt),
                            hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _getPromptIcon(prompt),
                                    size: 13,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      prompt,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 13,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPromptIcon(String prompt) {
    final p = prompt.toLowerCase();
    if (p.contains('summarize')) return Icons.summarize_outlined;
    if (p.contains('points') || p.contains('key')) return Icons.list_alt_rounded;
    if (p.contains('explain') || p.contains('structure')) return Icons.explore_outlined;
    if (p.contains('read')) return Icons.menu_book_rounded;
    return Icons.chat_bubble_outline_rounded;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.userBubbleColor,
    required this.assistantBubbleColor,
  });

  final _ChatMessage message;
  final Color userBubbleColor;
  final Color assistantBubbleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.role == _ChatRole.user;
    final bubbleColor = isUser ? userBubbleColor : assistantBubbleColor;
    final textColor = isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    final child = isUser
        ? Text(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontSize: 13,
              height: 1.3,
            ),
          )
        : _AssistantMessageContent(content: message.content);

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 6),
          bottomRight: Radius.circular(isUser ? 6 : 18),
        ),
      ),
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [Flexible(child: bubble)],
      ),
    );
  }
}

class _AssistantMessageContent extends StatelessWidget {
  const _AssistantMessageContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEmphasis =
        content.contains('**') ||
        content.contains('*') ||
        content.toLowerCase().contains('warning') ||
        content.toLowerCase().contains('error') ||
        content.toLowerCase().contains('suggestion') ||
        content.toLowerCase().contains('option');

    final body = MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.35),
        listBullet: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        h1: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        h2: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        codeblockPadding: const EdgeInsets.all(10),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
    );

    if (!hasEmphasis) return body;
    return CalloutBox(child: body);
  }
}

class _TypingBubble extends HookWidget {
  const _TypingBubble({
    required this.accentColor,
    required this.ambientEnabled,
  });

  final Color accentColor;
  final bool ambientEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ticker = useState(0);

    useEffect(() {
      final timer = Stream.periodic(
        const Duration(milliseconds: 420),
      ).listen((_) => ticker.value = (ticker.value + 1) % 3);
      return timer.cancel;
    }, const []);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: ambientEnabled ? 0.80 : 1.0,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(
              'Thinking${'.' * (ticker.value + 1)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChromePanel extends StatelessWidget {
  const _ChromePanel({
    required this.child,
    required this.borderRadius,
    required this.tintColor,
    required this.frosted,
    this.border,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color tintColor;
  final bool frosted;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
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

    return ClipRRect(
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
    );
  }
}

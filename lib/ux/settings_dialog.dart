// SPDX-License-Identifier: MIT
//
// Copyright 2026 Palmshed. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../features/firebase_config_store.dart';
import 'password_vault_screen.dart';
import '../features/theme_utils.dart';
import '../features/update_service.dart';
import '../main.dart' show profileManager;
import '../models/user_profile.dart';
import '../utils/url_utils.dart';

class SettingsDialog extends HookWidget {
  const SettingsDialog({
    super.key,
    this.onSettingsChanged,
    this.onClearCaches,
    this.onClearAllData,
    this.onThemePreviewChanged,
    this.currentTheme,
    required this.aiAvailable,
    this.aiSearchSuggestionsEnabled = false,
    this.advancedCacheEnabled = false,
    this.ambientToolbarEnabled = false,
    this.autoHideAddressBarEnabled = false,
    this.onOpenHelp,
  });

  final void Function()? onSettingsChanged;
  final void Function()? onClearCaches;
  final void Function(bool factoryReset)? onClearAllData;
  final void Function(AppThemeMode mode)? onThemePreviewChanged;
  final AppThemeMode? currentTheme;
  final bool aiAvailable;
  final bool aiSearchSuggestionsEnabled;
  final bool advancedCacheEnabled;
  final bool ambientToolbarEnabled;
  final bool autoHideAddressBarEnabled;
  final void Function()? onOpenHelp;

  String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'system';
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.adjust:
        return 'adjust (page)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const compactDensity = VisualDensity(horizontal: -2, vertical: -2);

    final refreshIconController = useAnimationController(
      duration: const Duration(milliseconds: 1000),
    );

    final homepage = useState<String?>(null);
    final hideAppBar = useState(false);
    final useModernUserAgent = useState(false);
    final privateBrowsing = useState(false);
    final originalPrivateBrowsing = useRef<bool?>(null);
    final adBlocking = useState(false);
    final strictMode = useState(false);
    final passwordManagerEnabled = useState(false);
    final reorderableTabs = useState(false);
    final tabFaviconBadgeEnabled = useState(false);
    final autoHideAddressBarEnabled = useState(this.autoHideAddressBarEnabled);
    final aiSearchSuggestionsEnabled =
        useState(this.aiSearchSuggestionsEnabled);
    final advancedCacheEnabled = useState(this.advancedCacheEnabled);
    final ambientToolbarEnabled = useState(this.ambientToolbarEnabled);
    final urlAutocompleteSuggestionRemovalEnabled = useState(false);
    final selectedTheme =
        useState<AppThemeMode>(currentTheme ?? AppThemeMode.system);
    final homepageController = useTextEditingController();
    final settingsScrollController = useScrollController();

    final firebaseApiKey = useTextEditingController();
    final firebaseAppId = useTextEditingController();
    final firebaseSenderId = useTextEditingController();
    final firebaseProjectId = useTextEditingController();
    final firebaseStorageBucket = useTextEditingController();
    final showFirebaseConfig = useState(false);
    final loadedFirebaseConfig =
        useRef<Map<String, String>>(<String, String>{});
    final lastSettingsProfileId = useRef<String?>(null);

    final updateService = useMemoized(() => UpdateService());
    final isCheckingUpdate = useState(false);
    final localUpdateInfo = useState<UpdateInfo?>(null);
    final effectiveUpdateInfo = localUpdateInfo.value;
    final downloadProgress = useState<double?>(null);

    Future<void> handleUpdate(UpdateInfo info) async {
      final sizeMB = (info.size / (1024 * 1024)).round();
      final sizeText = sizeMB > 0 ? ' (~${sizeMB}MB)' : '';

      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
          title: Text(
            'Update to ${info.version}',
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
          ),
          content: Text('New version available$sizeText. Install now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: ButtonStyle(
                overlayColor: WidgetStateProperty.all(Colors.transparent),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ButtonStyle(
                overlayColor: WidgetStateProperty.all(Colors.transparent),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        downloadProgress.value = 0.0;
        final file = await updateService.downloadUpdate(
          info.downloadUrl,
          info.version,
          (progress) => downloadProgress.value = progress,
          info.checksum,
        );
        downloadProgress.value = null;

        if (file != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download complete. Installing...')),
          );

          if (Platform.isMacOS) {
            try {
              final appName = 'Via.app';
              final appPath = '/Applications/$appName';

              final mountResult = await Process.run(
                  'hdiutil', ['attach', file.path, '-nobrowse']);
              if (mountResult.exitCode != 0) {
                throw Exception('Failed to mount DMG: ${mountResult.stderr}');
              }

              final mountOutput = mountResult.stdout.toString();
              final volumeLine = mountOutput.split('\n').firstWhere(
                    (line) => line.contains('/Volumes/'),
                    orElse: () => '',
                  );
              final volumePathMatch =
                  RegExp(r'(/Volumes/[^\r\n]*)').firstMatch(volumeLine);
              final volumePath = volumePathMatch?.group(1)?.trim() ?? '';
              if (volumePath.isEmpty) {
                await Process.run('hdiutil', ['detach', mountOutput.trim()]);
                throw Exception('Could not find mounted volume');
              }
              final sourceApp = '$volumePath/$appName';

              if (!await File(sourceApp).exists()) {
                await Process.run('hdiutil', ['detach', volumePath]);
                throw Exception('App not found in DMG');
              }

              final backupPath = '$appPath.backup';
              if (await Directory(appPath).exists()) {
                await Process.run('mv', [appPath, backupPath]);
              }

              final cpResult = await Process.run(
                  'ditto', ['-rsrc', sourceApp, '/Applications/']);
              if (cpResult.exitCode != 0) {
                if (await Directory(backupPath).exists()) {
                  await Process.run('mv', [backupPath, appPath]);
                }
                await Process.run('hdiutil', ['detach', volumePath]);
                throw Exception('Failed to copy app: ${cpResult.stderr}');
              }

              await Process.run('hdiutil', ['detach', volumePath]);

              if (await Directory(backupPath).exists()) {
                await Process.run('rm', ['-rf', backupPath]);
              }

              await Process.run('open', ['/Applications/$appName']);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Update installed. Restarting...'),
                  duration: Duration(seconds: 5),
                ),
              );

              exit(0);
            } catch (e) {
              debugPrint('Installation failed: $e');
              await Process.run('open', [file.path]);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Installation failed. Update downloaded to ${file.path}. Drag to Applications to install manually.'),
                    duration: const Duration(seconds: 15),
                  ),
                );
              }
            }
          } else if (Platform.isWindows) {
            try {
              await Process.run(file.path, []);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Update installer launched. Follow the prompts to complete installation.'),
                  duration: Duration(seconds: 10),
                ),
              );
            } catch (e) {
              debugPrint('Failed to launch installer: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Update downloaded to: ${file.path}. Run the installer manually.')),
              );
            }
          } else if (Platform.isLinux) {
            try {
              await Process.run('xdg-open', [file.path]);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Update package opened. Use your package manager to install it.'),
                  duration: Duration(seconds: 10),
                ),
              );
            } catch (e) {
              debugPrint('Failed to open package: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Update downloaded to: ${file.path}. Install manually with your package manager.')),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Update downloaded to: ${file.path}. Please install manually.')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to download update')),
          );
        }
      }
    }

    Future<void> checkUpdate() async {
      refreshIconController.forward(from: 0.0);
      isCheckingUpdate.value = true;
      try {
        final info = await updateService.checkForUpdates();
        localUpdateInfo.value = info;
        if (info != null) {
          await handleUpdate(info);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Browser is up to date')),
          );
        }
      } catch (e) {
        debugPrint('Update check failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Update check failed. Please try again later.')),
        );
      } finally {
        isCheckingUpdate.value = false;
      }
    }

    useEffect(() {
      var cancelled = false;
      Future<void> loadPreferences() async {
        final prefs = await SharedPreferences.getInstance();
        if (cancelled) return;
        String scopedKey(String key) => profileManager.getScopedStorageKey(key);
        bool readBool(String key, {required bool defaultValue}) =>
            prefs.getBool(scopedKey(key)) ?? defaultValue;

        String? readString(String key) => prefs.getString(scopedKey(key));

        final storedHomepage = readString(homepageKey);
        final resolvedHomepage = (storedHomepage?.isNotEmpty ?? false)
            ? storedHomepage!
            : defaultHomepageUrl;
        hideAppBar.value = readBool(hideAppBarKey, defaultValue: false);
        useModernUserAgent.value =
            readBool(useModernUserAgentKey, defaultValue: false);
        privateBrowsing.value =
            readBool(privateBrowsingKey, defaultValue: false);
        originalPrivateBrowsing.value = privateBrowsing.value;
        adBlocking.value = readBool(adBlockingKey, defaultValue: false);
        strictMode.value = readBool(strictModeKey, defaultValue: false);
        passwordManagerEnabled.value =
            readBool(passwordManagerEnabledKey, defaultValue: false);
        reorderableTabs.value =
            readBool(reorderableTabsKey, defaultValue: false);
        tabFaviconBadgeEnabled.value =
            readBool(tabFaviconBadgeEnabledKey, defaultValue: false);
        aiSearchSuggestionsEnabled.value =
            readBool(aiSearchSuggestionsEnabledKey, defaultValue: false);
        advancedCacheEnabled.value =
            readBool(advancedCacheEnabledKey, defaultValue: false);
        ambientToolbarEnabled.value =
            readBool(ambientToolbarEnabledKey, defaultValue: false);
        urlAutocompleteSuggestionRemovalEnabled.value = readBool(
          urlAutocompleteSuggestionRemovalEnabledKey,
          defaultValue: false,
        );
        autoHideAddressBarEnabled.value =
            readBool(autoHideAddressBarKey, defaultValue: false);
        final themeString = readString(themeModeKey);
        selectedTheme.value = themeString == null
            ? (currentTheme ?? AppThemeMode.system)
            : AppThemeMode.values.firstWhere(
                (m) => m.name == themeString,
                orElse: () => currentTheme ?? AppThemeMode.system,
              );

        final firebaseConfig = await FirebaseConfigStore.loadSettingsConfig();
        if (cancelled) return;
        firebaseApiKey.text = firebaseConfig[firebaseApiKeyPref] ?? '';
        firebaseAppId.text = firebaseConfig[firebaseAppIdPref] ?? '';
        firebaseSenderId.text = firebaseConfig[firebaseSenderIdPref] ?? '';
        firebaseProjectId.text = firebaseConfig[firebaseProjectIdPref] ?? '';
        firebaseStorageBucket.text =
            firebaseConfig[firebaseStorageBucketPref] ?? '';
        loadedFirebaseConfig.value = <String, String>{
          firebaseApiKeyPref: firebaseApiKey.text,
          firebaseAppIdPref: firebaseAppId.text,
          firebaseSenderIdPref: firebaseSenderId.text,
          firebaseProjectIdPref: firebaseProjectId.text,
          firebaseStorageBucketPref: firebaseStorageBucket.text,
        };

        homepage.value = resolvedHomepage;
        homepageController.text =
            resolvedHomepage == defaultHomepageUrl ? '' : resolvedHomepage;
      }

      void handleProfileChange() {
        final current = profileManager.activeProfileId;
        if (current == lastSettingsProfileId.value) return;
        lastSettingsProfileId.value = current;
        unawaited(loadPreferences());
      }

      lastSettingsProfileId.value = profileManager.activeProfileId;
      profileManager.addListener(handleProfileChange);
      unawaited(loadPreferences());
      return () {
        cancelled = true;
        profileManager.removeListener(handleProfileChange);
      };
    }, const []);

    if (homepage.value == null) {
      return const AlertDialog(
        title: Text('Settings'),
        content: CircularProgressIndicator(),
      );
    }

    final dialogMaxHeight = math.min(
      MediaQuery.of(context).size.height * 0.72,
      560.0,
    );

    return AlertDialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.fromLTRB(28, 24, 20, 24),
      title: Text(
        'Settings',
        style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: Scrollbar(
          controller: settingsScrollController,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: settingsScrollController,
            child: Theme(
              data: theme.copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                  hoverColor: Colors.transparent,
                ),
                switchTheme: SwitchThemeData(
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return theme.colorScheme.onPrimary;
                    }
                    return theme.colorScheme.outline;
                  }),
                ),
                listTileTheme: ListTileThemeData(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -1),
                  titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                  ),
                  subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: homepageController,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Homepage',
                      isDense: true,
                      filled: false,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: compactDensity,
                        title: Text(
                          'Profile',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: ListenableBuilder(
                          listenable: profileManager,
                          builder: (context, _) => Text(
                            profileManager.activeProfile?.name ?? 'None',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        trailing: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: IconButton(
                            key: const Key('settings.manage_profiles'),
                            icon: const Icon(Icons.settings, size: 18),
                            onPressed: () => _showProfileManagerDialog(
                              context,
                              ambientToolbarEnabled.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Hide toolbar'),
                      value: hideAppBar.value,
                      onChanged: (value) => hideAppBar.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Hide URL'),
                      value: autoHideAddressBarEnabled.value,
                      onChanged: (value) =>
                          autoHideAddressBarEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Legacy UA'),
                      value: useModernUserAgent.value,
                      onChanged: (value) => useModernUserAgent.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Private'),
                      value: privateBrowsing.value,
                      onChanged: (value) => privateBrowsing.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Block ads'),
                      value: adBlocking.value,
                      onChanged: (value) => adBlocking.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Strict'),
                      value: strictMode.value,
                      onChanged: (value) => strictMode.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Passwords'),
                      value: passwordManagerEnabled.value,
                      onChanged: (value) =>
                          passwordManagerEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  if (passwordManagerEnabled.value)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: ListTile(
                        leading: const Icon(Icons.lock),
                        title: const Text('Manage Passwords'),
                        trailing: const Icon(Icons.chevron_right),
                        hoverColor: Colors.transparent,
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PasswordVaultScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Reorder tabs'),
                      value: reorderableTabs.value,
                      onChanged: (value) => reorderableTabs.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Favicon badge'),
                      value: tabFaviconBadgeEnabled.value,
                      onChanged: (value) =>
                          tabFaviconBadgeEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('AI suggestions'),
                      value: aiSearchSuggestionsEnabled.value,
                      onChanged: (value) =>
                          aiSearchSuggestionsEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Erase suggestions'),
                      value: urlAutocompleteSuggestionRemovalEnabled.value,
                      onChanged: (value) =>
                          urlAutocompleteSuggestionRemovalEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Advanced cache'),
                      value: advancedCacheEnabled.value,
                      onChanged: (value) => advancedCacheEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Ambient'),
                      value: ambientToolbarEnabled.value,
                      onChanged: (value) => ambientToolbarEnabled.value = value,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppThemeMode.values.map((mode) {
                      final isSelected = selectedTheme.value == mode;
                      return Theme(
                        data: theme.copyWith(
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                        ),
                        child: ChoiceChip(
                          label: Text(
                            _themeLabel(mode),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 12),
                          ),
                          selected: isSelected,
                          showCheckmark: false,
                          visualDensity: compactDensity,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) {
                            selectedTheme.value = mode;
                            onThemePreviewChanged?.call(mode);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.12),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'AI Chat',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: aiAvailable
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    aiAvailable
                                        ? Icons.verified_rounded
                                        : Icons.warning_amber_rounded,
                                    size: 12,
                                    color: aiAvailable
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    aiAvailable ? 'Ready' : 'Setup',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: aiAvailable
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: IconButton(
                                key: const Key(
                                    'settings.firebase_config_toggle'),
                                visualDensity: compactDensity,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                icon: Icon(
                                  showFirebaseConfig.value
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                onPressed: () => showFirebaseConfig.value =
                                    !showFirebaseConfig.value,
                              ),
                            ),
                          ],
                        ),
                        if (showFirebaseConfig.value) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: firebaseApiKey,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              labelStyle: TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              filled: false,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: firebaseAppId,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'App ID',
                              labelStyle: TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              filled: false,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: firebaseSenderId,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Sender ID',
                              labelStyle: TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              filled: false,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: firebaseProjectId,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Project ID',
                              labelStyle: TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              filled: false,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: firebaseStorageBucket,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Storage',
                              labelStyle: TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              filled: false,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(
                      effectiveUpdateInfo != null
                          ? 'v${effectiveUpdateInfo.version}'
                          : 'Updates',
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: effectiveUpdateInfo != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Update',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        : RotationTransition(
                            turns: refreshIconController,
                            child: IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed:
                                  isCheckingUpdate.value ? null : checkUpdate,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop(false);
                        onOpenHelp?.call();
                      },
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/icons/menu_bar_icon.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.menu, size: 24),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final homepageText = homepageController.text.trim();
            String homepageToSave;
            if (homepageText.isEmpty) {
              homepageToSave = defaultHomepageUrl;
            } else {
              final processed = UrlUtils.processUrl(homepageText);
              if (!UrlUtils.isValidUrl(processed)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid homepage URL')),
                );
                return;
              }
              homepageToSave = processed;
            }
            final prefs = await SharedPreferences.getInstance();
            String scopedKey(String key) =>
                profileManager.getScopedStorageKey(key);

            final oldApiKey =
                loadedFirebaseConfig.value[firebaseApiKeyPref] ?? '';
            final oldAppId =
                loadedFirebaseConfig.value[firebaseAppIdPref] ?? '';
            final oldSenderId =
                loadedFirebaseConfig.value[firebaseSenderIdPref] ?? '';
            final oldProjectId =
                loadedFirebaseConfig.value[firebaseProjectIdPref] ?? '';
            final oldStorageBucket =
                loadedFirebaseConfig.value[firebaseStorageBucketPref] ?? '';

            final newApiKey = firebaseApiKey.text.trim();
            final newAppId = firebaseAppId.text.trim();
            final newSenderId = firebaseSenderId.text.trim();
            final newProjectId = firebaseProjectId.text.trim();
            final newStorageBucket = firebaseStorageBucket.text.trim();

            final firebaseChanged = oldApiKey != newApiKey ||
                oldAppId != newAppId ||
                oldSenderId != newSenderId ||
                oldProjectId != newProjectId ||
                oldStorageBucket != newStorageBucket;

            await prefs.setString(scopedKey(homepageKey), homepageToSave);
            await prefs.setBool(scopedKey(hideAppBarKey), hideAppBar.value);
            await prefs.setBool(
                scopedKey(useModernUserAgentKey), useModernUserAgent.value);
            await prefs.setBool(
                scopedKey(privateBrowsingKey), privateBrowsing.value);
            await prefs.setBool(scopedKey(adBlockingKey), adBlocking.value);
            await prefs.setBool(scopedKey(strictModeKey), strictMode.value);
            await prefs.setBool(scopedKey(passwordManagerEnabledKey),
                passwordManagerEnabled.value);
            await prefs.setBool(
                scopedKey(reorderableTabsKey), reorderableTabs.value);
            await prefs.setBool(
              scopedKey(tabFaviconBadgeEnabledKey),
              tabFaviconBadgeEnabled.value,
            );
            await prefs.setBool(scopedKey(aiSearchSuggestionsEnabledKey),
                aiSearchSuggestionsEnabled.value);
            await prefs.setBool(
                scopedKey(advancedCacheEnabledKey), advancedCacheEnabled.value);
            await prefs.setBool(scopedKey(ambientToolbarEnabledKey),
                ambientToolbarEnabled.value);
            await prefs.setBool(
              scopedKey(urlAutocompleteSuggestionRemovalEnabledKey),
              urlAutocompleteSuggestionRemovalEnabled.value,
            );
            await prefs.setBool(
              scopedKey(autoHideAddressBarKey),
              autoHideAddressBarEnabled.value,
            );
            await prefs.setString(
                scopedKey(themeModeKey), selectedTheme.value.name);

            try {
              await FirebaseConfigStore.saveSettingsConfig(
                apiKey: newApiKey,
                appId: newAppId,
                senderId: newSenderId,
                projectId: newProjectId,
                storageBucket: newStorageBucket,
              );
            } catch (_) {
            }

            onSettingsChanged?.call();
            if (privateBrowsing.value &&
                originalPrivateBrowsing.value == false) {
              onClearCaches?.call();
            }

            final message = firebaseChanged
                ? 'Settings saved — restart required for Firebase changes'
                : 'Settings saved';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
            Navigator.of(context).pop(true);
          },
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Save'),
        ),
        if (onClearAllData != null)
          TextButton(
            onPressed: () async {
              final theme = Theme.of(context);
              final confirm = await showDialog<bool?>(
                context: context,
                builder: (dialogContext) {
                  bool factoryReset = false;
                  return Theme(
                    data: theme.copyWith(
                      splashFactory: NoSplash.splashFactory,
                      hoverColor: Colors.transparent,
                    ),
                    child: StatefulBuilder(
                      builder: (dialogContext, setState) => AlertDialog(
                        title: Text(
                          'Clear All Data',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontSize: 15),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This will clear all cached data, saved passwords, and settings.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Checkbox(
                                    value: factoryReset,
                                    onChanged: (v) {
                                      setState(() => factoryReset = v ?? false);
                                    },
                                    overlayColor: WidgetStateProperty.all(
                                        Colors.transparent),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Factory reset (erase all profiles)',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const SizedBox.shrink(),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(null),
                            style: ButtonStyle(
                              overlayColor:
                                  WidgetStateProperty.all(Colors.transparent),
                            ),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(factoryReset),
                            style: ButtonStyle(
                              overlayColor:
                                  WidgetStateProperty.all(Colors.transparent),
                            ),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
              if (confirm != null) {
                onClearAllData?.call(confirm);
              }
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            child: Text('Clear'),
          ),
      ],
    );
  }

  void _showProfileManagerDialog(BuildContext dialogContext, bool ambient) {
    showDialog<void>(
      context: dialogContext,
      builder: (context) => _ProfileManagerDialog(
        onProfileChanged: () {},
        ambientEnabled: ambient,
      ),
    );
  }
}

class _ProfileManagerDialog extends StatefulWidget {
  final VoidCallback onProfileChanged;
  final bool ambientEnabled;

  const _ProfileManagerDialog({
    required this.onProfileChanged,
    required this.ambientEnabled,
  });

  @override
  State<_ProfileManagerDialog> createState() => _ProfileManagerDialogState();
}

class _ProfileManagerDialogState extends State<_ProfileManagerDialog> {
  final noHoverOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    return states.contains(WidgetState.hovered) ? Colors.transparent : null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
      backgroundColor: widget.ambientEnabled
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)
          : null,
      title: Text(
        'Manage Profiles',
        style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
      ),
      content: SizedBox(
        width: 300,
        child: Theme(
          data: theme.copyWith(
            splashFactory: NoSplash.splashFactory,
            hoverColor: Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: profileManager,
                builder: (context, _) => ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: profileManager.profiles.map((profile) {
                        final isActive =
                            profile.id == profileManager.activeProfileId;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isActive
                                ? null
                                : () async {
                                    await profileManager
                                        .switchProfile(profile.id);
                                    widget.onProfileChanged();
                                    if (mounted) setState(() {});
                                  },
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              hoverColor: Colors.transparent,
                              selectedColor: profile.color,
                              selected: isActive,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: profile.color,
                                child: Text(
                                  profile.name.isNotEmpty
                                      ? profile.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              title: Text(profile.name),
                              trailing: isActive
                                  ? Icon(Icons.check,
                                      size: 18, color: profile.color)
                                  : profileManager.canDelete(profile.id)
                                      ? IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                          onPressed: () =>
                                              _confirmDelete(profile),
                                        )
                                      : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const Divider(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showCreateProfileDialog,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: const ListTile(
                    dense: true,
                    leading: Icon(Icons.add),
                    title: Text('Create new profile'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: ButtonStyle(overlayColor: noHoverOverlay),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _showCreateProfileDialog() {
    final nameController = TextEditingController();
    int? selectedColorIndex;
    final theme = Theme.of(context);

    final dialogTheme = theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hoverColor: Colors.transparent,
      ),
    );
    showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: dialogTheme,
        child: StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            alignment: Alignment.centerRight,
            insetPadding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
            title: Text(
              'Create Profile',
              style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  onTap: () {
                    nameController.selection = TextSelection.collapsed(
                      offset: nameController.text.length,
                    );
                  },
                  decoration: InputDecoration(
                    labelText: 'Profile name',
                    hintText: 'Enter profile name',
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
                const SizedBox(height: 16),
                Text(
                  'Color',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(UserProfile.availableColors.length,
                      (index) {
                    final color = UserProfile.availableColors[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setStateDialog(() {
                            selectedColorIndex = index;
                          });
                        },
                        hoverColor: Colors.transparent,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(color),
                          child: selectedColorIndex == index
                              ? const Icon(Icons.check,
                                  size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(
                style: ButtonStyle(overlayColor: noHoverOverlay),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: ButtonStyle(overlayColor: noHoverOverlay),
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty) {
                    final colorValue = selectedColorIndex != null
                        ? UserProfile.availableColors[selectedColorIndex!]
                        : null;
                    await profileManager.createProfile(
                      nameController.text.trim(),
                      colorValue: colorValue,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      setState(() {});
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(UserProfile profile) {
    final dialogTheme = Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
    );
    showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: dialogTheme,
        child: AlertDialog(
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
          title: Text(
            'Erase ${profile.name}?',
            style:
                Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
          ),
          content: Text(
            'All browsing data for this profile will be lost.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          actions: [
            TextButton(
              style: ButtonStyle(overlayColor: noHoverOverlay),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: ButtonStyle(
                overlayColor: noHoverOverlay,
              ),
              onPressed: () async {
                await profileManager.deleteProfile(profile.id);
                widget.onProfileChanged();
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: Text(
                'Erase',
                style: TextStyle(color: Colors.red.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

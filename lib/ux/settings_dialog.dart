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

import 'package:package_info_plus/package_info_plus.dart';

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
    final lastNonAdjustTheme = useRef<AppThemeMode>(
      currentTheme == AppThemeMode.adjust ? AppThemeMode.system : (currentTheme ?? AppThemeMode.system)
    );
    final currentAppVersion = useState<String>('1.0.0');
    final homepageController = useTextEditingController();
    final settingsScrollController = useScrollController();

    final homepageFocusNode = useFocusNode();

    final firebaseApiKey = useTextEditingController();
    final firebaseAppId = useTextEditingController();
    final firebaseSenderId = useTextEditingController();
    final firebaseProjectId = useTextEditingController();
    final firebaseStorageBucket = useTextEditingController();

    final firebaseApiKeyFocusNode = useFocusNode();
    final firebaseAppIdFocusNode = useFocusNode();
    final firebaseSenderIdFocusNode = useFocusNode();
    final firebaseProjectIdFocusNode = useFocusNode();
    final firebaseStorageBucketFocusNode = useFocusNode();

    final showFirebaseConfig = useState(false);
    final loadedFirebaseConfig =
        useRef<Map<String, String>>(<String, String>{});
    final lastSettingsProfileId = useRef<String?>(null);

    final updateService = useMemoized(() => UpdateService());
    final isCheckingUpdate = useState(false);
    final localUpdateInfo = useState<UpdateInfo?>(null);
    final effectiveUpdateInfo = localUpdateInfo.value;
    final downloadProgress = useState<double?>(null);

    Future<void> saveSetting(String key, dynamic value) async {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = profileManager.getScopedStorageKey(key);
      if (value is bool) {
        await prefs.setBool(scopedKey, value);
      } else if (value is String) {
        await prefs.setString(scopedKey, value);
      }
      onSettingsChanged?.call();
      if (key == privateBrowsingKey &&
          value == true &&
          originalPrivateBrowsing.value == false) {
        onClearCaches?.call();
        originalPrivateBrowsing.value = true;
      }
    }

    Future<void> saveFirebaseConfig() async {
      final newApiKey = firebaseApiKey.text.trim();
      final newAppId = firebaseAppId.text.trim();
      final newSenderId = firebaseSenderId.text.trim();
      final newProjectId = firebaseProjectId.text.trim();
      final newStorageBucket = firebaseStorageBucket.text.trim();

      final oldApiKey = loadedFirebaseConfig.value[firebaseApiKeyPref] ?? '';
      final oldAppId = loadedFirebaseConfig.value[firebaseAppIdPref] ?? '';
      final oldSenderId = loadedFirebaseConfig.value[firebaseSenderIdPref] ?? '';
      final oldProjectId = loadedFirebaseConfig.value[firebaseProjectIdPref] ?? '';
      final oldStorageBucket =
          loadedFirebaseConfig.value[firebaseStorageBucketPref] ?? '';

      final firebaseChanged = oldApiKey != newApiKey ||
          oldAppId != newAppId ||
          oldSenderId != newSenderId ||
          oldProjectId != newProjectId ||
          oldStorageBucket != newStorageBucket;

      if (!firebaseChanged) return;

      try {
        await FirebaseConfigStore.saveSettingsConfig(
          apiKey: newApiKey,
          appId: newAppId,
          senderId: newSenderId,
          projectId: newProjectId,
          storageBucket: newStorageBucket,
        );
        loadedFirebaseConfig.value = <String, String>{
          firebaseApiKeyPref: newApiKey,
          firebaseAppIdPref: newAppId,
          firebaseSenderIdPref: newSenderId,
          firebaseProjectIdPref: newProjectId,
          firebaseStorageBucketPref: newStorageBucket,
        };
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Firebase config saved — restart required for changes')),
          );
        }
      } catch (e) {
        debugPrint('Failed to save Firebase config: $e');
      }
    }

    useEffect(() {
      void listener() {
        if (!firebaseApiKeyFocusNode.hasFocus &&
            !firebaseAppIdFocusNode.hasFocus &&
            !firebaseSenderIdFocusNode.hasFocus &&
            !firebaseProjectIdFocusNode.hasFocus &&
            !firebaseStorageBucketFocusNode.hasFocus) {
          saveFirebaseConfig();
        }
      }
      firebaseApiKeyFocusNode.addListener(listener);
      firebaseAppIdFocusNode.addListener(listener);
      firebaseSenderIdFocusNode.addListener(listener);
      firebaseProjectIdFocusNode.addListener(listener);
      firebaseStorageBucketFocusNode.addListener(listener);

      return () {
        firebaseApiKeyFocusNode.removeListener(listener);
        firebaseAppIdFocusNode.removeListener(listener);
        firebaseSenderIdFocusNode.removeListener(listener);
        firebaseProjectIdFocusNode.removeListener(listener);
        firebaseStorageBucketFocusNode.removeListener(listener);
      };
    }, [
      firebaseApiKeyFocusNode,
      firebaseAppIdFocusNode,
      firebaseSenderIdFocusNode,
      firebaseProjectIdFocusNode,
      firebaseStorageBucketFocusNode,
    ]);

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
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download complete. Installing...')),
            );
          }

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

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Update installed. Restarting...'),
                    duration: Duration(seconds: 5),
                  ),
                );
              }

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
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Update installer launched. Follow the prompts to complete installation.'),
                    duration: Duration(seconds: 10),
                  ),
                );
              }
            } catch (e) {
              debugPrint('Failed to launch installer: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Update downloaded to: ${file.path}. Run the installer manually.')),
                );
              }
            }
          } else if (Platform.isLinux) {
            try {
              await Process.run('xdg-open', [file.path]);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Update package opened. Use your package manager to install it.'),
                    duration: Duration(seconds: 10),
                  ),
                );
              }
            } catch (e) {
              debugPrint('Failed to open package: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Update downloaded to: ${file.path}. Install manually with your package manager.')),
                );
              }
            }
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Update downloaded to: ${file.path}. Please install manually.')),
              );
            }
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to download update')),
            );
          }
        }
      }
    }

    Future<void> checkUpdate() async {
      refreshIconController.forward(from: 0.0);
      isCheckingUpdate.value = true;
      try {
        final info = await updateService.checkForUpdates();
        localUpdateInfo.value = info;
        if (info == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Browser is up to date')),
          );
        }
      } catch (e) {
        debugPrint('Update check failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Update check failed. Please try again later.')),
          );
        }
      } finally {
        isCheckingUpdate.value = false;
      }
    }

    useEffect(() {
      var cancelled = false;
      Future<void> loadPreferences() async {
        final prefs = await SharedPreferences.getInstance();
        if (cancelled) return;
        try {
          if (Platform.environment.containsKey('FLUTTER_TEST')) {
            currentAppVersion.value = '1.0.0';
          } else {
            final packageInfo = await PackageInfo.fromPlatform();
            currentAppVersion.value = packageInfo.version;
          }
        } catch (_) {
          currentAppVersion.value = '1.0.0';
        }
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

    useEffect(() {
      void listener() async {
        if (!homepageFocusNode.hasFocus) {
          final text = homepageController.text.trim();
          final resolved =
              text.isEmpty ? defaultHomepageUrl : UrlUtils.processUrl(text);
          if (UrlUtils.isValidUrl(resolved)) {
            homepage.value = resolved;
            await saveSetting(homepageKey, resolved);
          } else {
            homepageController.text = homepage.value == defaultHomepageUrl
                ? ''
                : homepage.value ?? '';
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid homepage URL')),
              );
            }
          }
        }
      }
      homepageFocusNode.addListener(listener);
      return () => homepageFocusNode.removeListener(listener);
    }, [homepageFocusNode, homepage]);

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

    Widget buildSectionHeading(String title) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

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
                  buildSectionHeading('Profile'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                            icon: Icon(
                              Icons.settings,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.55),
                            ),
                            onPressed: () => _showProfileManagerDialog(
                              context,
                              ambientToolbarEnabled.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  buildSectionHeading('Homepage'),
                  TextField(
                    controller: homepageController,
                    focusNode: homepageFocusNode,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    onSubmitted: (value) async {
                      final text = value.trim();
                      final resolved = text.isEmpty
                          ? defaultHomepageUrl
                          : UrlUtils.processUrl(text);
                      if (UrlUtils.isValidUrl(resolved)) {
                        homepage.value = resolved;
                        await saveSetting(homepageKey, resolved);
                        homepageFocusNode.unfocus();
                      } else {
                        homepageController.text = homepage.value ==
                                defaultHomepageUrl
                            ? ''
                            : homepage.value ?? '';
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid homepage URL')),
                          );
                        }
                      }
                    },
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
                  buildSectionHeading('Appearance'),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Theme',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: RadioListTile<AppThemeMode>(
                      title: const Text('System'),
                      value: AppThemeMode.system,
                      groupValue: selectedTheme.value == AppThemeMode.adjust ? lastNonAdjustTheme.value : selectedTheme.value,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: compactDensity,
                      onChanged: (value) {
                        if (value != null) {
                          lastNonAdjustTheme.value = value;
                          selectedTheme.value = value;
                          onThemePreviewChanged?.call(value);
                          saveSetting(themeModeKey, value.name);
                        }
                      },
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: RadioListTile<AppThemeMode>(
                      title: const Text('Light'),
                      value: AppThemeMode.light,
                      groupValue: selectedTheme.value == AppThemeMode.adjust ? lastNonAdjustTheme.value : selectedTheme.value,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: compactDensity,
                      onChanged: (value) {
                        if (value != null) {
                          lastNonAdjustTheme.value = value;
                          selectedTheme.value = value;
                          onThemePreviewChanged?.call(value);
                          saveSetting(themeModeKey, value.name);
                        }
                      },
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: RadioListTile<AppThemeMode>(
                      title: const Text('Dark'),
                      value: AppThemeMode.dark,
                      groupValue: selectedTheme.value == AppThemeMode.adjust ? lastNonAdjustTheme.value : selectedTheme.value,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: compactDensity,
                      onChanged: (value) {
                        if (value != null) {
                          lastNonAdjustTheme.value = value;
                          selectedTheme.value = value;
                          onThemePreviewChanged?.call(value);
                          saveSetting(themeModeKey, value.name);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CheckboxListTile(
                      title: const Text('Adjust page colors'),
                      value: selectedTheme.value == AppThemeMode.adjust,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: compactDensity,
                      onChanged: (value) {
                        final newMode = (value == true) ? AppThemeMode.adjust : lastNonAdjustTheme.value;
                        selectedTheme.value = newMode;
                        onThemePreviewChanged?.call(newMode);
                        saveSetting(themeModeKey, newMode.name);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Hide toolbar'),
                      value: hideAppBar.value,
                      onChanged: (value) {
                        hideAppBar.value = value;
                        saveSetting(hideAppBarKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Hide URL'),
                      value: autoHideAddressBarEnabled.value,
                      onChanged: (value) {
                        autoHideAddressBarEnabled.value = value;
                        saveSetting(autoHideAddressBarKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Tint toolbar with website color'),
                      value: ambientToolbarEnabled.value,
                      onChanged: (value) {
                        ambientToolbarEnabled.value = value;
                        saveSetting(ambientToolbarEnabledKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  buildSectionHeading('Privacy'),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Private'),
                      value: privateBrowsing.value,
                      onChanged: (value) {
                        privateBrowsing.value = value;
                        saveSetting(privateBrowsingKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Block ads'),
                      value: adBlocking.value,
                      onChanged: (value) {
                        adBlocking.value = value;
                        saveSetting(adBlockingKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Strict'),
                      value: strictMode.value,
                      onChanged: (value) {
                        strictMode.value = value;
                        saveSetting(strictModeKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Passwords'),
                      value: passwordManagerEnabled.value,
                      onChanged: (value) {
                        passwordManagerEnabled.value = value;
                        saveSetting(passwordManagerEnabledKey, value);
                      },
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
                      title: const Text('Legacy UA'),
                      value: useModernUserAgent.value,
                      onChanged: (value) {
                        useModernUserAgent.value = value;
                        saveSetting(useModernUserAgentKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Advanced cache'),
                      value: advancedCacheEnabled.value,
                      onChanged: (value) {
                        advancedCacheEnabled.value = value;
                        saveSetting(advancedCacheEnabledKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  buildSectionHeading('Tabs'),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Reorderable tabs'),
                      value: reorderableTabs.value,
                      onChanged: (value) {
                        reorderableTabs.value = value;
                        saveSetting(reorderableTabsKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Favicon badge'),
                      value: tabFaviconBadgeEnabled.value,
                      onChanged: (value) {
                        tabFaviconBadgeEnabled.value = value;
                        saveSetting(tabFaviconBadgeEnabledKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  buildSectionHeading('AI'),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('AI suggestions'),
                      value: aiSearchSuggestionsEnabled.value,
                      onChanged: (value) {
                        aiSearchSuggestionsEnabled.value = value;
                        saveSetting(aiSearchSuggestionsEnabledKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SwitchListTile(
                      title: const Text('Erase suggestions'),
                      value: urlAutocompleteSuggestionRemovalEnabled.value,
                      onChanged: (value) {
                        urlAutocompleteSuggestionRemovalEnabled.value = value;
                        saveSetting(urlAutocompleteSuggestionRemovalEnabledKey, value);
                      },
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        InkWell(
                          key: const Key('settings.firebase_config_toggle'),
                          onTap: () => showFirebaseConfig.value = !showFirebaseConfig.value,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  'AI Chat',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontSize: 12),
                                ),
                                const Spacer(),
                                Text(
                                  'Firebase Gemini',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  showFirebaseConfig.value
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showFirebaseConfig.value) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: firebaseApiKey,
                            focusNode: firebaseApiKeyFocusNode,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              labelStyle: const TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
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
                            focusNode: firebaseAppIdFocusNode,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'App ID',
                              labelStyle: const TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
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
                            focusNode: firebaseSenderIdFocusNode,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Sender ID',
                              labelStyle: const TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
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
                            focusNode: firebaseProjectIdFocusNode,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Project ID',
                              labelStyle: const TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
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
                            focusNode: firebaseStorageBucketFocusNode,
                            obscureText: true,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              labelText: 'Storage Bucket',
                              labelStyle: const TextStyle(fontSize: 8),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
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
                  buildSectionHeading('Updates'),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      effectiveUpdateInfo != null
                          ? 'New Version Available: v${effectiveUpdateInfo.version}'
                          : 'Version ${currentAppVersion.value}',
                      style: effectiveUpdateInfo != null
                          ? theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            )
                          : theme.textTheme.bodyMedium,
                    ),
                    subtitle: effectiveUpdateInfo != null
                        ? (downloadProgress.value != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: downloadProgress.value,
                                    minHeight: 3,
                                  ),
                                ),
                              )
                            : const Text('An update is ready to install.'))
                        : Text(isCheckingUpdate.value ? 'Checking for updates...' : 'Up to date'),
                    trailing: effectiveUpdateInfo != null
                        ? (downloadProgress.value != null
                            ? Text(
                                '${(downloadProgress.value! * 100).toInt()}%',
                                style: theme.textTheme.bodySmall,
                              )
                            : OutlinedButton(
                                onPressed: () => handleUpdate(effectiveUpdateInfo),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Install'),
                              ))
                        : (isCheckingUpdate.value
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton(
                                onPressed: checkUpdate,
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Check for updates'),
                              )),
                  ),
                  if (onClearAllData != null) ...[
                    buildSectionHeading('Danger Zone'),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        title: Text(
                          'Reset settings & data',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: const Text('Erase settings, passwords, caches, and profiles'),
                        onTap: () async {
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
                                      'Reset Settings & Data',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(fontSize: 15),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'This will clear all cached data, saved passwords, settings, and user profiles.',
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
                                        child: const Text('Reset'),
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
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    if (mounted) {
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
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (mounted) {
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

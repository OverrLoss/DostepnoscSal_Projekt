import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'room_sync_service.dart';
import 'app_update_downloader.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final int apkSize;
  final String releaseNotes;
  final bool isUpdateAvailable;
  final String currentVersionName;
  final int currentVersionCode;

  AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.apkSize,
    required this.releaseNotes,
    required this.isUpdateAvailable,
    required this.currentVersionName,
    required this.currentVersionCode,
  });

  String get formattedSize {
    if (apkSize <= 0) return '';
    final mb = apkSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._init();
  AppUpdateService._init();

  static const MethodChannel _channel = MethodChannel('com.example.roomavailability/app_updater');

  bool _isChecking = false;
  bool _isDownloading = false;
  DateTime? _lastCheckTime;

  DateTime? get lastCheckTime => _lastCheckTime;

  Future<Map<String, dynamic>> getLocalAppVersion() async {
    if (kIsWeb) {
      return {'versionCode': 11, 'versionName': '1.3.6'};
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
      if (res != null) {
        return {
          'versionCode': (res['versionCode'] as num?)?.toInt() ?? 1,
          'versionName': res['versionName']?.toString() ?? '1.0.0',
        };
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error getting local version: $e');
    }
    return {'versionCode': 1, 'versionName': '1.0.0'};
  }

  Future<AppUpdateInfo?> checkUpdate() async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final local = await getLocalAppVersion();
      final localCode = local['versionCode'] as int;
      final localName = local['versionName'] as String;

      final serverBase = RoomSyncService.instance.serverUrl.isNotEmpty
          ? RoomSyncService.instance.serverUrl
          : 'https://sale.pwojtaszek.codes';

      // Add cache-buster to prevent any caching layer from serving stale response
      final ts = DateTime.now().millisecondsSinceEpoch;
      final uri = Uri.parse('$serverBase/api/v1/app-version?_t=$ts');
      final res = await http.get(uri, headers: {
        'Cache-Control': 'no-cache, no-store',
        'Pragma': 'no-cache',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final remoteCode = (data['versionCode'] as num?)?.toInt() ?? 0;
        final remoteName = data['versionName']?.toString() ?? '1.0.0';

        // Always ensure APK URL has cache-buster ?v=N query param
        String apkUrl = data['apkUrl']?.toString() ?? '$serverBase/DostepnoscSal.apk';
        if (!apkUrl.contains('?v=') && !apkUrl.contains('&v=')) {
          apkUrl = '$apkUrl?v=$remoteCode';
        }

        final apkSize = (data['apkSize'] as num?)?.toInt() ?? 0;
        final releaseNotes = data['releaseNotes']?.toString() ?? 'Nowa wersja jest dostępna.';

        final bool isNewer = remoteCode > localCode;
        _lastCheckTime = DateTime.now();

        debugPrint('[AppUpdateService] local=$localCode remote=$remoteCode isNewer=$isNewer apkUrl=$apkUrl');

        return AppUpdateInfo(
          versionCode: remoteCode,
          versionName: remoteName,
          apkUrl: apkUrl,
          apkSize: apkSize,
          releaseNotes: releaseNotes,
          isUpdateAvailable: isNewer,
          currentVersionName: localName,
          currentVersionCode: localCode,
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking update: $e');
    } finally {
      _isChecking = false;
    }
    return null;
  }

  Future<void> checkForUpdate(
    BuildContext context, {
    bool autoPrompt = false,
    bool showUpToDate = false,
  }) async {
    // Aktualizacje przez APK istnieją tylko na Androidzie.
    // Na iOS / macOS / Windows aplikację instaluje się na nowo (Xcode, TestFlight).
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      if (showUpToDate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Na tym urządzeniu aktualizację instaluje się przez Xcode lub TestFlight.'),
          ),
        );
      }
      return;
    }
    if (kIsWeb) {
      if (showUpToDate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wersja Web jest zawsze na bieżąco z serwerem.'),
            backgroundColor: Color(0xFF141414),
          ),
        );
      }
      return;
    }

    final updateInfo = await checkUpdate();
    if (!context.mounted) return;

    if (updateInfo != null && updateInfo.isUpdateAvailable) {
      _showUpdateAvailableDialog(context, updateInfo);
    } else if (showUpToDate && context.mounted) {
      final local = await getLocalAppVersion();
      if (!context.mounted) return;
      final name = local['versionName'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Twoja aplikacja jest aktualna (v$name).'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showUpdateAvailableDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded, color: Colors.greenAccent, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nowa aktualizacja',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dostępna jest nowa wersja ${info.versionName} (${info.formattedSize})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Obecna wersja: v${info.currentVersionName}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'Co nowego:',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Później', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _startDownloadAndInstall(context, info);
              },
              icon: const Icon(Icons.download_rounded, color: Colors.black, size: 18),
              label: const Text('Aktualizuj teraz', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _startDownloadAndInstall(BuildContext context, AppUpdateInfo info) {
    if (_isDownloading) return;
    _isDownloading = true;

    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Przygotowywanie...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.downloading_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Pobieranie aktualizacji', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) {
                final percent = (progress * 100).toInt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 12,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ValueListenableBuilder<String>(
                          valueListenable: statusNotifier,
                          builder: (context, status, _) {
                            return Text(
                              status,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            );
                          },
                        ),
                        Text(
                          '$percent%',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    _executeDownloadAndInstall(info, progressNotifier, statusNotifier, context);
  }

  Future<void> _executeDownloadAndInstall(
    AppUpdateInfo info,
    ValueNotifier<double> progressNotifier,
    ValueNotifier<String> statusNotifier,
    BuildContext context,
  ) async {
    try {
      final cacheDir = await _channel.invokeMethod<String>('getCacheDir');
      if (cacheDir == null || cacheDir.isEmpty) {
        throw Exception('Nie można uzyskać dostępu do pamięci podręcznej');
      }

      final targetPath = '$cacheDir/DostepnoscSal_update.apk';

      // Build a download URL that always bypasses Cloudflare / CDN cache
      final ts = DateTime.now().millisecondsSinceEpoch;
      String downloadUrl = info.apkUrl;
      // Replace or add cache-busting params
      if (downloadUrl.contains('?v=')) {
        downloadUrl = downloadUrl.replaceFirst(RegExp(r'\?v=\d+'), '?v=${info.versionCode}&_t=$ts');
      } else if (downloadUrl.contains('?')) {
        downloadUrl = '$downloadUrl&_t=$ts';
      } else {
        downloadUrl = '$downloadUrl?v=${info.versionCode}&_t=$ts';
      }

      debugPrint('[AppUpdateService] Downloading from: $downloadUrl');

      await downloadApkFile(
        url: downloadUrl,
        targetPath: targetPath,
        expectedSize: info.apkSize,
        onProgress: (p, status) {
          progressNotifier.value = p;
          statusNotifier.value = status;
        },
      );

      statusNotifier.value = 'Uruchamianie instalatora...';
      await Future.delayed(const Duration(milliseconds: 600));

      // Close the downloading dialog
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Check permission to install unknown apps
      final canInstall = await _channel.invokeMethod<bool>('canInstallPackages') ?? true;
      if (!canInstall) {
        // Show info and open settings so user can grant permission
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Zezwól na instalację z nieznanych źródeł w Ustawieniach, a następnie wróć do aplikacji.'),
              backgroundColor: Color(0xFF1F1F1F),
              duration: Duration(seconds: 5),
            ),
          );
        }
        await _channel.invokeMethod('openInstallPermissionSettings');
        // Wait for user to come back and retry
        await Future.delayed(const Duration(seconds: 4));
      }

      // Trigger native package install intent
      final success = await _channel.invokeMethod<bool>('installApk', {'filePath': targetPath});
      if (success != true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Błąd podczas uruchamiania instalatora APK'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Download failed: $e');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Błąd pobierania aktualizacji: $e'),
            backgroundColor: Colors.redAccent,
            action: SnackBarAction(
              label: 'Ponów',
              textColor: Colors.white,
              onPressed: () {
                checkForUpdate(context, autoPrompt: true);
              },
            ),
          ),
        );
      }
    } finally {
      _isDownloading = false;
    }
  }
}

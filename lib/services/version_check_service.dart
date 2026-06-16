// lib/services/version_check_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckResult {
  final bool hasUpdate;
  final String latestVersion;
  final String? downloadUrl;
  final String? localApkPath;

  const UpdateCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    this.downloadUrl,
    this.localApkPath,
  });
}

class VersionCheckService {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/Calbrs/SynCal/releases/latest';

  static const String _fallbackReleasesUrl =
      'https://github.com/Calbrs/SynCal/releases';

  static Future<UpdateCheckResult?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = Version.parse(_cleanVersion(packageInfo.version));

      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Cache-Control': 'no-cache',
          'User-Agent': 'SyncCal-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersionStr = _cleanVersion((data['tag_name'] ?? '').toString());
      final latestVersion = Version.parse(latestVersionStr);

      if (latestVersion > currentVersion) {
        String? apkDownloadUrl;
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null) {
          for (var asset in assets) {
            if (asset['name'].toString().toLowerCase().endsWith('.apk')) {
              apkDownloadUrl = asset['browser_download_url'];
              break;
            }
          }
        }

        String? localFilePath;
        if (apkDownloadUrl != null) {
          try {
            final dir = await getExternalStorageDirectory();
            if (dir != null) {
              final file = File('${dir.path}/update_v$latestVersionStr.apk');
              if (file.existsSync() && file.lengthSync() > 100000) {
                localFilePath = file.path;
              }
            }
          } catch (_) {}
        }

        return UpdateCheckResult(
          hasUpdate: true,
          latestVersion: latestVersionStr,
          downloadUrl: apkDownloadUrl,
          localApkPath: localFilePath,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> downloadApk({
    required String version,
    required Function(double progress) onProgress,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = Version.parse(_cleanVersion(packageInfo.version));
      final latestVersion = Version.parse(version);

      if (latestVersion <= currentVersion) return null;

      final response = await http.get(Uri.parse(_latestReleaseUrl));
      if (response.statusCode != 200) throw Exception('Failed to fetch release');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      String? apkUrl;
      final assets = data['assets'] as List<dynamic>?;
      if (assets != null) {
        for (var asset in assets) {
          if (asset['name'].toString().toLowerCase().endsWith('.apk')) {
            apkUrl = asset['browser_download_url'];
            break;
          }
        }
      }
      if (apkUrl == null) throw Exception('APK not found in release');

      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception('Storage not available');

      final file = File('${dir.path}/update_v$version.apk');

      if (file.existsSync() && file.lengthSync() > 500000) {
        onProgress(1.0);
        return file.path;
      }

      final request = http.Request('GET', Uri.parse(apkUrl));
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed with status ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int received = 0;

      final fileSink = file.openWrite();
      await streamedResponse.stream.map((chunk) {
        received += chunk.length;
        if (contentLength > 0) {
          onProgress(received / contentLength);
        }
        return chunk;
      }).pipe(fileSink);

      await fileSink.close();

      if (file.existsSync() && file.lengthSync() > 500000) {
        onProgress(1.0);
        return file.path;
      } else {
        throw Exception('Downloaded file is invalid');
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> openUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _cleanVersion(String v) {
    return v
        .trim()
        .replaceAll('v', '')
        .replaceAll('V', '')
        .split('+')[0]
        .split('-')[0]
        .trim();
  }

  static Future<void> checkAndPromptUpdate(
    BuildContext context, {
    bool silent = true,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionStr = _cleanVersion(packageInfo.version);
      final currentVersion = Version.parse(currentVersionStr);

      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Cache-Control': 'no-cache',
          'User-Agent': 'SyncCal-App',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) throw Exception('GitHub API error');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersionStr = _cleanVersion((data['tag_name'] ?? '').toString());
      final latestVersion = Version.parse(latestVersionStr);

      if (latestVersion > currentVersion) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion.toString(), data['html_url'] ?? _fallbackReleasesUrl, data['body'] ?? '');
        }
      } else if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are using the latest version'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String url,
    String changelog,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 12),
            Text('Update $version'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('A new version is available!', style: TextStyle(fontSize: 16)),
              if (changelog.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                  child: Text(changelog.length > 350 ? '${changelog.substring(0, 350)}...' : changelog, style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Would you like to update now?', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openUpdateUrl(url);
            },
            child: const Text('View Release'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await openUpdateUrl(url);
            },
            child: const Text('Install Now'),
          ),
        ],
      ),
    );
  }
}
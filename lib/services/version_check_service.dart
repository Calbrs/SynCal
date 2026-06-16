import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionCheckService {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/Calbrs/SynCal/releases/latest';

  static Future<void> checkAndPromptUpdate(
    BuildContext context, {
    bool silent = true,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();

      final response = await http
          .get(Uri.parse(_latestReleaseUrl))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) {
        // No releases yet on GitHub
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No releases found on GitHub yet'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (response.statusCode != 200) {
        throw Exception('GitHub returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final latestTag = (data['tag_name'] as String?)
              ?.replaceFirst('v', '')
              .trim() ??
          '';

      final releaseUrl = (data['html_url'] as String?) ??
          'https://github.com/Calbrs/SynCal/releases';

      if (latestTag.isEmpty) {
        throw Exception('Invalid release data from GitHub');
      }

      if (_isNewerVersion(latestTag, currentVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, latestTag, releaseUrl);
        }
      } else {
        if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are using the latest version'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Version check failed: $e');

      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to check for updates'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    final latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .toList();

    final currentParts = current
        .split('.')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .toList();

    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    while (latestParts.length < maxLength) {
      latestParts.add(0);
    }
    while (currentParts.length < maxLength) {
      currentParts.add(0);
    }

    for (int i = 0; i < maxLength; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String url,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
          'Version $version is available.\n\nPlease update SyncCal to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(url);
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
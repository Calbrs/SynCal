// lib/screens/settings_screen.dart
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;

import '/core/api_client.dart';
import '../../services/version_check_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '1.0.0';
  String _syncCalId = 'Not linked';
  bool _checkingUpdate = false;
  bool _downloading = false;
  double _downloadProgress = 0.0;
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSyncCalId();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (_) {}
  }

  void _loadSyncCalId() {
    final linkedUser = ApiClient.instance.linkedUser;
    setState(() {
      final id = linkedUser?.syncalId ?? linkedUser?.id;
      _syncCalId = (id is String ? id : id?.toString()) ?? 'Not linked';
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    try {
      final result = await VersionCheckService.checkForUpdate();
      if (!mounted) return;

      if (result != null && result.hasUpdate) {
        setState(() => _latestVersion = result.latestVersion);
        _startDownload();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are up to date'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _startDownload() async {
    if (_latestVersion == null) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final path = await VersionCheckService.downloadApk(
        version: _latestVersion!,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update downloaded. Go to home screen to install.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showReportProblemModal(BuildContext context) {
    final controller = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E22),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        const Text('Report a Problem', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('Describe the issue you\'re experiencing.', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: controller,
                          maxLines: 5,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Describe the issue...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.all(16),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        final desc = controller.text.trim();
                                        if (desc.isEmpty) return;

                                        setModalState(() => isSubmitting = true);

                                        try {
                                          // Fixed API call - using your existing ApiClient pattern
                                          final response = await http.post(
                                            Uri.parse('https://your-api-domain.com/api/connect'), // ← Change this to your real domain
                                            headers: {'Content-Type': 'application/json'},
                                            body: jsonEncode({
                                              'action': 'report_problem',
                                              'syncal_id': _syncCalId,
                                              'description': desc,
                                            }),
                                          );

                                          if (response.statusCode == 200) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Problem reported successfully. Thank you!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          } else {
                                            throw Exception('Server error: ${response.statusCode}');
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Failed to report problem: $e'),
                                                backgroundColor: Colors.redAccent,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) Navigator.pop(ctx);
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                                    : const Text('Submit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1C1C1E),
        extendBody: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            shape: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
          ),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              children: [
                _sectionLabel('Account'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5)),
                  clipBehavior: Clip.antiAlias,
                  child: _settingsTile(
                    icon: Icons.fingerprint_rounded,
                    title: 'SyncCal ID',
                    subtitle: _syncCalId,
                    trailing: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _syncCalId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copied to clipboard'), backgroundColor: Color(0xFF3A3A3E)));
                      },
                      child: Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                _sectionLabel('Updates'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5)),
                  clipBehavior: Clip.antiAlias,
                  child: _settingsTile(
                    icon: Icons.system_update_rounded,
                    title: 'Check for Updates',
                    subtitle: _latestVersion != null ? 'v$_latestVersion available' : null,
                    onTap: _checkingUpdate || _downloading ? null : _checkForUpdates,
                    trailing: _checkingUpdate || _downloading
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(value: _downloading ? _downloadProgress : null, strokeWidth: 2))
                        : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                  ),
                ),

                const SizedBox(height: 24),

                _sectionLabel('Support'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5)),
                  clipBehavior: Clip.antiAlias,
                  child: _settingsTile(
                    icon: Icons.bug_report_rounded,
                    title: 'Report a Problem',
                    onTap: () => _showReportProblemModal(context),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.3), size: 14),
                  ),
                ),
              ],
            ),

            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Text('SyncCal v$_appVersion', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13, letterSpacing: 0.3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(label.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.0)),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
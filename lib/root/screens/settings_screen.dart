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

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadSyncCalId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VersionCheckService.checkAndPromptUpdate(context, silent: true);
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
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

  void _showReportProblemModal(BuildContext context) {
    final problemController = TextEditingController();
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
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                      ),
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
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Text(
                          'Report a Problem',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: problemController,
                          maxLines: 5,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Describe the problem you encountered...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            contentPadding: const EdgeInsets.all(16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            ),
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
                                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                                child: const Text('Cancel',
                                    style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
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
                                        final description = problemController.text.trim();
                                        if (description.isEmpty) return;

                                        setModalState(() => isSubmitting = true);

                                        try {
                                          final response = await http.post(
                                            Uri.parse('https://your-api-domain.com/api/report_problem.php'),
                                            headers: {'Content-Type': 'application/json'},
                                            body: jsonEncode({
                                              'synccal_id': _syncCalId == 'Not linked' ? '' : _syncCalId,
                                              'description': description,
                                            }),
                                          );

                                          if (response.statusCode == 200) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: const Text('Problem reported successfully.'),
                                                  backgroundColor: Colors.green,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          } else {
                                            throw Exception();
                                          }
                                        } catch (_) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: const Text('Failed to submit report. Please try again.'),
                                                backgroundColor: Colors.redAccent,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                                      )
                                    : const Text('Submit',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E), // iOS Background Dark
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. SyncCal ID (Independent Block)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _settingsTile(
                  title: 'SyncCal ID',
                  subtitle: _syncCalId,
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                    onPressed: () {
                      if (_syncCalId == 'Not linked') return;
                      Clipboard.setData(ClipboardData(text: _syncCalId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('SyncCal ID copied to clipboard'),
                          backgroundColor: const Color(0xFF3A3A3C),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12), // Nafasi kati ya makontena

              // 2. Report a Problem (Independent Block)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _settingsTile(
                  title: 'Report a Problem',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
                  onTap: () => _showReportProblemModal(context),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Check for Updates (Independent Block)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _settingsTile(
                  title: 'Check for Updates',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 16),
                  onTap: () => VersionCheckService.checkAndPromptUpdate(context, silent: false),
                ),
              ),
            ],
          ),
          
          // Version info ya chini kabisa
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Text(
              'Version $_appVersion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
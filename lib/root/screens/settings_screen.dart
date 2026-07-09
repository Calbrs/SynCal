// lib/screens/settings_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';

import '/core/api_client.dart';
import '../../services/version_check_service.dart';
import '../app_routes.dart';

/// ── Shared palette, identical to HomeScreen's _Palette so every screen
/// reads as one continuous surface.
class _Palette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color surface = Color(0xFF18181B);
  static const Color hairline = Color(0xFF3F3F46);
  static const Color muted = Color(0xFF71717A);
  static const Color mutedLight = Color(0xFFA1A1AA);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '1.0.0';
  String _synCalId = 'Not linked';
  String _username = '';
  bool _checkingUpdate = false;
  String? _latestVersion;
  bool _unkillableMode = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadUserInfo();
    _loadUnkillableMode();
  }

  Future<void> _loadUnkillableMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _unkillableMode = prefs.getBool('unkillable_mode_enabled') ?? false;
    });
  }

  Future<void> _toggleUnkillableMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('unkillable_mode_enabled', value);
    if (!mounted) return;
    setState(() {
      _unkillableMode = value;
    });

    const channel = MethodChannel('com.example.SynCal/sms');
    try {
      await channel.invokeMethod('toggleUnkillableMode', {'enabled': value});
    } catch (e) {
      debugPrint('Failed to toggle native service: $e');
    }
  }

  Future<void> _requestAutoStart() async {
    try {
      var isAvailable = await getAutoStartPermission();
      if (!isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Auto-start is already enabled or not supported on this device.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open Auto-Start settings: $e')),
        );
      }
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = packageInfo.version;
      });
    } catch (_) {}
  }

  void _loadUserInfo() {
    final linkedUser = ApiClient.instance.linkedUser;
    setState(() {
      _synCalId = linkedUser?.syncalId ?? 'Not linked';
      _username = linkedUser?.username ?? '';
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    try {
      await VersionCheckService.checkAndPromptUpdate(context, silent: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update check failed'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
        title: const Text(
          'Logout & Unlink',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to logout and unlink your account?\n\nThis action cannot be undone.',
          style: TextStyle(color: _Palette.mutedLight, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: _Palette.mutedLight)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Yes, Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.instance.unlink();

      final boxes = ['settings', 'user', 'cache'];
      for (var boxName in boxes) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).clear();
        } else {
          await Hive.deleteBoxFromDisk(boxName);
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      if (mounted) {
        context.go(AppRoutes.auth);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── Profile drawer restyled with the same glass surface, hairline
  // border, and pill button treatment as HomeScreen's compose sheet.
  void _showProfileDrawer() {
    final user = ApiClient.instance.linkedUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No account linked')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: _Palette.surface.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _Palette.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _username.isNotEmpty ? _username[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _username.isNotEmpty ? _username : 'User',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user.syncalId,
                              style: TextStyle(
                                color: _Palette.muted,
                                fontSize: 13,
                                fontFamily: 'monospace',
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _profileInfoTile(
                              icon: Icons.fingerprint_rounded,
                              label: 'SynCal ID',
                              value: user.syncalId,
                            ),
                            const SizedBox(height: 10),
                            _profileInfoTile(
                              icon: Icons.person_rounded,
                              label: 'Username',
                              value: _username,
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2), width: 0.5),
                            ),
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _logout,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: const Text(
                                  'Logout & Unlink',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _profileInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white70, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: _Palette.muted, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Report modal restyled with the same glass sheet + pill buttons as
  // HomeScreen's compose sheet.
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                    decoration: BoxDecoration(
                      color: _Palette.surface.withValues(alpha: 0.95),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
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
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(color: _Palette.hairline, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        const Text(
                          'Report a Problem',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Describe the issue you're experiencing.",
                          style: TextStyle(color: _Palette.muted, fontSize: 13),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                          ),
                          child: TextField(
                            controller: controller,
                            maxLines: 5,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            cursorColor: Colors.white,
                            decoration: InputDecoration(
                              hintText: 'Describe the issue…',
                              hintStyle: TextStyle(color: _Palette.muted, fontSize: 13),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                                    ),
                                    child: SizedBox(
                                      height: 48,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                        ),
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text(
                                          'Cancel',
                                          style: TextStyle(color: _Palette.mutedLight, fontSize: 14.5, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                                    ),
                                    child: SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                        ),
                                        onPressed: isSubmitting
                                            ? null
                                            : () async {
                                                final desc = controller.text.trim();
                                                if (desc.isEmpty) return;

                                                setModalState(() => isSubmitting = true);

                                                try {
                                                  final success = await ApiClient.instance.reportProblem(desc);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          success
                                                              ? 'Problem reported successfully. Thank you!'
                                                              : 'Report saved offline. Will sync when online.',
                                                        ),
                                                        backgroundColor: success ? Colors.green : Colors.orangeAccent,
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Failed to report: $e'),
                                                        backgroundColor: Colors.redAccent,
                                                      ),
                                                    );
                                                  }
                                                } finally {
                                                  if (ctx.mounted) Navigator.pop(ctx);
                                                }
                                              },
                                        child: isSubmitting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : const Text(
                                                'Submit',
                                                style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
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
        backgroundColor: _Palette.bg,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                    sliver: SliverList.list(
                      children: [
                        _sectionLabel('Account'),
                        const SizedBox(height: 8),
                        _sectionCard([
                          _settingsTile(
                            icon: Icons.fingerprint_rounded,
                            title: 'SynCal ID',
                            subtitle: _synCalId,
                            onTap: _showProfileDrawer,
                          ),
                        ]),
                        const SizedBox(height: 22),
                        _sectionLabel('Background Execution (Advanced)'),
                        const SizedBox(height: 8),
                        _sectionCard([
                          _settingsTile(
                            icon: Icons.shield_rounded,
                            title: 'Enable Auto-Start',
                            subtitle: 'Prevent the OS from delaying your SMS',
                            onTap: _requestAutoStart,
                            trailing: Icon(Icons.open_in_new_rounded, color: Colors.white.withValues(alpha: 0.25), size: 14),
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.battery_alert_rounded,
                            title: 'Unkillable Mode',
                            subtitle: 'Forces background service to stay alive',
                            onTap: () => _toggleUnkillableMode(!_unkillableMode),
                            trailing: Switch(
                              value: _unkillableMode,
                              onChanged: _toggleUnkillableMode,
                              activeThumbColor: Colors.greenAccent,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 22),
                        _sectionLabel('Updates'),
                        const SizedBox(height: 8),
                        _sectionCard([
                          _settingsTile(
                            icon: Icons.system_update_rounded,
                            title: 'Check for Updates',
                            subtitle: _latestVersion != null ? 'v$_latestVersion available' : null,
                            onTap: _checkingUpdate ? null : _checkForUpdates,
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                                  )
                                : null,
                          ),
                        ]),
                        const SizedBox(height: 22),
                        _sectionLabel('Support'),
                        const SizedBox(height: 8),
                        _sectionCard([
                          _settingsTile(
                            icon: Icons.bug_report_rounded,
                            title: 'Report a Problem',
                            onTap: () => _showReportProblemModal(context),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Text(
                  'SynCal v$_appVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header matching HomeScreen: big title left, glass back chip right.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 19),
            ),
          ),
          const Expanded(
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: _Palette.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  // ── Section card matching HomeScreen's glass surfaces: translucent
  // fill, hairline border, rounded corners.
  Widget _sectionCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1, indent: 64);

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: _Palette.mutedLight, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.25), size: 13),
          ],
        ),
      ),
    );
  }
}
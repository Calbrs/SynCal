import 'package:flutter/material.dart';
import '../services/background_service.dart';
import '../services/sms_gateway_service.dart';

/// Drop this widget anywhere you want to gate the user before they create a
/// schedule — e.g. wrap your "Add Schedule" button, or show it as a banner
/// at the top of the Schedules screen.
///
/// Usage (gate before creating a schedule):
///   onPressed: () async {
///     final ok = await BackgroundPermissionPrompt.ensureGranted(context);
///     if (!ok) return; // user cancelled or didn't grant
///     // proceed to create schedule
///   }
///
/// Usage (always-visible banner):
///   BackgroundPermissionPrompt()
class BackgroundPermissionPrompt extends StatefulWidget {
  /// Called when all permissions are granted (or already were).
  final VoidCallback? onAllGranted;

  const BackgroundPermissionPrompt({super.key, this.onAllGranted});

  /// Shows a bottom sheet and resolves to true only when all permissions
  /// are confirmed granted. Returns false if the user dismisses.
  static Future<bool> ensureGranted(BuildContext context) async {
    final status = await BackgroundService.checkPermissions();
    if (status.allGranted) return true;

    if (!context.mounted) return false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PermissionSheet(),
    );
    return result == true;
  }

  @override
  State<BackgroundPermissionPrompt> createState() =>
      _BackgroundPermissionPromptState();
}

class _BackgroundPermissionPromptState
    extends State<BackgroundPermissionPrompt> with WidgetsBindingObserver {
  BackgroundPermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when the user comes back from the settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await BackgroundService.checkPermissions();
    if (!mounted) return;
    setState(() => _status = s);
    if (s.allGranted) widget.onAllGranted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    if (status.allGranted) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(12),
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Scheduled messages may not work',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _refresh,
                tooltip: 'Re-check permissions',
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Allow the following settings so messages send even when the app is closed:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _PermissionTile(
              icon: Icons.alarm,
              label: 'Exact alarm permission',
              granted: status.canScheduleExactAlarms,
              onTap: () async {
                await SmsGatewayService.requestExactAlarmPermission();
                // User is taken to system settings — re-check on resume
              },
            ),
            _PermissionTile(
              icon: Icons.battery_saver,
              label: 'Battery optimization — tap to disable for this app',
              granted: status.isIgnoringBatteryOptimizations,
              onTap: () async {
                await SmsGatewayService.requestIgnoreBatteryOptimizations();
              },
            ),
            // Autostart cannot be checked programmatically, so always show it.
            _PermissionTile(
              icon: Icons.rocket_launch_outlined,
              label: 'Autostart — tap to enable in Phone Manager',
              granted: null, // unknown — always show as actionable
              onTap: () async {
                final openedSpecific =
                    await SmsGatewayService.openAutostartSettings();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(openedSpecific
                        ? 'Find this app and enable Autostart'
                        : 'Find this app in the list and allow it to start automatically'),
                    duration: const Duration(seconds: 5),
                  ));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? granted; // null = unknown (autostart)
  final VoidCallback onTap;

  const _PermissionTile({
    required this.icon,
    required this.label,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = granted == true;
    final isUnknown = granted == null;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon,
          color: isGranted
              ? Colors.green
              : isUnknown
                  ? Colors.orange
                  : Colors.red),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: isGranted
          ? const Icon(Icons.check_circle, color: Colors.green)
          : TextButton(
              onPressed: onTap,
              child: Text(isUnknown ? 'Open' : 'Fix'),
            ),
    );
  }
}

/// Full-screen bottom sheet version — used by BackgroundPermissionPrompt.ensureGranted()
class _PermissionSheet extends StatefulWidget {
  const _PermissionSheet();

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet>
    with WidgetsBindingObserver {
  BackgroundPermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await BackgroundService.checkPermissions();
    if (!mounted) return;
    setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ Required permissions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'These settings let SynCal send scheduled messages even when the '
              'app is closed or the phone was restarted. Please enable all three.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            if (status == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              _SheetTile(
                icon: Icons.alarm,
                title: 'Exact alarm permission',
                subtitle: 'Lets the app wake up at the exact scheduled time.',
                granted: status.canScheduleExactAlarms,
                onTap: () async {
                  await SmsGatewayService.requestExactAlarmPermission();
                },
              ),
              const SizedBox(height: 12),
              _SheetTile(
                icon: Icons.battery_saver,
                title: 'Disable battery optimization',
                subtitle:
                    'Prevents the OS from killing background tasks before '
                    'your message is sent.',
                granted: status.isIgnoringBatteryOptimizations,
                onTap: () async {
                  await SmsGatewayService.requestIgnoreBatteryOptimizations();
                },
              ),
              const SizedBox(height: 12),
              _SheetTile(
                icon: Icons.rocket_launch_outlined,
                title: 'Enable Autostart',
                subtitle:
                    'Required on Infinix, Tecno, Itel, Xiaomi, Huawei and '
                    'similar phones. Opens Phone Manager — find this app and '
                    'turn Autostart ON.',
                granted: null,
                onTap: () async {
                  final opened =
                      await SmsGatewayService.openAutostartSettings();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(opened
                          ? 'Find SynCal in the list and enable Autostart'
                          : 'Find SynCal in App Info and allow background activity'),
                      duration: const Duration(seconds: 6),
                    ));
                  }
                },
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip (not recommended)'),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Done / Re-check'),
                onPressed: () async {
                  await _refresh();
                  final s = _status;
                  if (s != null && s.allGranted && context.mounted) {
                    Navigator.pop(context, true);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                        'Some permissions are still missing. '
                        'Autostart cannot be verified automatically — '
                        'make sure you enabled it in Phone Manager.',
                      ),
                      duration: Duration(seconds: 5),
                    ));
                  }
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? granted;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = granted == true;
    final isUnknown = granted == null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isGranted
              ? Colors.green.shade200
              : isUnknown
                  ? Colors.orange.shade200
                  : Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(10),
        color: isGranted
            ? Colors.green.shade50
            : isUnknown
                ? Colors.orange.shade50
                : Colors.red.shade50,
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isGranted
                ? Colors.green
                : isUnknown
                    ? Colors.orange
                    : Colors.red),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: isGranted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isUnknown ? Colors.orange : Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: Text(isUnknown ? 'Open' : 'Fix',
                    style: const TextStyle(fontSize: 12)),
              ),
      ),
    );
  }
}
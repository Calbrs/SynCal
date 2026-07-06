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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B), // zinc900
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Background settings required',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14.5),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: Colors.white70),
              onPressed: _refresh,
              tooltip: 'Re-check permissions',
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Infinix & other phones aggressively kill background processes. Allow these settings to ensure messages send on time:',
            style: TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.3),
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            icon: Icons.alarm,
            label: 'Exact alarm permission',
            granted: status.canScheduleExactAlarms,
            onTap: () async {
              await SmsGatewayService.requestExactAlarmPermission();
            },
          ),
          _PermissionTile(
            icon: Icons.battery_saver,
            label: 'Ignore battery optimizations',
            granted: status.isIgnoringBatteryOptimizations,
            onTap: () async {
              await SmsGatewayService.requestIgnoreBatteryOptimizations();
            },
          ),
          _PermissionTile(
            icon: Icons.rocket_launch_outlined,
            label: 'Enable Autostart (Phone Manager)',
            granted: null,
            onTap: () async {
              final openedSpecific =
                  await SmsGatewayService.openAutostartSettings();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(openedSpecific
                      ? 'Find SynCal and enable Autostart'
                      : 'Find SynCal and allow automatic background startup'),
                  duration: const Duration(seconds: 5),
                ));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? granted;
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isGranted
                ? Colors.greenAccent
                : isUnknown
                    ? Colors.orangeAccent
                    : Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9)),
            ),
          ),
          if (isGranted)
            const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 18)
          else
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: isUnknown ? Colors.orangeAccent : Colors.redAccent,
              ),
              child: Text(
                isUnknown ? 'Open' : 'Fix',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
        ],
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

    final AccentColor = isGranted
        ? Colors.greenAccent
        : isUnknown
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AccentColor.withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF18181B), // zinc900
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(
            icon,
            color: AccentColor,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          trailing: isGranted
              ? const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent)
              : ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isUnknown ? Colors.orangeAccent : Colors.redAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isUnknown ? 'Open' : 'Fix',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
        ),
      ),
    );
  }
}
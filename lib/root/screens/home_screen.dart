import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact.dart';
import '../models/sms_session.dart';
import '../../services/sms_gateway_service.dart';
import '../../services/sms_session_store.dart';
import '../../services/version_check_service.dart';
import '../app_routes.dart';

class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  const ShimmerLoading({super.key, required this.child, this.isLoading = true});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isLoading
        ? AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Opacity(
                opacity: 0.2 + 0.6 * _animation.value,
                child: widget.child,
              );
            },
          )
        : widget.child;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color zinc950 = Color(0xFF09090B);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc700 = Color(0xFF3F3F46);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);

  List<SimCard> _simCards = [];
  SimCard? _selectedSim;
  bool _simLoaded = false;
  bool _permissionsGranted = false;

  bool _showUpdateBanner = false;
  String? _latestVersion;
  String? _localApkPath;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initSms();
    _checkForUpdate();
  }

  Future<void> _initSms() async {
    final granted = await SmsGatewayService.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _simLoaded = true;
        _permissionsGranted = false;
      });
      return;
    }
    final sims = await SmsGatewayService.getSimCards();
    if (mounted) {
      setState(() {
        _simCards = sims;
        _selectedSim = sims.isNotEmpty ? sims.first : null;
        _simLoaded = true;
        _permissionsGranted = true;
      });
    }
  }

  bool _hasContactsWithNumbers() {
    final box = Hive.box<Contact>('contacts');
    return box.values.any((c) => c.phones.isNotEmpty);
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await VersionCheckService.checkForUpdate();
      if (!mounted) return;
      if (result != null && result.hasUpdate) {
        setState(() {
          _showUpdateBanner = true;
          _latestVersion = result.latestVersion;
          _localApkPath = result.localApkPath;
        });
      }
    } catch (_) {}
  }

  void _startDownload() async {
    if (_latestVersion == null) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    try {
      final apkPath = await VersionCheckService.downloadApk(
        version: _latestVersion!,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (mounted) {
        setState(() {
          _localApkPath = apkPath;
          _isDownloading = false;
          _downloadProgress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _triggerUpdate() async {
    if (_localApkPath == null) {
      if (!_isDownloading) _startDownload();
      return;
    }

    final canInstall = await SmsGatewayService.canInstallPackages();
    if (!canInstall) {
      final granted = await SmsGatewayService.requestInstallPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable "Install unknown apps" in Settings to update.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    try {
      await SmsGatewayService.installApk(_localApkPath!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Install failed: $e')),
        );
      }
    }
  }

  Widget _buildUpdateBanner() {
    final isReady = _localApkPath != null && !_isDownloading;
    final showProgress = _isDownloading;

    return AnimatedSlide(
      offset: _showUpdateBanner ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 350),
      child: AnimatedOpacity(
        opacity: _showUpdateBanner ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.3), width: 0.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: const Color(0xFFFFB800).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.system_update_rounded, color: Color(0xFFFFB800), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Update available', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                            if (_latestVersion != null) Text('v$_latestVersion', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _triggerUpdate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: const Color(0xFFFFB800), borderRadius: BorderRadius.circular(20)),
                          child: Text(isReady ? 'Install' : 'Download', style: const TextStyle(color: Colors.black, fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _showUpdateBanner = false),
                        child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.35), size: 18),
                      ),
                    ],
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress, minHeight: 4, backgroundColor: Colors.white.withValues(alpha: 0.1), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFB800))),
                    const SizedBox(height: 4),
                    Text('${(_downloadProgress * 100).toStringAsFixed(0)}% downloaded', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indicatorColor = _permissionsGranted ? Colors.green : Colors.orangeAccent;
    final indicatorLabel = _permissionsGranted ? 'Online' : 'No Permission';
    final hasContacts = _hasContactsWithNumbers();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: zinc950,
        extendBody: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('SynCal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('powered by calbrs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: zinc500, letterSpacing: 0.5)),
                  ],
                ),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: indicatorColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        children: [
                          AnimatedContainer(duration: const Duration(milliseconds: 400), width: 8, height: 8, decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(indicatorLabel, style: TextStyle(color: indicatorColor, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26), onPressed: () => _showMainDrawer(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Consumer<SmsSessionStore>(
          builder: (context, store, _) {
            if (!store.isLoaded) {
              return const Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2));
            }
            return Stack(
              children: [
                store.sessions.isEmpty
                    ? Center(
                        child: Text(
                          'No messages sent yet.\nTap Send Message to start.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: zinc500, fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
                        itemCount: store.sessions.length,
                        itemBuilder: (context, index) {
                          final session = store.sessions[index];
                          return _SessionCard(
                            session: session,
                            onTap: () => _showSessionDetail(context, session.id),
                            onDelete: () => _confirmDeleteSession(context, session.id),
                          );
                        },
                      ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showUpdateBanner) ...[_buildUpdateBanner(), const SizedBox(height: 10)],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                              ),
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                  onPressed: (_simLoaded && _permissionsGranted && hasContacts)
                                      ? () => _showMessageDrawer(context)
                                      : null,
                                  child: Text(
                                    _permissionsGranted
                                        ? (hasContacts ? 'Send Message' : 'No Contacts')
                                        : 'Permissions Required',
                                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3),
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
              ],
            );
          },
        ),
      ),
    );
  }

  void _showMainDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            decoration: BoxDecoration(
              color: zinc900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: zinc700, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                _buildTile(
                  icon: Icons.contacts_rounded,
                  title: 'Contacts',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) context.push(AppRoutes.createEvent);
                  },
                ),
                const SizedBox(height: 4),
                _buildTile(
                  icon: Icons.link_rounded,
                  title: 'Links',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) context.push(AppRoutes.links);
                  },
                ),
                const SizedBox(height: 4),
                _buildTile(
                  icon: Icons.schedule_rounded,
                  title: 'Scheduled',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) context.push(AppRoutes.scheduled);
                  },
                ),
                const SizedBox(height: 4),
                _buildTile(
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  onTap: () {
                    Navigator.pop(ctx);
                    if (mounted) context.push(AppRoutes.settings);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: zinc800,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
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
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.3), size: 14),
          ],
        ),
      ),
    );
  }

  void _showMessageDrawer(BuildContext context) {
    final msgController = TextEditingController();
    SimCard? drawerSim = _selectedSim;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 2,
              left: 1,
              right: 1,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  decoration: BoxDecoration(
                    color: zinc900,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(color: zinc700, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const Text(
                        'Send Message',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Compose and broadcast to your contacts',
                        style: TextStyle(color: zinc400, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      _buildTileWithTrailing(
                        icon: Icons.sim_card_rounded,
                        title: 'SIM Card',
                        subtitle: drawerSim?.displayName ?? 'Select SIM',
                        trailing: Icon(Icons.arrow_drop_down, color: zinc400, size: 24),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (ctx2) => Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: zinc900,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: _simCards.map((s) => ListTile(
                                  title: Text('${s.displayName} — ${s.carrierName}',
                                      style: const TextStyle(color: Colors.white)),
                                  onTap: () {
                                    Navigator.pop(ctx2);
                                    setModalState(() => drawerSim = s);
                                  },
                                )).toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: msgController,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: TextStyle(color: zinc500, fontSize: 13),
                          filled: true,
                          fillColor: zinc800,
                          contentPadding: const EdgeInsets.only(left: 2, right: 16, top: 16, bottom: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: zinc700, width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: zinc400, width: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                backgroundColor: zinc800,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel', style: TextStyle(color: zinc400, fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: zinc950,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                final text = msgController.text.trim();
                                if (text.isEmpty) return;
                                Navigator.pop(ctx);
                                if (mounted) {
                                  context.read<SmsSessionStore>().startSession(
                                    message: text,
                                    simSlot: drawerSim?.slotIndex ?? -1,
                                    simLabel: drawerSim?.displayName ?? 'Default SIM',
                                  );
                                }
                              },
                              child: const Text('Send', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
        });
      },
    );
  }

  Widget _buildTileWithTrailing({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: zinc800,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
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
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(subtitle, style: TextStyle(color: zinc400, fontSize: 12)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  void _showSessionDetail(BuildContext context, String sessionId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: zinc900,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
                ),
                child: ListenableBuilder(
                  listenable: context.read<SmsSessionStore>(),
                  builder: (context, _) {
                    final store = context.read<SmsSessionStore>();
                    final session = store.sessions.firstWhere(
                      (s) => s.id == sessionId,
                      orElse: () => throw Exception('Session not found'),
                    );
                    return _SessionDetailContent(
                      session: session,
                      scrollController: scrollController,
                      store: store,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context, String sessionId) {
    final store = context.read<SmsSessionStore>();
    final session = store.sessions.firstWhere((s) => s.id == sessionId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: zinc900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete log?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove the session log from ${DateFormat('MMM dd, HH:mm').format(session.startedAt)}.',
          style: TextStyle(color: zinc400, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: zinc400)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                store.deleteSession(sessionId);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _SessionDetailContent extends StatelessWidget {
  final SmsSession session;
  final ScrollController scrollController;
  final SmsSessionStore store;

  const _SessionDetailContent({
    required this.session,
    required this.scrollController,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFF3F3F46), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy — HH:mm').format(session.startedAt),
                    style: TextStyle(color: const Color(0xFF71717A), fontSize: 13),
                  ),
                  _buildStateBadge(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                session.message,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: session.progressFraction,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    session.isComplete
                        ? (session.failedCount == 0 ? Colors.greenAccent : Colors.orangeAccent)
                        : Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStatsCard(),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF27272A), thickness: 0.5),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: session.recipients.length,
            itemBuilder: (_, i) {
              final r = session.recipients[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _recipientIcon(r.status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            r.phone,
                            style: TextStyle(color: const Color(0xFF71717A), fontSize: 13),
                          ),
                          if (r.error != null)
                            Text(
                              r.error!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if ((r.retryCount > 0) || ((r.deliveryRetryCount ?? 0) > 0))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '↺ ${r.retryCount + (r.deliveryRetryCount ?? 0)}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Session Stats',
                style: TextStyle(
                  color: const Color(0xFFA1A1AA),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'SIM: ${session.simLabel}',
                style: TextStyle(color: const Color(0xFF71717A), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statItem('Total', session.totalCount.toString(), const Color(0xFFD4D4D8)),
              const SizedBox(width: 20),
              _statItem('Sent ✓', session.sentCount.toString(), Colors.greenAccent),
              const SizedBox(width: 20),
              _statItem('Failed ✗', session.failedCount.toString(), Colors.redAccent),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _statItem('Pending ⌛', session.pendingCount.toString(), const Color(0xFF71717A)),
              const SizedBox(width: 20),
              _statItem('Not Delivered ⚠️', session.sentButNotDeliveredCount.toString(), Colors.orangeAccent),
              const Spacer(),
              if (session.retryPass > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Retry ${session.retryPass}',
                    style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              if (!session.isComplete) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Running',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if ((session.failedCount > 0 || session.sentButNotDeliveredCount > 0) && session.isComplete)
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _retrySession(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Failed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _retrySession() {
    store.retrySession(session.id);
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(color: const Color(0xFF71717A), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStateBadge() {
    String label;
    Color color;

    if (!session.isComplete) {
      label = session.state == SmsSessionState.retrying ? 'Retrying…' : 'Sending…';
      color = Colors.blueAccent;
    } else if (session.failedCount == 0) {
      label = 'Done ✓';
      color = Colors.greenAccent;
    } else {
      label = '${session.failedCount} failed';
      color = Colors.orangeAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _recipientIcon(SmsRecipientStatus status) {
    switch (status) {
      case SmsRecipientStatus.sent:
        return const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20);
      case SmsRecipientStatus.sentNotDelivered:
        return const Icon(Icons.check_circle_outline_rounded, color: Colors.orangeAccent, size: 20);
      case SmsRecipientStatus.failed:
        return const Icon(Icons.error_rounded, color: Colors.redAccent, size: 20);
      case SmsRecipientStatus.pending:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF71717A)),
        );
    }
  }
}

class _SessionCard extends StatelessWidget {
  final SmsSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({required this.session, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isRunning = !session.isComplete;
    final progressColor = isRunning
        ? Colors.blueAccent
        : (session.failedCount == 0 ? Colors.greenAccent : Colors.orangeAccent);

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (!session.isComplete) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot delete a session that is still running.')),
            );
          }
          return false;
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2), width: 0.5),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(height: 4),
            Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, HH:mm').format(session.startedAt),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12.5),
                  ),
                  Row(
                    children: [
                      _buildBadge(session, isRunning, progressColor),
                      if (session.isComplete) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onDelete,
                          child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.2), size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                session.message,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: session.progressFraction,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _chip('${session.sentCount}/${session.totalCount} sent', Colors.greenAccent),
                  const SizedBox(width: 8),
                  if (session.failedCount > 0) _chip('${session.failedCount} failed', Colors.redAccent),
                  if (isRunning && session.pendingCount > 0) ...[
                    const SizedBox(width: 8),
                    _chip('${session.pendingCount} pending', Colors.white38),
                  ],
                  const Spacer(),
                  Text(
                    session.simLabel,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(SmsSession session, bool isRunning, Color progressColor) {
    String label;
    if (!session.isComplete) {
      label = session.state == SmsSessionState.retrying ? 'Retrying…' : 'Sending…';
    } else if (session.failedCount == 0) {
      label = 'Done ✓';
    } else {
      label = '${session.failedCount} failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: progressColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: progressColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
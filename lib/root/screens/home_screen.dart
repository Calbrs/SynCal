// lib/root/screens/home_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sms_session.dart';
import '../../services/sms_gateway_service.dart';
import '../../services/sms_session_store.dart';
import '../../services/version_check_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SimCard> _simCards = [];
  SimCard? _selectedSim;
  bool _simLoaded = false;
  bool _permissionsGranted = false;

  bool _showUpdateBanner = false;
  String? _latestVersion;
  String? _localApkPath;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _updateError;

  static const _channel = MethodChannel('com.example.synccal/sms');

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
      _updateError = null;
    });

    try {
      final apkPath = await VersionCheckService.downloadApk(
        version: _latestVersion!,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
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
          _updateError = e.toString();
        });
      }
    }
  }

  Future<void> _triggerUpdate() async {
    if (_localApkPath != null) {
      try {
        await _channel.invokeMethod('installApk', {'filePath': _localApkPath});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Install failed: $e'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
      }
    } else if (!_isDownloading) {
      _startDownload();
    }
  }

  Widget _buildUpdateBanner() {
    final isReady = _localApkPath != null && !_isDownloading;
    final showProgress = _isDownloading;

    return AnimatedSlide(
      offset: _showUpdateBanner ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
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
                border: Border.all(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                    width: 0.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.system_update_rounded,
                            color: Color(0xFFFFB800), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Update available',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_latestVersion != null)
                              Text(
                                'v$_latestVersion',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (showProgress)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            value: _downloadProgress,
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _triggerUpdate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB800),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isReady ? 'Install' : 'Download',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _showUpdateBanner = false),
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.35), size: 18),
                      ),
                    ],
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFB800)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_downloadProgress * 100).toStringAsFixed(0)}% downloaded',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  if (_updateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Download failed: ${_updateError!.substring(0, 60)}${_updateError!.length > 60 ? '...' : ''}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('SyncCal',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text('powered by calbrs',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 0.5)),
                  ],
                ),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: indicatorColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: indicatorColor,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(indicatorLabel,
                              style: TextStyle(
                                color: indicatorColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 26),
                      onPressed: () => _showMenuDrawer(context),
                    ),
                  ],
                ),
              ],
            ),
            shape: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
          ),
        ),
        body: Consumer<SmsSessionStore>(
          builder: (context, store, _) {
            if (!store.isLoaded) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2),
              );
            }

            return Stack(
              children: [
                store.sessions.isEmpty
                    ? Center(
                        child: Text(
                          'No messages sent yet.\nTap Send Message to start.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 15),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
                        itemCount: store.sessions.length,
                        itemBuilder: (context, index) {
                          final session = store.sessions[index];
                          return _SessionCard(
                            session: session,
                            onTap: () => _showSessionDetail(context, session),
                            onDelete: () => _confirmDeleteSession(context, session),
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
                      if (_showUpdateBanner) ...[
                        _buildUpdateBanner(),
                        const SizedBox(height: 10),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0x26FFFFFF),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 0.5,
                                ),
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
                                  onPressed: _simLoaded && _permissionsGranted
                                      ? () => _showMessageDrawer(context)
                                      : null,
                                  child: Text(
                                    _permissionsGranted ? 'Send Message' : 'Permissions Required',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
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
              ],
            );
          },
        ),
      ),
    );
  }

  // ==================== Drawer & Modals ====================

  void _showMenuDrawer(BuildContext context) {
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
              color: const Color(0xFF1E1E22),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _drawerTile(
                        title: 'Contacts',
                        icon: Icons.contacts_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/create-event');
                        },
                      ),
                      Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.08)),
                      _drawerTile(
                        title: 'Settings',
                        icon: Icons.settings_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/settings');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400)),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
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
                      if (_simCards.length > 1) ...[
                        const Text('SIM Card', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SimCard>(
                              value: drawerSim,
                              dropdownColor: const Color(0xFF2A2A2E),
                              isExpanded: true,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              iconEnabledColor: Colors.white54,
                              items: _simCards
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text('${s.displayName} — ${s.carrierName}'),
                                      ))
                                  .toList(),
                              onChanged: (s) => setModalState(() => drawerSim = s),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      TextField(
                        controller: msgController,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: 'Type your message here...',
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
                              onPressed: () {
                                final text = msgController.text.trim();
                                if (text.isEmpty) return;
                                Navigator.pop(ctx);
                                context.read<SmsSessionStore>().startSession(
                                      message: text,
                                      simSlot: drawerSim?.slotIndex ?? -1,
                                      simLabel: drawerSim?.displayName ?? 'Default SIM',
                                    );
                              },
                              child: const Text('Send', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  void _showSessionDetail(BuildContext context, SmsSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2E),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 0.5)),
                ),
                child: ListenableBuilder(
                  listenable: context.read<SmsSessionStore>(),
                  builder: (_, _) {
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
                                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    DateFormat('MMM dd, yyyy — HH:mm').format(session.startedAt),
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                                  ),
                                  _sessionStateBadge(session),
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
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    session.isComplete
                                        ? (session.failedCount == 0 ? Colors.greenAccent : Colors.orangeAccent)
                                        : Colors.blueAccent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _statChip('${session.sentCount} sent', Colors.greenAccent),
                                  const SizedBox(width: 8),
                                  _statChip('${session.failedCount} failed', Colors.redAccent),
                                  const SizedBox(width: 8),
                                  _statChip('${session.pendingCount} pending', Colors.white38),
                                  const Spacer(),
                                  Text('SIM: ${session.simLabel}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                                ],
                              ),
                              if (session.retryPass > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Retry pass: ${session.retryPass} / ${SmsSession.maxRetries}',
                                    style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.8), fontSize: 12),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white10, thickness: 0.5),
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
                                          Text(r.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                                          Text(r.phone, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                                          if (r.error != null)
                                            Text(r.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    if (r.retryCount > 0)
                                      Text('↺ ${r.retryCount}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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

  void _confirmDeleteSession(BuildContext context, SmsSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete log?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove the session log from ${DateFormat('MMM dd, HH:mm').format(session.startedAt)}.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<SmsSessionStore>().deleteSession(session.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _recipientIcon(SmsRecipientStatus status) {
    switch (status) {
      case SmsRecipientStatus.sent:
        return const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20);
      case SmsRecipientStatus.failed:
        return const Icon(Icons.error_rounded, color: Colors.redAccent, size: 20);
      case SmsRecipientStatus.pending:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.5)),
        );
    }
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sessionStateBadge(SmsSession session) {
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot delete a session that is still running.')),
          );
          return false;
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 0.5),
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
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, HH:mm').format(session.startedAt),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
                  ),
                  Row(
                    children: [
                      _buildBadge(session, isRunning, progressColor),
                      if (session.isComplete) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onDelete,
                          child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.3), size: 18),
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
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
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
                  Text(session.simLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11.5)),
                ],
              ),
              if (session.retryPass > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Retry ${session.retryPass}/${SmsSession.maxRetries}',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5),
                  ),
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
      decoration: BoxDecoration(color: progressColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: progressColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}
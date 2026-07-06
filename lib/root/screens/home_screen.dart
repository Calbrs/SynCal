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

/// ── Shared theme tokens (kept identical to the onboarding screen so the
/// whole app reads as one continuous surface, not a patchwork of screens).
class _Palette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color surface = Color(0xFF18181B);
  static const Color hairline = Color(0xFF3F3F46);
  static const Color muted = Color(0xFF71717A);
  static const Color mutedLight = Color(0xFFA1A1AA);
}

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
  bool _requestingPermissions = false;

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

  // Re-triggers the OS permission dialog on demand (e.g. when the user taps
  // the disabled "Permissions Required" button) instead of only asking once
  // on first launch.
  Future<void> _requestPermissionsNow() async {
    if (_requestingPermissions) return;
    setState(() => _requestingPermissions = true);
    try {
      final granted = await SmsGatewayService.requestPermissions();
      if (!mounted) return;
      if (granted) {
        final sims = await SmsGatewayService.getSimCards();
        if (mounted) {
          setState(() {
            _simCards = sims;
            _selectedSim = sims.isNotEmpty ? sims.first : null;
            _simLoaded = true;
            _permissionsGranted = true;
          });
        }
      } else {
        setState(() {
          _simLoaded = true;
          _permissionsGranted = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS permissions are required to send messages.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
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

  // ── Simple, casual update banner: a thin pill instead of a heavy card.
  Widget _buildUpdateBanner() {
    final isReady = _localApkPath != null && !_isDownloading;
    return AnimatedSlide(
      offset: _showUpdateBanner ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showUpdateBanner ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: _triggerUpdate,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_upward_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isDownloading
                        ? 'Updating… ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                        : (isReady
                            ? 'Update ready — v${_latestVersion ?? ''}'
                            : 'New version v${_latestVersion ?? ''} available'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  isReady ? 'Install' : 'Update',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _showUpdateBanner = false),
                  child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.35), size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indicatorColor = _permissionsGranted ? Colors.green : Colors.orangeAccent;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Palette.bg,
        extendBody: true,
        // ── Cupertino-style large-title header instead of a Material AppBar.
        body: SafeArea(
          bottom: false,
          child: Consumer<SmsSessionStore>(
            builder: (context, store, _) {
              return ValueListenableBuilder<Box<Contact>>(
                valueListenable: Hive.box<Contact>('contacts').listenable(),
                builder: (context, contactBox, _) {

                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeader(indicatorColor),
                      ),
                      if (_showUpdateBanner)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                            child: _buildUpdateBanner(),
                          ),
                        ),
                      if (!store.isLoaded)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2)),
                        )
                      else if (store.sessions.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                          sliver: SliverList.builder(
                            itemCount: store.sessions.length,
                            itemBuilder: (context, index) {
                              final session = store.sessions[index];
                              return _SessionBanner(
                                session: session,
                                onTap: () => context.push('${AppRoutes.sessionDetail}/${session.id}'),
                                onDelete: () => store.deleteSession(session.id),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        // ── Schedule (clock) + Send Message share one row at the bottom.
        floatingActionButton: _buildBottomActionRow(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildHeader(Color indicatorColor) {
    final indicatorLabel = _permissionsGranted ? 'Online' : 'No Permission';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SynCal',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'powered by calbrs',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _Palette.muted, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(indicatorLabel, style: TextStyle(color: indicatorColor, fontSize: 12.5, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (menuContext) => GestureDetector(
                  onTap: () => _showMenuPopup(menuContext),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                    ),
                    child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline_rounded, color: Colors.white.withValues(alpha: 0.3), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap Send Message below to start.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _Palette.muted, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ── Schedule (clock) button + Send Message button share one horizontal
  // row, floating together at the bottom — same as before, but the clock
  // action now lives here instead of inside the drawer list.
  Widget _buildBottomActionRow() {
    final hasContacts = _hasContactsWithNumbers();
    final canAct = _simLoaded && _permissionsGranted && hasContacts;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.schedule_rounded,
            tooltip: 'Schedule a message',
            onPressed: canAct
                ? () => context.push(AppRoutes.addSchedule)
                : (_permissionsGranted ? null : _requestPermissionsNow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                  ),
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      // If permissions aren't granted, tapping triggers the
                      // OS permission request instead of doing nothing.
                      onPressed: !_simLoaded
                          ? null
                          : (!_permissionsGranted
                              ? _requestPermissionsNow
                              : (hasContacts ? () => _showMessageDrawer(context) : null)),
                      child: _requestingPermissions
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _permissionsGranted ? Icons.send_rounded : Icons.lock_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _permissionsGranted
                                      ? (hasContacts ? 'Send Message' : 'No Contacts')
                                      : 'Grant Permissions',
                                  style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Anchored popup card: locates itself 2px under the tapped menu button
  // instead of sliding up as a bottom sheet. Tapping outside dismisses it.
  void _showMenuPopup(BuildContext anchorContext) {
    final renderBox = anchorContext.findRenderObject() as RenderBox;
    final buttonSize = renderBox.size;
    final buttonOffset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(anchorContext).size.width;

    const cardWidth = 220.0;
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => entry.remove(),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: buttonOffset.dy + buttonSize.height + 2,
              left: (buttonOffset.dx + buttonSize.width - cardWidth)
                  .clamp(12.0, screenWidth - cardWidth - 12.0),
              child: _MenuPopupCard(
                width: cardWidth,
                onClose: () => entry.remove(),
                onContacts: () {
                  entry.remove();
                  if (mounted) context.push(AppRoutes.createEvent);
                },
                onLinks: () {
                  entry.remove();
                  if (mounted) context.push(AppRoutes.links);
                },
                onScheduled: () {
                  entry.remove();
                  if (mounted) context.push(AppRoutes.scheduled);
                },
                onSettings: () {
                  entry.remove();
                  if (mounted) context.push(AppRoutes.settings);
                },
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(anchorContext).insert(entry);
  }

  // ── Digital/professional compose sheet: monospace metadata line, live
  // character + segment counter, and a terminal-style SIM status readout
  // instead of playful pill chips.
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                  decoration: BoxDecoration(
                    color: _Palette.surface.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
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
                      Row(
                        children: [
                          const Text(
                            'COMPOSE_MESSAGE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, color: Colors.white54, size: 15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // ── SIM selector: one row, two side-by-side option
                      // buttons (segmented style), same pattern as before.
                      if (_simCards.isNotEmpty)
                        Row(
                          children: List.generate(_simCards.length, (i) {
                            final sim = _simCards[i];
                            final selected = drawerSim?.slotIndex == sim.slotIndex;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: i == _simCards.length - 1 ? 0 : 8),
                                child: GestureDetector(
                                  onTap: () => setModalState(() => drawerSim = sim),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: selected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
                                        width: 0.8,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      sim.displayName,
                                      style: TextStyle(
                                        color: selected ? Colors.white : _Palette.mutedLight,
                                        fontSize: 13,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: msgController,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                        cursorColor: Colors.white,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Type your message…',
                          hintStyle: TextStyle(color: _Palette.muted, fontSize: 13),
                          filled: true,
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          contentPadding: const EdgeInsets.all(16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ── Live char / segment counter, monospace, digital feel.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: msgController,
                        builder: (context, value, _) {
                          final len = value.text.length;
                          final segments = len == 0 ? 0 : (len / 160).ceil();
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$len CHR · $segments SEG',
                              style: TextStyle(color: _Palette.muted, fontSize: 11, fontFamily: 'monospace', letterSpacing: 0.5),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                            ),
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text('Dispatch', style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                                  ],
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
        });
      },
    );
  }
}

/// ── Small circular glass icon button used for the schedule action next to
/// Send Message in the bottom row.
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  const _GlassIconButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
          ),
          child: SizedBox(
            height: 54,
            width: 54,
            child: IconButton(
              icon: Icon(icon, color: onPressed == null ? Colors.white30 : Colors.white, size: 22),
              tooltip: tooltip,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Anchored popup card shown 2px below the menu button. Renders as a
/// compact list card rather than a full-height bottom sheet.
class _MenuPopupCard extends StatelessWidget {
  final double width;
  final VoidCallback onClose;
  final VoidCallback onContacts;
  final VoidCallback onLinks;
  final VoidCallback onScheduled;
  final VoidCallback onSettings;

  const _MenuPopupCard({
    required this.width,
    required this.onClose,
    required this.onContacts,
    required this.onLinks,
    required this.onScheduled,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.scale(
              alignment: Alignment.topRight,
              scale: 0.92 + (0.08 * t),
              child: child,
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: _Palette.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MenuPopupItem(icon: Icons.contacts_rounded, label: 'Contacts', onTap: onContacts),
                  _menuDivider(),
                  _MenuPopupItem(icon: Icons.link_rounded, label: 'Link Management', onTap: onLinks),
                  _menuDivider(),
                  _MenuPopupItem(icon: Icons.schedule_rounded, label: 'Scheduled Messages', onTap: onScheduled),
                  _menuDivider(),
                  _MenuPopupItem(icon: Icons.settings_rounded, label: 'Settings', onTap: onSettings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuDivider() => Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.06), indent: 14, endIndent: 14);
}

class _MenuPopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuPopupItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 17),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ── Simple, casual banner-style session row. No card elevation, no boxy
/// stats grid — just a thin colored accent bar, a one-line status, and a
/// slim progress underline. Reads more like a notification than a widget.
class _SessionBanner extends StatelessWidget {
  final SmsSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _SessionBanner({required this.session, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isRunning = !session.isComplete;
    final accentColor = isRunning
        ? Colors.blueAccent
        : (session.failedCount == 0 ? Colors.greenAccent : Colors.orangeAccent);

    String status;
    if (isRunning) {
      status = session.state == SmsSessionState.retrying ? 'Retrying' : 'Sending';
    } else if (session.failedCount == 0) {
      status = 'Delivered';
    } else {
      status = '${session.failedCount} failed';
    }

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
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
        margin: const EdgeInsets.only(bottom: 2),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: 0.7), size: 20),
      ),
      // ── Simple casual log line instead of a stat card: a status dot,
      // the message, a relative time, and nothing else — reads like a
      // notification feed entry rather than a dashboard widget.
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$status · ${_relativeTime(session.startedAt)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${session.sentCount}/${session.totalCount}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM dd').format(time);
  }
}
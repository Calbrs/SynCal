import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/scheduled_message_store.dart';
import '../models/scheduled_message.dart';
import 'add_schedule_screen.dart';
import '../../services/background_service.dart';
import '../../services/background_permission_prompt.dart';

/// ── Shared palette, identical to HomeScreen's _Palette.
class _Palette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color muted = Color(0xFF71717A);
}

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  State<ScheduledMessagesScreen> createState() => _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundService.processNow();
    });
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
          child: Consumer<ScheduledMessageStore>(
            builder: (context, store, _) {
              return CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, store)),
                  if (!store.isLoaded)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2)),
                    )
                  else if (store.schedules.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                      sliver: SliverList.list(
                        children: [
                          const BackgroundPermissionPrompt(),
                          const SizedBox(height: 4),
                          ...store.schedules.map((schedule) {
                            return _ScheduleBanner(
                              schedule: schedule,
                              onTap: () => _editSchedule(context, schedule),
                              onToggle: () => store.toggleActive(schedule.id),
                              onDelete: () => store.deleteSchedule(schedule.id),
                            );
                          }),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        floatingActionButton: _buildAddButton(context),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  // ── Header matching HomeScreen: big title left, back + refresh glass
  // chips right.
  Widget _buildHeader(BuildContext context, ScheduledMessageStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scheduled',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  store.isLoaded ? '${store.schedules.length} upcoming messages' : 'Loading…',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _Palette.muted, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await BackgroundService.processNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Checked for due schedules')),
                );
              }
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 19),
            ),
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
              child: Icon(Icons.schedule_rounded, color: Colors.white.withValues(alpha: 0.3), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'No scheduled messages',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap New Schedule below to start.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _Palette.muted, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add button styled exactly like HomeScreen's "Send Message" pill:
  // wide glass pill with icon + label, not a small circular FAB.
  Widget _buildAddButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
                onPressed: () => _addSchedule(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'New Schedule',
                      style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addSchedule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddScheduleScreen()),
    );
  }

  void _editSchedule(BuildContext context, ScheduledMessage schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddScheduleScreen(existing: schedule)),
    );
  }
}

/// ── Banner-style row matching HomeScreen's _SessionBanner: status dot,
/// message line, meta line, no card elevation, no trash icon (swipe to
/// delete is the only delete affordance, same as Home). Trailing icon is
/// a pause/play toggle instead of a delete button.
class _ScheduleBanner extends StatelessWidget {
  final ScheduledMessage schedule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ScheduleBanner({
    required this.schedule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = schedule.isActive && schedule.status == ScheduleStatus.pending;
    final Color accentColor;
    String status;
    switch (schedule.status) {
      case ScheduleStatus.pending:
        accentColor = isActive ? Colors.blueAccent : Colors.orangeAccent;
        status = isActive ? 'Active' : 'Paused';
        break;
      case ScheduleStatus.sent:
        accentColor = Colors.greenAccent;
        status = 'Sent';
        break;
      case ScheduleStatus.failed:
        accentColor = Colors.redAccent;
        status = 'Failed';
        break;
    }

    final meta = '$status · ${DateFormat('MMM dd, HH:mm').format(schedule.scheduledTime)} · '
        '${schedule.recipientIds.length} recipients'
        '${schedule.repetition != Repetition.none ? ' · ${schedule.repetition.name[0].toUpperCase()}${schedule.repetition.name.substring(1)}' : ''}';

    return Dismissible(
      key: ValueKey(schedule.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async => true,
      onDismissed: (_) => onDelete(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 2),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: 0.7), size: 20),
      ),
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
                      schedule.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (schedule.status == ScheduleStatus.pending) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onToggle,
                  child: Icon(
                    isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: isActive ? Colors.white.withValues(alpha: 0.4) : Colors.greenAccent.withValues(alpha: 0.8),
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
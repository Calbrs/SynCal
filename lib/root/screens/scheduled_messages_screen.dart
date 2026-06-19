import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/scheduled_message_store.dart';
import '../models/scheduled_message.dart';
import 'add_schedule_screen.dart';
import '../../services/background_service.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  State<ScheduledMessagesScreen> createState() => _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  @override
  void initState() {
    super.initState();
    // Process any due schedules as soon as the screen loads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundService.processNow();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color zinc950 = Color(0xFF09090B);
    const Color zinc900 = Color(0xFF18181B);
    const Color zinc800 = Color(0xFF27272A);
    const Color zinc700 = Color(0xFF3F3F46);
    const Color zinc500 = Color(0xFF71717A);
    const Color zinc400 = Color(0xFFA1A1AA);

    return Scaffold(
      backgroundColor: zinc950,
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                'Scheduled Messages',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                onPressed: () async {
                  await BackgroundService.processNow();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Checked for due schedules')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      body: Consumer<ScheduledMessageStore>(
        builder: (context, store, _) {
          if (!store.isLoaded) {
            return const Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2));
          }

          if (store.schedules.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded, color: zinc500, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    'No scheduled messages',
                    style: TextStyle(color: zinc400, fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to schedule your first message',
                    style: TextStyle(color: zinc500, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: store.schedules.length,
            itemBuilder: (context, index) {
              final schedule = store.schedules[index];
              return _ScheduleCard(
                schedule: schedule,
                onTap: () => _editSchedule(context, schedule),
                onToggle: () => store.toggleActive(schedule.id),
                onDelete: () => store.deleteSchedule(schedule.id),
              );
            },
          );
        },
      ),
      floatingActionButton: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
            ),
            child: FloatingActionButton(
              onPressed: () => _addSchedule(context),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              child: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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

// (_ScheduleCard unchanged, included for completeness)
class _ScheduleCard extends StatelessWidget {
  final ScheduledMessage schedule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ScheduleCard({
    super.key,
    required this.schedule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const Color zinc500 = Color(0xFF71717A);
    const Color zinc400 = Color(0xFFA1A1AA);

    final isActive = schedule.isActive && schedule.status == ScheduleStatus.pending;
    final Color color;
    String statusText;
    switch (schedule.status) {
      case ScheduleStatus.pending:
        color = isActive ? Colors.greenAccent : Colors.orangeAccent;
        statusText = isActive ? 'ACTIVE' : 'PAUSED';
        break;
      case ScheduleStatus.sent:
        color = Colors.blueAccent;
        statusText = 'SENT ✓';
        break;
      case ScheduleStatus.failed:
        color = Colors.redAccent;
        statusText = 'FAILED ✗';
        break;
    }

    return Dismissible(
      key: ValueKey(schedule.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async => true,
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    DateFormat('MMM dd, HH:mm').format(schedule.scheduledTime),
                    style: TextStyle(color: zinc400, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                schedule.message,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person_rounded, color: zinc500, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${schedule.recipientIds.length} recipients',
                    style: TextStyle(color: zinc500, fontSize: 13),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.sim_card_rounded, color: zinc500, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    schedule.simLabel,
                    style: TextStyle(color: zinc500, fontSize: 13),
                  ),
                  if (schedule.repetition != Repetition.none) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.repeat_rounded, color: zinc500, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      schedule.repetition.name.toUpperCase(),
                      style: TextStyle(color: zinc500, fontSize: 13),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (schedule.status == ScheduleStatus.pending)
                    IconButton(
                      onPressed: onToggle,
                      icon: Icon(
                        isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: isActive ? Colors.orangeAccent : Colors.greenAccent,
                        size: 22,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onTap,
                    child: Text(
                      'EDIT',
                      style: TextStyle(color: zinc400, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
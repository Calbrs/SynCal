import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/scheduled_message_store.dart';
import '../models/scheduled_message.dart';
import 'add_schedule_screen.dart';

class ScheduledMessagesScreen extends StatelessWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Scheduled Messages',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<ScheduledMessageStore>(
        builder: (context, store, _) {
          if (!store.isLoaded) {
            return const Center(child: CircularProgressIndicator(color: Colors.white30));
          }
          if (store.schedules.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded, color: Color(0xFF71717A), size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No scheduled messages',
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to schedule a message',
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 14),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: store.schedules.length,
            itemBuilder: (context, index) {
              final schedule = store.schedules[index];
              return _ScheduleCard(
                schedule: schedule,
                onTap: () => _editSchedule(context, schedule),
                onToggle: () => store.toggleActive(schedule.id),
                onDelete: () => _deleteSchedule(context, store, schedule.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addSchedule(context),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add_rounded),
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

  void _deleteSchedule(BuildContext context, ScheduledMessageStore store, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete schedule?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently remove the scheduled message.',
          style: TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF71717A))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              store.deleteSchedule(id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ScheduledMessage schedule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.schedule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = schedule.isActive;
    final color = isActive ? Colors.greenAccent : const Color(0xFF71717A);

    return Container(
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'ACTIVE' : 'PAUSED',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM dd, HH:mm').format(schedule.scheduledTime),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            schedule.message,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_rounded, color: const Color(0xFF71717A), size: 16),
              const SizedBox(width: 4),
              Text(
                '${schedule.recipientIds.length} recipients',
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
              const SizedBox(width: 16),
              Icon(Icons.sim_card_rounded, color: const Color(0xFF71717A), size: 16),
              const SizedBox(width: 4),
              Text(
                schedule.simLabel,
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
              const SizedBox(width: 16),
              if (schedule.repetition != Repetition.none) ...[
                Icon(Icons.repeat_rounded, color: const Color(0xFF71717A), size: 16),
                const SizedBox(width: 4),
                Text(
                  schedule.repetition.name,
                  style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: isActive ? Colors.orangeAccent : Colors.greenAccent,
                  size: 20,
                ),
                tooltip: isActive ? 'Pause' : 'Resume',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                tooltip: 'Delete',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              TextButton(
                onPressed: onTap,
                child: const Text(
                  'Edit',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
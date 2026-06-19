import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/contact.dart';
import '../models/scheduled_message.dart';
import '../../services/scheduled_message_store.dart';
import '../../services/sms_gateway_service.dart';

class AddScheduleScreen extends StatefulWidget {
  final ScheduledMessage? existing;
  const AddScheduleScreen({super.key, this.existing});

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  static const Color zinc950 = Color(0xFF09090B);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc700 = Color(0xFF3F3F46);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _messageController;
  late DateTime _scheduledTime;
  late Repetition _repetition;
  late int _simSlot;
  late String _simLabel;
  late List<String> _selectedContactKeys;
  List<SimCard> _simCards = [];
  bool _loadingSims = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _messageController = TextEditingController(text: existing?.message ?? '');
    _scheduledTime = existing?.scheduledTime ?? DateTime.now().add(const Duration(hours: 1));
    _repetition = existing?.repetition ?? Repetition.none;
    _simSlot = existing?.simSlot ?? -1;
    _simLabel = existing?.simLabel ?? 'Default SIM';
    _selectedContactKeys = existing?.recipientIds ?? [];
    _loadSimCards();
  }

  Future<void> _loadSimCards() async {
    final sims = await SmsGatewayService.getSimCards();
    if (mounted) {
      setState(() {
        _simCards = sims;
        _loadingSims = false;
        if (_simSlot == -1 && sims.isNotEmpty) {
          _simSlot = sims.first.slotIndex;
          _simLabel = sims.first.displayName;
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool get _isValid {
    return _messageController.text.trim().isNotEmpty &&
        _selectedContactKeys.isNotEmpty &&
        _simSlot != -1;
  }

  Future<void> _pickDateTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF18181B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF18181B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;

    if (mounted) {
      setState(() {
        _scheduledTime = DateTime(
          picked.year, picked.month, picked.day,
          time.hour, time.minute,
        );
      });
    }
  }

  void _selectContacts() {
    final box = Hive.box<Contact>('contacts');
    final allContacts = box.values.toList();
    final selected = List<String>.from(_selectedContactKeys);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  height: MediaQuery.of(ctx).size.height * 0.75,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: BoxDecoration(
                    color: zinc900,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: zinc700,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Text(
                        'Select Recipients',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose contacts to receive this message',
                        style: TextStyle(color: zinc400, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: allContacts.length,
                          itemBuilder: (_, idx) {
                            final contact = allContacts[idx];
                            final key = box.keyAt(idx);
                            final isChecked = selected.contains(key.toString());
                            // Wrap in Material to fix ListTile background color issue
                            return Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                title: Text(
                                  contact.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  contact.phones.isNotEmpty ? contact.phones.first : 'No number',
                                  style: TextStyle(color: zinc500, fontSize: 13),
                                ),
                                value: isChecked,
                                onChanged: (checked) {
                                  setModalState(() {
                                    final keyStr = key.toString();
                                    if (checked == true) {
                                      if (!selected.contains(keyStr)) selected.add(keyStr);
                                    } else {
                                      selected.remove(keyStr);
                                    }
                                  });
                                },
                                activeColor: Colors.white,
                                checkColor: Colors.black,
                                tileColor: Colors.transparent,
                                dense: true,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                backgroundColor: zinc800,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: zinc400, fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: zinc950,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (mounted) {
                                  setState(() {
                                    _selectedContactKeys = List.from(selected);
                                  });
                                }
                              },
                              child: const Text(
                                'Apply',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
      backgroundColor: zinc950,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Text(
              widget.existing == null ? 'Schedule Message' : 'Edit Schedule',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: TextStyle(color: zinc500, fontSize: 13),
                      filled: true,
                      fillColor: zinc800,
                      contentPadding: const EdgeInsets.all(16),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: zinc700, width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: zinc400, width: 0.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),

                  _buildTile(
                    icon: Icons.calendar_today_rounded,
                    title: 'Scheduled Time',
                    subtitle: DateFormat('MMM dd, yyyy HH:mm').format(_scheduledTime),
                    onTap: _pickDateTime,
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                  ),
                  const SizedBox(height: 8),

                  _buildTile(
                    icon: Icons.repeat_rounded,
                    title: 'Repetition',
                    subtitle: _repetition.name.toUpperCase(),
                    onTap: _showRepetitionPicker,
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                  ),
                  const SizedBox(height: 8),

                  _buildTile(
                    icon: Icons.sim_card_rounded,
                    title: 'SIM Card',
                    subtitle: _loadingSims ? 'Loading...' : _simLabel,
                    onTap: _loadingSims ? () {} : _showSimPicker,
                    trailing: _loadingSims
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
                          )
                        : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                  ),
                  const SizedBox(height: 8),

                  _buildTile(
                    icon: Icons.person_rounded,
                    title: 'Recipients',
                    subtitle: '${_selectedContactKeys.length} selected',
                    onTap: _selectContacts,
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: _isValid ? 0.12 : 0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: _isValid ? 0.15 : 0.06),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _isValid ? _save : null,
                        child: Text(
                          widget.existing == null ? 'Save Schedule' : 'Update Schedule',
                          style: TextStyle(
                            color: _isValid ? Colors.white : Colors.white.withValues(alpha: 0.3),
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
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Widget trailing,
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
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
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
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: zinc400, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  void _showRepetitionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: zinc900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: Repetition.values.map((rep) {
              return ListTile(
                title: Text(
                  rep.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _repetition == rep
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _repetition = rep);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showSimPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: zinc900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _simCards.map((sim) {
              return ListTile(
                title: Text(
                  '${sim.displayName} — ${sim.carrierName}',
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _simSlot == sim.slotIndex
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {
                      _simSlot = sim.slotIndex;
                      _simLabel = sim.displayName;
                    });
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _save() {
    if (!_isValid) return;

    final store = context.read<ScheduledMessageStore>();
    final id = widget.existing?.id ?? const Uuid().v4();

    final schedule = ScheduledMessage(
      id: id,
      message: _messageController.text.trim(),
      scheduledTime: _scheduledTime,
      repetition: _repetition,
      recipientIds: _selectedContactKeys,
      simSlot: _simSlot,
      simLabel: _simLabel,
      isActive: true,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      sentCount: widget.existing?.sentCount,
    );

    if (widget.existing == null) {
      store.addSchedule(schedule);
    } else {
      store.updateSchedule(schedule);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
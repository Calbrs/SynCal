import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/contact.dart';
import '../models/scheduled_message.dart';
import '../../services/scheduled_message_store.dart';
import '../../services/sms_gateway_service.dart';
import 'custom_date_time_picker.dart';

/// ── Shared palette, identical to HomeScreen's _Palette so every screen
/// reads as one continuous surface.
class _Palette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color surface = Color(0xFF18181B);
  static const Color hairline = Color(0xFF3F3F46);
  static const Color muted = Color(0xFF71717A);
  static const Color mutedLight = Color(0xFFA1A1AA);
}

class AddScheduleScreen extends StatefulWidget {
  final ScheduledMessage? existing;
  const AddScheduleScreen({super.key, this.existing});

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
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
    final result = await showCustomDateTimePicker(
      context: context,
      initialDateTime: _scheduledTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (result == null) return;
    if (!mounted) return;

    setState(() => _scheduledTime = result);
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
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  height: MediaQuery.of(ctx).size.height * 0.75,
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                  decoration: BoxDecoration(
                    color: _Palette.surface.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: _Palette.hairline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Text(
                        'Select Recipients',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose contacts to receive this message',
                        style: TextStyle(color: _Palette.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: ListView.builder(
                          itemCount: allContacts.length,
                          itemBuilder: (_, idx) {
                            final contact = allContacts[idx];
                            final key = box.keyAt(idx);
                            final isChecked = selected.contains(key.toString());
                            return Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                title: Text(
                                  contact.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  contact.phones.isNotEmpty ? contact.phones.first : 'No number',
                                  style: TextStyle(color: _Palette.muted, fontSize: 12.5),
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
                                controlAffinity: ListTileControlAffinity.trailing,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _GlassPillButton(
                              label: 'Cancel',
                              filled: false,
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GlassPillButton(
                              label: 'Apply',
                              filled: true,
                              icon: Icons.check_rounded,
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (mounted) {
                                  setState(() {
                                    _selectedContactKeys = List.from(selected);
                                  });
                                }
                              },
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Palette.bg,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Form(
            key: _formKey,
            child: Stack(
              children: [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                      sliver: SliverList.list(
                        children: [
                          _buildMessageField(),
                          const SizedBox(height: 20),
                          _buildTile(
                            icon: Icons.calendar_today_rounded,
                            title: 'Scheduled Time',
                            subtitle: DateFormat('MMM dd, yyyy HH:mm').format(_scheduledTime),
                            onTap: _pickDateTime,
                          ),
                          const SizedBox(height: 10),
                          _buildTile(
                            icon: Icons.repeat_rounded,
                            title: 'Repetition',
                            subtitle: _repetitionLabel(_repetition),
                            onTap: _showRepetitionPicker,
                          ),
                          const SizedBox(height: 10),
                          _buildTile(
                            icon: Icons.sim_card_rounded,
                            title: 'SIM Card',
                            subtitle: _loadingSims ? 'Loading…' : _simLabel,
                            onTap: _loadingSims ? null : _showSimPicker,
                            loading: _loadingSims,
                          ),
                          const SizedBox(height: 10),
                          _buildTile(
                            icon: Icons.person_rounded,
                            title: 'Recipients',
                            subtitle: _selectedContactKeys.isEmpty
                                ? 'None selected'
                                : '${_selectedContactKeys.length} selected',
                            onTap: _selectContacts,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: _buildSaveButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header matches HomeScreen: big title left, glass back button right.
  Widget _buildHeader() {
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
                Text(
                  widget.existing == null ? 'Schedule' : 'Edit Schedule',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.existing == null ? 'Set up a message to send later' : 'Update the details below',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _Palette.muted, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: TextField(
        controller: _messageController,
        maxLines: 4,
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
        cursorColor: Colors.white,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Type your message…',
          hintStyle: TextStyle(color: _Palette.muted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  // ── Tile styled like HomeScreen's glassy surfaces: soft translucent
  // fill, hairline border, circular icon chip.
  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
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
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: _Palette.mutedLight, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
              )
            else
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.25), size: 13),
          ],
        ),
      ),
    );
  }

  // ── Bottom action, same glass pill treatment as HomeScreen's Send button.
  Widget _buildSaveButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isValid ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: _isValid ? 0.1 : 0.06),
              width: 0.5,
            ),
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
              onPressed: _isValid ? _save : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_send_rounded,
                    color: _isValid ? Colors.white : Colors.white30,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.existing == null ? 'Save Schedule' : 'Update Schedule',
                    style: TextStyle(
                      color: _isValid ? Colors.white : Colors.white.withValues(alpha: 0.3),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
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

  String _repetitionLabel(Repetition rep) {
    switch (rep) {
      case Repetition.none:
        return 'One-time';
      default:
        return rep.name[0].toUpperCase() + rep.name.substring(1);
    }
  }

  void _showRepetitionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _GlassSheet(
          title: 'Repetition',
          children: Repetition.values.map((rep) {
            final selected = _repetition == rep;
            return _SheetOptionTile(
              label: _repetitionLabel(rep),
              selected: selected,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _repetition = rep);
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _showSimPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _GlassSheet(
          title: 'SIM Card',
          children: _simCards.map((sim) {
            final selected = _simSlot == sim.slotIndex;
            return _SheetOptionTile(
              label: '${sim.displayName} — ${sim.carrierName}',
              selected: selected,
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

/// ── Reusable glassy bottom sheet shell used by pickers, matching
/// HomeScreen's compose-sheet look.
class _GlassSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _GlassSheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
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
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: _Palette.hairline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
                ),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SheetOptionTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : _Palette.mutedLight,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

/// ── Glass pill button used inside the recipients sheet (Cancel / Apply),
/// same family as HomeScreen's glass buttons.
class _GlassPillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final IconData? icon;
  final VoidCallback onPressed;
  const _GlassPillButton({required this.label, required this.filled, this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: filled ? 0.12 : 0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 0.15 : 0.08), width: 0.5),
          ),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: onPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: filled ? Colors.white : _Palette.mutedLight,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
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
}
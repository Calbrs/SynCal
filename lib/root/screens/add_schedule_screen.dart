import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';
import '../models/scheduled_message.dart';
import '../../services/scheduled_message_store.dart';
import '../../services/sms_gateway_service.dart';
import 'package:uuid/uuid.dart';

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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF18181B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Select Recipients', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: allContacts.length,
                itemBuilder: (_, idx) {
                  final contact = allContacts[idx];
                  // Get the key from the Hive box
                  final key = box.keyAt(idx);
                  final isChecked = selected.contains(key.toString());
                  return CheckboxListTile(
                    title: Text(
                      contact.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      contact.phones.isNotEmpty ? contact.phones.first : 'No number',
                      style: const TextStyle(color: Color(0xFF71717A)),
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
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF71717A))),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {
                      _selectedContactKeys = selected;
                    });
                  }
                },
                child: const Text('Apply', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.existing == null ? 'Schedule Message' : 'Edit Schedule',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Message
              TextFormField(
                controller: _messageController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Message',
                  labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  filled: true,
                  fillColor: const Color(0xFF18181B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => v?.trim().isEmpty == true ? 'Message is required' : null,
              ),
              const SizedBox(height: 16),

              // Date/Time
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scheduled Time', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  DateFormat('MMM dd, yyyy HH:mm').format(_scheduledTime),
                  style: const TextStyle(color: Color(0xFF71717A)),
                ),
                trailing: const Icon(Icons.calendar_today_rounded, color: Colors.white),
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 16),

              // Repetition
              DropdownButtonFormField<Repetition>(
                initialValue: _repetition,
                dropdownColor: const Color(0xFF18181B),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Repetition',
                  labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  filled: true,
                  fillColor: const Color(0xFF18181B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: Repetition.values.map((e) {
                  return DropdownMenuItem(
                    value: e,
                    child: Text(e.name.toUpperCase(), style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _repetition = val);
                  }
                },
              ),
              const SizedBox(height: 16),

              // SIM selection
              if (_loadingSims)
                const CircularProgressIndicator()
              else
                DropdownButtonFormField<int>(
                  initialValue: _simSlot,
                  dropdownColor: const Color(0xFF18181B),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'SIM Card',
                    labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                    filled: true,
                    fillColor: const Color(0xFF18181B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _simCards.map((sim) {
                    return DropdownMenuItem(
                      value: sim.slotIndex,
                      child: Text('${sim.displayName} — ${sim.carrierName}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final sim = _simCards.firstWhere((s) => s.slotIndex == val);
                      setState(() {
                        _simSlot = sim.slotIndex;
                        _simLabel = sim.displayName;
                      });
                    }
                  },
                ),
              const SizedBox(height: 16),

              // Recipients selection
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Recipients', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${_selectedContactKeys.length} selected',
                  style: const TextStyle(color: Color(0xFF71717A)),
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70),
                onTap: _selectContacts,
              ),
              if (_selectedContactKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Please select at least one contact',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedContactKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient')),
      );
      return;
    }

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
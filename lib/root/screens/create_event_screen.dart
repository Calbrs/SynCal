// lib/screens/create_event_screen.dart
// Updated to match the UI style of HomeScreen

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import '../models/contact.dart';
import '/core/api_client.dart';

// ─── Shimmer loading widget (same as HomeScreen) ──────────────
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

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> with SingleTickerProviderStateMixin {
  // ─── Zinc color palette ──────────────────────────────────────
  static const Color zinc950 = Color(0xFF09090B);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc700 = Color(0xFF3F3F46);
  static const Color zinc600 = Color(0xFF52525B);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);
  static const Color zinc300 = Color(0xFFD4D4D8);

  final _searchController = TextEditingController();
  final _contactBox = Hive.box<Contact>('contacts');
  List<Contact> contacts = [];
  bool _menuOpen = false;
  DateTime? _lastSync;
  OverlayEntry? _overlayEntry;
  final _menuButtonKey = GlobalKey();
  late AnimationController _menuAnimController;
  late Animation<double> _menuFadeAnim;
  late Animation<Offset> _menuSlideAnim;

  Timer? _autoSyncTimer;
  static const Duration _syncInterval = Duration(seconds: 30);

  // ── Sync enabled flag ────────────────────────────────────────
  bool _syncEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _lastSync = ApiClient.instance.lastSync;
    _loadSyncEnabled();

    _menuAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _menuFadeAnim = CurvedAnimation(parent: _menuAnimController, curve: Curves.easeOut);
    _menuSlideAnim = Tween<Offset>(
            begin: const Offset(0, -0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _menuAnimController, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_syncEnabled && ApiClient.instance.linkedUser != null) {
        _autoSync();
        _startPeriodicSync();
      }
    });
  }

  Future<void> _loadSyncEnabled() async {
    final settingsBox = Hive.box('settings');
    final enabled = settingsBox.get('syncEnabled', defaultValue: false) as bool;
    setState(() => _syncEnabled = enabled);
  }

  Future<void> _saveSyncEnabled(bool value) async {
    final settingsBox = Hive.box('settings');
    await settingsBox.put('syncEnabled', value);
    setState(() => _syncEnabled = value);
  }

  @override
  void dispose() {
    _stopPeriodicSync();
    _removeOverlay();
    _menuAnimController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Periodic sync ──────────────────────────────────────────────

  void _startPeriodicSync() {
    if (_autoSyncTimer != null || !_syncEnabled) return;
    _autoSyncTimer = Timer.periodic(_syncInterval, (timer) {
      if (ApiClient.instance.linkedUser != null && mounted && _syncEnabled) {
        _performSync(silent: true);
      }
    });
  }

  void _stopPeriodicSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ── Sync ──────────────────────────────────────────────────────

  Future<void> _autoSync() async {
    if (ApiClient.instance.linkedUser == null || !_syncEnabled) return;
    final last = ApiClient.instance.lastSync;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return;
    try {
      await _performSync(silent: true);
    } catch (_) {}
  }

  Future<void> _performSync({bool silent = false}) async {
    if (!mounted || ApiClient.instance.linkedUser == null || !_syncEnabled) return;
    try {
      final synced = await ApiClient.instance.syncContacts();
      _mergeContacts(synced);
      setState(() {
        _lastSync = ApiClient.instance.lastSync;
      });
    } catch (e) {
      if (!silent && mounted) _showSnack(e.toString(), color: Colors.redAccent);
    }
  }

  void _mergeContacts(List<SyncedContact> synced) {
    for (final sc in synced) {
      if (sc.phones.isEmpty) continue;
      final exists = _contactBox.values.any((c) =>
          c.name.toLowerCase() == sc.name.toLowerCase() &&
          c.phones.isNotEmpty && c.phones[0] == sc.phones[0]);
      if (!exists) {
        _contactBox.add(Contact(
            name: sc.name,
            phones: sc.phones.take(2).toList(),
            createdAt: DateTime.now()));
      }
    }
    _loadContacts();
  }

  // ── Overlay menu ──────────────────────────────────────────────

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleMenu() => _menuOpen ? _closeMenu() : _openMenu();

  void _openMenu() {
    setState(() => _menuOpen = true);
    final box = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final isLinked = ApiClient.instance.linkedUser != null;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: pos.dy + box.size.height + 6,
            right: MediaQuery.of(context).size.width - pos.dx - box.size.width,
            child: FadeTransition(
              opacity: _menuFadeAnim,
              child: SlideTransition(
                position: _menuSlideAnim,
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 260,
                        decoration: BoxDecoration(
                          color: zinc900,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMenuItem(
                              icon: Icons.person_add_outlined,
                              label: 'Add new contact',
                              onTap: () {
                                _closeMenu();
                                Future.delayed(const Duration(milliseconds: 220), _showAddContactModal);
                              },
                              showDivider: true,
                            ),
                            _buildMenuItem(
                              icon: Icons.contacts_outlined,
                              label: 'Select from phone',
                              onTap: () {
                                _closeMenu();
                                Future.delayed(const Duration(milliseconds: 220), _showContactPickerDrawer);
                              },
                              showDivider: true,
                            ),
                            _buildSyncToggleItem(isLinked),
                          ],
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
    );
    Overlay.of(context).insert(_overlayEntry!);
    _menuAnimController.forward();
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.white.withValues(alpha: 0.08),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }

  Widget _buildSyncToggleItem(bool isLinked) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            _syncEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
            color: _syncEnabled ? Colors.greenAccent : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _syncEnabled ? 'Online Sync' : 'Sync Off',
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                if (_lastSync != null && _syncEnabled)
                  Text(
                    'Last sync: ${_formatRelative(_lastSync!)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5),
                  ),
                if (!isLinked)
                  Text(
                    'Link account first',
                    style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.7), fontSize: 11),
                  ),
              ],
            ),
          ),
          Switch(
            value: _syncEnabled && isLinked,
            onChanged: (value) => _toggleSync(value, isLinked),
            activeColor: Colors.greenAccent,
            inactiveThumbColor: Colors.grey,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSync(bool value, bool isLinked) async {
    if (!isLinked) {
      _showSnack('Please link your account first', color: Colors.orangeAccent);
      _closeMenu();
      return;
    }

    if (value && !_syncEnabled) {
      final password = await _showPasswordDialog();
      if (password == null) return;
      try {
        final user = ApiClient.instance.linkedUser!;
        await ApiClient.instance.login(user.username, password);
        await _saveSyncEnabled(true);
        _startPeriodicSync();
        _performSync(silent: false);
        _closeMenu();
        if (mounted) _showSnack('Sync enabled', color: Colors.greenAccent);
      } catch (e) {
        _showSnack(e.toString(), color: Colors.redAccent);
      }
    } else if (!value && _syncEnabled) {
      await _saveSyncEnabled(false);
      _stopPeriodicSync();
      _closeMenu();
      if (mounted) _showSnack('Sync disabled', color: Colors.orangeAccent);
    }
  }

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    bool obscure = true;
    final completer = Completer<String?>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: zinc900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Re-enter password',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                ),
                onPressed: () => setState(() => obscure = !obscure),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.greenAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                completer.complete(null);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final pw = controller.text.trim();
                if (pw.isNotEmpty) {
                  Navigator.pop(ctx);
                  completer.complete(pw);
                }
              },
              child: const Text('Confirm', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        ),
      ),
    );

    return completer.future;
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    _menuAnimController.reverse().then((_) {
      _removeOverlay();
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  // ── Contacts ──────────────────────────────────────────────────

  void _loadContacts() => setState(() {
        contacts = _contactBox.values.toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      });

  void _search(String value) {
    if (value.isEmpty) {
      _loadContacts();
      return;
    }
    final q = value.toLowerCase();
    setState(() {
      contacts = _contactBox.values
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.phones.any((p) => p.toLowerCase().contains(q)))
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    });
  }

  String? _checkDuplicate(String name, String phone, {Contact? excludeContact}) {
    for (final c in _contactBox.values) {
      if (c == excludeContact) continue;
      if (c.name.toLowerCase() == name.toLowerCase()) {
        if (c.phones.contains(phone)) return 'This phone number already exists.';
        if (c.phones.length >= 2) return 'This contact already has maximum 2 numbers.';
      }
    }
    return null;
  }

  // ── Menu actions ──────────────────────────────────────────────

  void _onAddNewContact() {
    _closeMenu();
    Future.delayed(const Duration(milliseconds: 220), _showAddContactModal);
  }

  void _onSelectFromPhone() {
    _closeMenu();
    Future.delayed(const Duration(milliseconds: 220), _showContactPickerDrawer);
  }

  // ── Contact picker ────────────────────────────────────────────

  void _showContactPickerDrawer() async {
    if (!await fc.FlutterContacts.requestPermission(readonly: true)) {
      if (!mounted) return;
      _showSnack('Contacts permission denied', color: Colors.redAccent);
      return;
    }
    List<fc.Contact> deviceContacts = [];
    try {
      deviceContacts = await fc.FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      deviceContacts = deviceContacts.where((c) => c.phones.isNotEmpty).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to load contacts', color: Colors.redAccent);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContactPickerSheet(
        deviceContacts: deviceContacts,
        onSave: (selected) {
          for (final dc in selected) {
            final name = dc.displayName;
            final phones = dc.phones
                .map((p) => p.number.replaceAll(RegExp(r'\s+'), ''))
                .take(2)
                .toList();
            if (name.isEmpty || phones.isEmpty) continue;
            if (_contactBox.values.any((c) =>
                c.name.toLowerCase() == name.toLowerCase() &&
                c.phones.isNotEmpty &&
                c.phones[0] == phones[0])) {
              continue;
            }
            _contactBox.add(Contact(name: name, phones: phones, createdAt: DateTime.now()));
          }
          _loadContacts();
        },
      ),
    );
  }

  // ── Contact modals ────────────────────────────────────────────

  void _showAddContactModal() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(
          Column(
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
                'Add New Contact',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter contact details',
                style: TextStyle(color: zinc400, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Phone Number'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _pillButton(
                      'Cancel',
                      zinc800,
                      zinc400,
                      () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pillButton(
                      'Save',
                      Colors.white,
                      zinc950,
                      () {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty) return;
                        final msg = _checkDuplicate(name, phone);
                        if (msg != null) {
                          _showSnack(msg, color: Colors.redAccent);
                          return;
                        }
                        _contactBox.add(Contact(name: name, phones: [phone], createdAt: DateTime.now()));
                        _loadContacts();
                        Navigator.pop(context);
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
  }

  void _showAddPhoneModal(Contact contact) {
    if (contact.phones.length >= 2) return;
    final phoneCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(
          Column(
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
              Text(
                'Add Phone for ${contact.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: phoneCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('New Phone Number'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _pillButton(
                      'Cancel',
                      zinc800,
                      zinc400,
                      () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pillButton(
                      'Add',
                      Colors.white,
                      zinc950,
                      () {
                        final p = phoneCtrl.text.trim();
                        if (p.isEmpty) return;
                        final msg = _checkDuplicate(contact.name, p, excludeContact: contact);
                        if (msg != null) {
                          _showSnack(msg, color: Colors.redAccent);
                          return;
                        }
                        final phones = List<String>.from(contact.phones)..add(p);
                        _updateContact(contact, Contact(name: contact.name, phones: phones, createdAt: contact.createdAt));
                        Navigator.pop(context);
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
  }

  void _showEditContactModal(Contact old) {
    final nameCtrl = TextEditingController(text: old.name);
    final p1Ctrl = TextEditingController(text: old.phones.isNotEmpty ? old.phones[0] : '');
    final p2Ctrl = TextEditingController(text: old.phones.length > 1 ? old.phones[1] : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(
          Column(
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
                'Edit Contact',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Name'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: p1Ctrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration('Phone Number 1'),
                    ),
                  ),
                  if (old.phones.length > 1) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                      onPressed: () => _showRemoveNumberConfirmation(old, 0, context),
                    ),
                  ],
                ],
              ),
              if (old.phones.length > 1) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: p2Ctrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration('Phone Number 2'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                      onPressed: () => _showRemoveNumberConfirmation(old, 1, context),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _pillButton(
                      'Cancel',
                      zinc800,
                      zinc400,
                      () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pillButton(
                      'Save',
                      Colors.white,
                      zinc950,
                      () {
                        final name = nameCtrl.text.trim();
                        final p1 = p1Ctrl.text.trim();
                        final p2 = p2Ctrl.text.trim();
                        if (name.isEmpty || p1.isEmpty) return;
                        final msg = _checkDuplicate(name, p1, excludeContact: old);
                        if (msg != null) {
                          _showSnack(msg, color: Colors.redAccent);
                          return;
                        }
                        final phones = [p1, if (p2.isNotEmpty && old.phones.length > 1) p2];
                        _updateContact(old, Contact(name: name, phones: phones, createdAt: old.createdAt));
                        Navigator.pop(context);
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
  }

  void _showRemoveNumberConfirmation(Contact contact, int idx, BuildContext modalCtx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: zinc900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Number?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${contact.phones[idx]}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final phones = List<String>.from(contact.phones)..removeAt(idx);
              if (phones.isEmpty) {
                _showSnack('Contact must have at least one phone number', color: Colors.redAccent);
                Navigator.pop(context);
                return;
              }
              _updateContact(contact, Contact(name: contact.name, phones: phones, createdAt: contact.createdAt));
              Navigator.pop(context);
              Navigator.pop(modalCtx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showSecondNumber(Contact contact) {
    if (contact.phones.length < 2) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: zinc900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Additional Number', style: TextStyle(color: Colors.white)),
        content: Text(
          contact.phones[1],
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu(Contact contact) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: zinc900,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contact.phones.length < 2)
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                  title: const Text('Add another number', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddPhoneModal(contact);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                title: const Text('Edit contact', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showEditContactModal(contact);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete contact', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(contact);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Contact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: zinc900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Contact?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${contact.name}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final idx = _contactBox.values.toList().indexOf(contact);
              if (idx != -1) _contactBox.deleteAt(idx);
              _loadContacts();
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  void _updateContact(Contact old, Contact updated) {
    final idx = _contactBox.values.toList().indexOf(old);
    if (idx != -1) _contactBox.putAt(idx, updated);
    _loadContacts();
  }

  Widget _glassSheet(Widget child) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          decoration: BoxDecoration(
            color: zinc900,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: zinc400),
      filled: true,
      fillColor: zinc800,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: zinc700),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: zinc700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white54),
      ),
    );
  }

  Widget _pillButton(String text, Color bg, Color fg, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showSnack(String msg, {Color color = const Color(0xFF3A3A3E)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color == const Color(0xFF3A3A3E) ? color : color.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatRelative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: _closeMenu,
        child: Scaffold(
          backgroundColor: zinc950,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      onChanged: _search,
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(color: zinc500, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded, color: zinc400, size: 22),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_syncEnabled && ApiClient.instance.linkedUser != null)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  key: _menuButtonKey,
                  onTap: _toggleMenu,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _menuOpen ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ],
            ),
          ),
          body: contacts.isEmpty
              ? Center(
                  child: Text(
                    'No contacts yet.\nTap ⋮ to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: zinc500, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: contacts.length,
                  itemBuilder: (context, i) {
                    final c = contacts[i];
                    return _ContactCard(
                      contact: c,
                      onTap: () => _showOptionsMenu(c),
                      onPhoneTap: c.phones.length > 1 ? () => _showSecondNumber(c) : null,
                      onDelete: () => _showDeleteConfirmation(c),
                    );
                  },
                ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${contacts.length} contact${contacts.length != 1 ? 's' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: zinc500, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Contact card widget (styled like session cards) ──────────

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.onTap,
    this.onPhoneTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(contact.hashCode),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
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
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    child: Text(
                      contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (contact.phones.length > 1)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        onTap: onPhoneTap,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF1C1C1E), width: 2),
                          ),
                          child: const Text(
                            '+1',
                            style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (contact.phones.isNotEmpty)
                      Text(
                        contact.phones[0],
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                      ),
                  ],
                ),
              ),
              Text(
                DateFormat('MMM dd').format(contact.createdAt),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12.5),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 24),
                onPressed: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Contact picker sheet (restyled) ───────────────────────────

class _ContactPickerSheet extends StatefulWidget {
  final List<fc.Contact> deviceContacts;
  final void Function(List<fc.Contact>) onSave;

  const _ContactPickerSheet({required this.deviceContacts, required this.onSave});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _selected = <String>{};
  final _searchCtrl = TextEditingController();
  late List<fc.Contact> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.deviceContacts;
  }

  void _onSearch(String q) => setState(() {
        _filtered = q.isEmpty
            ? widget.deviceContacts
            : widget.deviceContacts.where((c) =>
                c.displayName.toLowerCase().contains(q.toLowerCase()) ||
                c.phones.any((p) => p.number.contains(q))).toList();
      });

  void _toggle(String id) => setState(() =>
      _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _save() {
    final sel = widget.deviceContacts.where((c) => _selected.contains(c.id)).toList();
    Navigator.pop(context);
    widget.onSave(sel);
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    const Color zinc900 = Color(0xFF18181B);
    const Color zinc800 = Color(0xFF27272A);
    const Color zinc700 = Color(0xFF3F3F46);
    const Color zinc500 = Color(0xFF71717A);
    const Color zinc400 = Color(0xFFA1A1AA);

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: BoxDecoration(
        color: zinc900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: zinc700, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Contacts',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 0.5),
                    ),
                    child: Text(
                      '$count selected',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: zinc500, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: zinc400, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No contacts found',
                      style: TextStyle(color: zinc500, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final dc = _filtered[i];
                      final sel = _selected.contains(dc.id);
                      return InkWell(
                        onTap: () => _toggle(dc.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: sel
                                    ? Colors.greenAccent.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.06),
                                child: Text(
                                  dc.displayName.isNotEmpty ? dc.displayName[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    color: sel ? Colors.greenAccent : Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dc.displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
                                    ),
                                    if (dc.phones.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        dc.phones[0].number,
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13.5),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: sel ? Colors.greenAccent : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: sel ? Colors.greenAccent : Colors.white38,
                                    width: 1.5,
                                  ),
                                ),
                                child: sel ? const Icon(Icons.check, color: Colors.black, size: 15) : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: count > 0 ? Colors.greenAccent : Colors.white.withValues(alpha: 0.15),
                        foregroundColor: count > 0 ? Colors.black : Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 0,
                      ),
                      onPressed: count > 0 ? _save : null,
                      child: Text(
                        count > 0 ? 'Add $count contact${count != 1 ? 's' : ''}' : 'Add',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
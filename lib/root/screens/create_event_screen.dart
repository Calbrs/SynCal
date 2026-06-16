// lib/screens/create_event_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import '../models/contact.dart';
import '/core/api_client.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _lastSync = ApiClient.instance.lastSync;
    _menuAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _menuFadeAnim =
        CurvedAnimation(parent: _menuAnimController, curve: Curves.easeOut);
    _menuSlideAnim = Tween<Offset>(
            begin: const Offset(0, -0.1), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _menuAnimController, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoSync();
      _startPeriodicSync();
    });
  }

  @override
  void dispose() {
    _stopPeriodicSync();
    _removeOverlay();
    _menuAnimController.dispose();
    super.dispose();
  }

  // ── Periodic sync ──────────────────────────────────────────────

  void _startPeriodicSync() {
    if (_autoSyncTimer != null) return;
    _autoSyncTimer = Timer.periodic(_syncInterval, (timer) {
      if (ApiClient.instance.linkedUser != null && mounted) {
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
    if (ApiClient.instance.linkedUser == null) return;
    final last = ApiClient.instance.lastSync;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return;
    try { await _performSync(silent: true); } catch (_) {}
  }

  Future<void> _performSync({bool silent = false}) async {
    if (!mounted || ApiClient.instance.linkedUser == null) return;
    try {
      final synced = await ApiClient.instance.syncContacts();
      _mergeContacts(synced);
      setState(() { _lastSync = ApiClient.instance.lastSync; });
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

  // ── Overlay ───────────────────────────────────────────────────

  void _removeOverlay() { _overlayEntry?.remove(); _overlayEntry = null; }
  void _toggleMenu() => _menuOpen ? _closeMenu() : _openMenu();

void _openMenu() {
    setState(() => _menuOpen = true);
    final box = _menuButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final isLinked = ApiClient.instance.linkedUser != null;

    _overlayEntry = OverlayEntry(builder: (context) => Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: _closeMenu,
          behavior: HitTestBehavior.translucent, child: const SizedBox.expand())),
      Positioned(
        top: pos.dy + box.size.height + 6,
        right: MediaQuery.of(context).size.width - pos.dx - box.size.width,
        child: FadeTransition(opacity: _menuFadeAnim,
          child: SlideTransition(position: _menuSlideAnim,
            child: Material(color: Colors.transparent,
              child: ClipRRect(borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C30),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))]),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _DropdownItem(icon: Icons.person_add_outlined, iconColor: Colors.white,
                          label: 'Add new contact', onTap: _onAddNewContact, showDivider: true),
                      _DropdownItem(icon: Icons.contacts_outlined, iconColor: Colors.greenAccent,
                          label: 'Select from phone', onTap: _onSelectFromPhone, showDivider: true),
                      _DropdownItem(
                          icon: isLinked ? Icons.link_off_rounded : Icons.link_rounded,
                          iconColor: isLinked ? Colors.greenAccent : Colors.blueAccent,
                          label: isLinked
                              ? 'Linked · ${ApiClient.instance.linkedUser!.username}'
                              : 'Link with SynCal ID',
                          subtitle: isLinked && _lastSync != null
                              ? 'Last sync ${_formatRelative(_lastSync!)}'
                              : null,
                          onTap: isLinked ? _onUnlinkConfirm : _onLinkWithSyscal,
                          showDivider: false),
                    ]),
                  ))))))),
    ]));
    Overlay.of(context).insert(_overlayEntry!);
    _menuAnimController.forward();
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
    if (value.isEmpty) { _loadContacts(); return; }
    final q = value.toLowerCase();
    setState(() {
      contacts = _contactBox.values.where((c) =>
          c.name.toLowerCase().contains(q) ||
          c.phones.any((p) => p.toLowerCase().contains(q))).toList()
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

  void _onLinkWithSyscal() {
    _closeMenu();
    Future.delayed(const Duration(milliseconds: 220), _showSyncalIdModal);
  }

  void _onUnlinkConfirm() {
    _closeMenu();
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Unlink SynCal Account?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'You\'ll be disconnected from ${ApiClient.instance.linkedUser?.username ?? 'your account'}. '
            'Your saved contacts won\'t be removed.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () async {
            await ApiClient.instance.unlink();
            if (!mounted) return;
            _stopPeriodicSync();
            Navigator.pop(ctx);
            setState(() => _lastSync = null);
            _showSnack('Account unlinked');
          }, child: const Text('Unlink', style: TextStyle(color: Colors.redAccent))),
        ],
      ));
    });
  }

  // ── Two-step SynCal link (username‑based) ─────────────────────

  void _showSyncalIdModal() {
    final idCtrl = TextEditingController();
    bool loading = false;
    String? error;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => _bottomSheet(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetHandle(),
          Row(children: [
            _iconBox(Icons.link_rounded, Colors.blueAccent),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Link SynCal Account',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Enter your SynCal ID to continue',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
            ]),
          ]),
          const SizedBox(height: 28),
          TextField(
            controller: idCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 0.5),
            textCapitalization: TextCapitalization.characters,
            decoration: _fieldDecoration('SynCal ID', hint: 'e.g. SYNC-CR-9326',
                prefix: Icons.fingerprint_rounded, accentColor: Colors.blueAccent, error: error),
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Search', loading: loading, color: Colors.blueAccent, textColor: Colors.white,
            onPressed: () async {
              final id = idCtrl.text.trim();
              if (id.isEmpty) { set(() => error = 'Enter your SynCal ID'); return; }
              set(() { loading = true; error = null; });
              try {
                final username = await ApiClient.instance.lookupSyncalId(id);
                if (!mounted) return;
                Navigator.pop(ctx);
                await Future.delayed(const Duration(milliseconds: 300));
                if (mounted) {
                  _showPasswordModal(id, username);
                }
              } on ApiException catch (e) {
                if (mounted) {
                  set(() { loading = false; error = e.message; });
                }
              } catch (_) {
                if (mounted) {
                  set(() { loading = false; error = 'Connection failed. Try again.'; });
                }
              }
            },
          ),
        ]),
      )),
    );
  }

  void _showPasswordModal(String syncalId, String username) {
    final pwCtrl = TextEditingController();
    bool loading = false, obscure = true;
    String? error;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => _bottomSheet(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetHandle(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25), width: 0.5)),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Center(child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 3),
                Text(syncalId, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5, letterSpacing: 0.4)),
              ])),
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
            ]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: pwCtrl,
            style: const TextStyle(color: Colors.white),
            obscureText: obscure,
            decoration: _fieldDecoration('Password',
                prefix: Icons.lock_outline_rounded,
                accentColor: Colors.greenAccent,
                error: error,
                suffix: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: Colors.white38, size: 20),
                  onPressed: () => set(() => obscure = !obscure),
                )),
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: 'Link Account', loading: loading,
            color: Colors.greenAccent, textColor: Colors.black,
            onPressed: () async {
              final pw = pwCtrl.text.trim();
              if (pw.isEmpty) { set(() => error = 'Enter your password'); return; }
              set(() { loading = true; error = null; });
              try {
                await ApiClient.instance.authenticateWithUsername(username, pw);
                if (!mounted) return;
                Navigator.pop(ctx);
                if (mounted) {
                  setState(() => _lastSync = ApiClient.instance.lastSync);
                  _showSnack('Linked to $username successfully', color: Colors.greenAccent);
                  _performSync(silent: true); // sync silently after linking
                  _startPeriodicSync();
                }
              } on ApiException catch (e) {
                if (mounted) {
                  set(() { loading = false; error = e.message; });
                }
              } catch (_) {
                if (mounted) {
                  set(() { loading = false; error = 'Connection failed. Try again.'; });
                }
              }
            },
          ),
        ]),
      )),
    );
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => _ContactPickerSheet(
        deviceContacts: deviceContacts,
        onSave: (selected) {
          for (final dc in selected) {
            final name = dc.displayName;
            final phones = dc.phones
                .map((p) => p.number.replaceAll(RegExp(r'\s+'), '')).take(2).toList();
            if (name.isEmpty || phones.isEmpty) continue;
            if (_contactBox.values.any((c) =>
                c.name.toLowerCase() == name.toLowerCase() &&
                c.phones.isNotEmpty && c.phones[0] == phones[0])) {
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add New Contact',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Name')),
          const SizedBox(height: 16),
          TextField(controller: phoneCtrl, style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone, decoration: _inputDecoration('Phone Number')),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _pillButton('Cancel', Colors.white.withValues(alpha: 0.1), Colors.white, () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: _pillButton('Save', Colors.white, Colors.black, () {
              final name = nameCtrl.text.trim(), phone = phoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              final msg = _checkDuplicate(name, phone);
              if (msg != null) { _showSnack(msg, color: Colors.redAccent); return; }
              _contactBox.add(Contact(name: name, phones: [phone], createdAt: DateTime.now()));
              _loadContacts();
              Navigator.pop(context);
            })),
          ]),
        ])),
      ),
    );
  }

  void _showAddPhoneModal(Contact contact) {
    if (contact.phones.length >= 2) return;
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Add Phone for ${contact.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          TextField(controller: phoneCtrl, style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone, decoration: _inputDecoration('New Phone Number')),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _pillButton('Cancel', Colors.white.withValues(alpha: 0.1), Colors.white, () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: _pillButton('Add', Colors.white, Colors.black, () {
              final p = phoneCtrl.text.trim();
              if (p.isEmpty) return;
              final msg = _checkDuplicate(contact.name, p, excludeContact: contact);
              if (msg != null) { _showSnack(msg, color: Colors.redAccent); return; }
              final phones = List<String>.from(contact.phones)..add(p);
              _updateContact(contact, Contact(name: contact.name, phones: phones, createdAt: contact.createdAt));
              Navigator.pop(context);
            })),
          ]),
        ])),
      ),
    );
  }

  void _showEditContactModal(Contact old) {
    final nameCtrl = TextEditingController(text: old.name);
    final p1Ctrl = TextEditingController(text: old.phones.isNotEmpty ? old.phones[0] : '');
    final p2Ctrl = TextEditingController(text: old.phones.length > 1 ? old.phones[1] : '');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _glassSheet(Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit Contact',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Name')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(controller: p1Ctrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone, decoration: _inputDecoration('Phone Number 1'))),
            if (old.phones.length > 1) ...[
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  onPressed: () => _showRemoveNumberConfirmation(old, 0, context)),
            ],
          ]),
          if (old.phones.length > 1) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(controller: p2Ctrl, style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone, decoration: _inputDecoration('Phone Number 2'))),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                  onPressed: () => _showRemoveNumberConfirmation(old, 1, context)),
            ]),
          ],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _pillButton('Cancel', Colors.white.withValues(alpha: 0.1), Colors.white, () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: _pillButton('Save', Colors.white, Colors.black, () {
              final name = nameCtrl.text.trim(), p1 = p1Ctrl.text.trim(), p2 = p2Ctrl.text.trim();
              if (name.isEmpty || p1.isEmpty) return;
              final msg = _checkDuplicate(name, p1, excludeContact: old);
              if (msg != null) { _showSnack(msg, color: Colors.redAccent); return; }
              final phones = [p1, if (p2.isNotEmpty && old.phones.length > 1) p2];
              _updateContact(old, Contact(name: name, phones: phones, createdAt: old.createdAt));
              Navigator.pop(context);
            })),
          ]),
        ])),
      ),
    );
  }

  void _showRemoveNumberConfirmation(Contact contact, int idx, BuildContext modalCtx) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove Number?', style: TextStyle(color: Colors.white)),
      content: Text('Remove ${contact.phones[idx]}?', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
        TextButton(onPressed: () {
          final phones = List<String>.from(contact.phones)..removeAt(idx);
          if (phones.isEmpty) {
            _showSnack('Contact must have at least one phone number', color: Colors.redAccent);
            Navigator.pop(context); return;
          }
          _updateContact(contact, Contact(name: contact.name, phones: phones, createdAt: contact.createdAt));
          Navigator.pop(context);
          Navigator.pop(modalCtx);
        }, child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  void _showSecondNumber(Contact contact) {
    if (contact.phones.length < 2) return;
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Additional Number', style: TextStyle(color: Colors.white)),
      content: Text(contact.phones[1], style: const TextStyle(color: Colors.white, fontSize: 18)),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.white70)))],
    ));
  }

  void _showOptionsMenu(Contact contact) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF2A2A2E), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (contact.phones.length < 2)
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                title: const Text('Add another number', style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(context); _showAddPhoneModal(contact); },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white70),
              title: const Text('Edit contact', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _showEditContactModal(contact); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete contact', style: TextStyle(color: Colors.redAccent)),
              onTap: () { Navigator.pop(context); _showDeleteConfirmation(contact); },
            ),
          ]),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Contact contact) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Contact?', style: TextStyle(color: Colors.white)),
      content: Text('Are you sure you want to delete ${contact.name}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
        TextButton(onPressed: () {
          final idx = _contactBox.values.toList().indexOf(contact);
          if (idx != -1) _contactBox.deleteAt(idx);
          _loadContacts();
          Navigator.pop(context);
        }, child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────

  void _updateContact(Contact old, Contact updated) {
    final idx = _contactBox.values.toList().indexOf(old);
    if (idx != -1) _contactBox.putAt(idx, updated);
    _loadContacts();
  }

  Widget _bottomSheet({required Widget child, required EdgeInsets padding}) =>
      Padding(padding: padding,
        child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5))),
              child: child))));

  Widget _glassSheet(Widget child) =>
      ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: const Color(0xFF2A2A2E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 0.5))),
            child: child)));

  Widget _sheetHandle() => Center(child: Container(
      width: 36, height: 4,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))));

  Widget _iconBox(IconData icon, Color color) => Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5)),
      child: Icon(icon, color: color, size: 22));

  InputDecoration _fieldDecoration(String label, {
    String? hint, IconData? prefix, Color accentColor = Colors.white,
    String? error, Widget? suffix,
  }) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      prefixIcon: prefix != null ? Icon(prefix, color: accentColor.withValues(alpha: 0.7)) : null,
      suffixIcon: suffix,
      errorText: error,
      errorStyle: const TextStyle(color: Colors.redAccent),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accentColor, width: 1)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent)));

  InputDecoration _inputDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));

  Widget _primaryButton({
    required String label, required bool loading,
    required Color color, required Color textColor, required VoidCallback onPressed,
  }) => SizedBox(width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: color, foregroundColor: textColor,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 0),
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: textColor == Colors.black ? Colors.black54 : Colors.white))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))));

  Widget _pillButton(String text, Color bg, Color fg, VoidCallback onPressed) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: bg, foregroundColor: fg,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            elevation: 0),
        onPressed: onPressed,
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)));

  void _showSnack(String msg, {Color color = const Color(0xFF3A3A3E)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color == const Color(0xFF3A3A3E) ? color : color.withValues(alpha: 0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      duration: const Duration(seconds: 3)));
  }

  String _formatRelative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: _closeMenu,
        child: Scaffold(
          backgroundColor: const Color(0xFF1C1C1E),
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent, elevation: 0,
            automaticallyImplyLeading: false,
            title: Row(children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Expanded(child: Container(
                height: 42,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: _search,
                  decoration: InputDecoration(
                      hintText: 'Search contacts...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.6), size: 22),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12))),
              )),
              const SizedBox(width: 8),
              // Spinner removed – sync runs silently in the background
              GestureDetector(
                key: _menuButtonKey,
                onTap: _toggleMenu,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: _menuOpen ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 26)),
              ),
            ]),
          ),
          body: Stack(children: [
            contacts.isEmpty
                ? const Center(child: Text('No contacts yet.\nTap ⋮ to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: contacts.length,
                    itemBuilder: (context, i) {
                      final c = contacts[i];
                      return Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            Stack(children: [
                              CircleAvatar(radius: 22,
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  child: Text(
                                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                              if (c.phones.length > 1)
                                Positioned(right: -2, bottom: -2,
                                  child: GestureDetector(onTap: () => _showSecondNumber(c),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                          color: Colors.greenAccent, shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFF1C1C1E), width: 2)),
                                      child: const Text('+1', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold))))),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              if (c.phones.isNotEmpty)
                                Text(c.phones[0], style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 15)),
                            ])),
                            Text(DateFormat('MMM dd').format(c.createdAt),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5)),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 24),
                                onPressed: () => _showOptionsMenu(c)),
                          ]),
                        ),
                        const Divider(color: Colors.white10, height: 1, thickness: 0.5),
                      ]);
                    }),
            Positioned(left: 0, right: 0, bottom: 20,
              child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      '${contacts.length} contact${contacts.length != 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, fontWeight: FontWeight.w500))))),
          ]),
        ),
      ),
    );
  }
}

class _DropdownItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _DropdownItem({
    required this.icon, required this.iconColor,
    required this.label, this.subtitle,
    required this.onTap, required this.showDivider,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11.5)),
            ],
          ])),
        ]))),
    if (showDivider)
      Divider(height: 1, thickness: 0.5,
          color: Colors.white.withValues(alpha: 0.08), indent: 16, endIndent: 16),
  ]);
}

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
  void initState() { super.initState(); _filtered = widget.deviceContacts; }

  void _onSearch(String q) => setState(() {
    _filtered = q.isEmpty ? widget.deviceContacts
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Expanded(child: Text('Select Contacts',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 0.5)),
                child: Text('$count selected',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w600))),
          ])),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(height: 44,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(22)),
            child: TextField(controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              onChanged: _onSearch,
              decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.5), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13))))),
        const SizedBox(height: 12),
        Expanded(child: _filtered.isEmpty
            ? Center(child: Text('No contacts found',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final dc = _filtered[i];
                  final sel = _selected.contains(dc.id);
                  return InkWell(onTap: () => _toggle(dc.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      child: Row(children: [
                        CircleAvatar(radius: 22,
                          backgroundColor: sel
                              ? Colors.greenAccent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.1),
                          child: Text(
                              dc.displayName.isNotEmpty ? dc.displayName[0].toUpperCase() : '?',
                              style: TextStyle(color: sel ? Colors.greenAccent : Colors.white,
                                  fontSize: 17, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(dc.displayName, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600)),
                          if (dc.phones.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(dc.phones[0].number, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13.5)),
                          ],
                        ])),
                        AnimatedContainer(duration: const Duration(milliseconds: 180),
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                              color: sel ? Colors.greenAccent : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(color: sel ? Colors.greenAccent : Colors.white38, width: 1.5)),
                          child: sel ? const Icon(Icons.check, color: Colors.black, size: 15) : null),
                      ])));
                })),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: count > 0 ? Colors.greenAccent : Colors.white.withValues(alpha: 0.15),
                  foregroundColor: count > 0 ? Colors.black : Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0),
              onPressed: count > 0 ? _save : null,
              child: Text(count > 0 ? 'Add $count contact${count != 1 ? 's' : ''}' : 'Add',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
          ]))),
      ]),
    );
  }
}
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '/core/api_client.dart';
import '/core/api_config.dart';

class LinkManagementScreen extends StatefulWidget {
  const LinkManagementScreen({super.key});

  @override
  State<LinkManagementScreen> createState() => _LinkManagementScreenState();
}

class _LinkManagementScreenState extends State<LinkManagementScreen> {
  static const Color zinc950 = Color(0xFF09090B);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc700 = Color(0xFF3F3F46);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);

  List<ActiveLink> _links = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // If getActiveLinks doesn't exist, fetch the single active link instead
      // and wrap it in a list for display.
      final activeLink = await ApiClient.instance.getActiveLink();
      if (mounted) {
        setState(() {
          if (activeLink != null) {
            _links = [activeLink];
          } else {
            _links = [];
          }
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _deleteLink(String token) async {
    try {
      await ApiClient.instance.deleteLink(token);
      if (mounted) {
        setState(() {
          _links.removeWhere((l) => l.linkToken == token);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link terminated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _copyLink(ActiveLink link) {
    final url =
        '${ApiConfig.baseUrl}/join/${link.linkType == 'registration_link' ? 'register-student' : 'edit-student'}?token=${link.linkToken}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: zinc950,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Links',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            onPressed: () => _showGenerateLinkSheet(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white30))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: zinc400, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load links',
                        style: TextStyle(color: zinc400, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: zinc500, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadLinks,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _links.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_off_rounded, color: zinc400, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'No active links',
                            style: TextStyle(color: zinc400, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Generate a new link to share',
                            style: TextStyle(color: zinc500, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _links.length,
                      itemBuilder: (context, index) {
                        final link = _links[index];
                        return _LinkCard(
                          link: link,
                          onCopy: () => _copyLink(link),
                          onDelete: () => _deleteLink(link.linkToken),
                        );
                      },
                    ),
    );
  }

  void _showGenerateLinkSheet() {
    String linkType = 'registration_link';
    bool generating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 2,
              left: 1,
              right: 1,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  decoration: BoxDecoration(
                    color: zinc900,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
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
                          decoration: BoxDecoration(color: zinc700, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const Text(
                        'Generate Link',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create a shareable student access link',
                        style: TextStyle(color: zinc400, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _buildLinkTypeButton('Registration', 'registration_link', linkType, (v) {
                            setModalState(() => linkType = v);
                          }),
                          const SizedBox(width: 8),
                          _buildLinkTypeButton('Edit', 'edit_link', linkType, (v) {
                            setModalState(() => linkType = v);
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: generating
                              ? null
                              : () async {
                                  setModalState(() => generating = true);
                                  try {
                                    final newLink = await ApiClient.instance.generateLink(linkType);
                                    if (mounted) {
                                      setModalState(() => generating = false);
                                      Navigator.pop(ctx);
                                      _loadLinks(); // refresh list
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Link generated successfully')),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setModalState(() => generating = false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString())),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: zinc950,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                          child: generating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                                )
                              : const Text(
                                  'Generate',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLinkTypeButton(String label, String value, String current, ValueChanged<String> onTap) {
    final selected = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? Colors.white : zinc700),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? zinc950 : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final ActiveLink link;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _LinkCard({required this.link, required this.onCopy, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = link.linkType == 'registration_link' ? Colors.greenAccent : Colors.blueAccent;

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
                  link.linkType.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Text(
                'Expires: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(link.expiresAt))}',
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${ApiConfig.baseUrl}/join/${link.linkType == 'registration_link' ? 'register-student' : 'edit-student'}?token=${link.linkToken}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                tooltip: 'Copy link',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                tooltip: 'Terminate link',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
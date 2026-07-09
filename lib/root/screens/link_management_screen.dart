import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '/core/api_client.dart';
import '/core/api_config.dart';

/// ── Shared palette, identical to HomeScreen's _Palette so every screen
/// reads as one continuous surface.
class _Palette {
  static const Color bg = Color(0xFF1C1C1E);
  static const Color surface = Color(0xFF18181B);
  static const Color hairline = Color(0xFF3F3F46);
  static const Color muted = Color(0xFF71717A);
  static const Color mutedLight = Color(0xFFA1A1AA);
}

class LinkManagementScreen extends StatefulWidget {
  const LinkManagementScreen({super.key});

  @override
  State<LinkManagementScreen> createState() => _LinkManagementScreenState();
}

class _LinkManagementScreenState extends State<LinkManagementScreen> {
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Palette.bg,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2)),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildErrorState(),
                )
              else if (_links.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                  sliver: SliverList.builder(
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
                ),
            ],
          ),
        ),
        floatingActionButton: _buildAddButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  // ── Header matching HomeScreen: big title left, glass back-button
  // right.
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
                const Text(
                  'My Links',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  _loading ? 'Loading…' : '${_links.length} active link${_links.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _Palette.muted, letterSpacing: 0.2),
                ),
              ],
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
              child: Icon(Icons.link_off_rounded, color: Colors.white.withValues(alpha: 0.3), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'No active links',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap Generate Link below to create one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _Palette.muted, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
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
                color: Colors.redAccent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, color: Colors.redAccent.withValues(alpha: 0.7), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load links',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: _Palette.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            ClipRRect(
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
                    height: 44,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _loadLinks,
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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

  // ── Add button styled like HomeScreen's "Send Message" pill: wide
  // glass pill with icon + label.
  Widget _buildAddButton() {
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
                onPressed: _showGenerateLinkSheet,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add_link_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Generate Link',
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

  // ── Generate-link sheet restyled with the same glass surface, hairline
  // border, segmented type selector, and pill button treatment as
  // HomeScreen's compose sheet.
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
                      const Text(
                        'Generate Link',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create a shareable student access link',
                        style: TextStyle(color: _Palette.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
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
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                            ),
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: generating
                                    ? null
                                    : () async {
                                        setModalState(() => generating = true);
                                        try {
                                          await ApiClient.instance.generateLink(linkType);
                                          if (mounted) {
                                            setModalState(() => generating = false);
                                          }
                                          if (context.mounted) {
                                            Navigator.pop(ctx);
                                            _loadLinks();
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
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                child: generating
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text(
                                        'Generate',
                                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: _Palette.mutedLight, fontSize: 13, fontWeight: FontWeight.w600),
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

  // ── Segmented selector, same visual language as the SIM-card selector
  // in HomeScreen's compose sheet.
  Widget _buildLinkTypeButton(String label, String value, String current, ValueChanged<String> onTap) {
    final selected = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
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
            label,
            style: TextStyle(
              color: selected ? Colors.white : _Palette.mutedLight,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Card restyled to match HomeScreen's glass surfaces: translucent
/// fill, hairline border, rounded status pill, muted meta row.
class _LinkCard extends StatelessWidget {
  final ActiveLink link;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _LinkCard({required this.link, required this.onCopy, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = link.linkType == 'registration_link' ? Colors.greenAccent : Colors.blueAccent;
    final url =
        '${ApiConfig.baseUrl}/join/${link.linkType == 'registration_link' ? 'register-student' : 'edit-student'}?token=${link.linkToken}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      link.linkType.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Expires ${DateFormat('dd/MM/yyyy').format(DateTime.parse(link.expiresAt))}',
                style: TextStyle(color: _Palette.mutedLight, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            url,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 6),
          Row(
            children: [
              _CardActionIcon(icon: Icons.copy_rounded, color: Colors.white70, tooltip: 'Copy link', onTap: onCopy),
              const SizedBox(width: 4),
              _CardActionIcon(
                icon: Icons.delete_outline_rounded,
                color: Colors.redAccent.withValues(alpha: 0.85),
                tooltip: 'Terminate link',
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _CardActionIcon({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/sms_session.dart';
import '../../services/sms_session_store.dart';

class SessionDetailScreen extends StatelessWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  static const Color bgDark = Color(0xFF1C1C1E);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Session Detail', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListenableBuilder(
        listenable: context.read<SmsSessionStore>(),
        builder: (context, _) {
          final store = context.read<SmsSessionStore>();
          final matches = store.sessions.where((s) => s.id == sessionId);
          if (matches.isEmpty) {
            return const Center(
              child: Text('This session no longer exists.', style: TextStyle(color: Colors.white54)),
            );
          }
          final session = matches.first;
          return _SessionDetailBody(session: session, store: store);
        },
      ),
    );
  }
}

class _SessionDetailBody extends StatelessWidget {
  final SmsSession session;
  final SmsSessionStore store;
  const _SessionDetailBody({required this.session, required this.store});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy — HH:mm').format(session.startedAt),
                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                  ),
                  _buildStateBadge(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                session.message,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: session.progressFraction,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    session.isComplete
                        ? (session.failedCount == 0 ? Colors.greenAccent : Colors.orangeAccent)
                        : Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStatsCard(context),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF27272A), thickness: 0.5),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: session.recipients.length,
            itemBuilder: (_, i) {
              final r = session.recipients[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _recipientIcon(r.status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                          Text(r.phone, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                          if (r.error != null)
                            Text(r.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ],
                      ),
                    ),
                    if ((r.retryCount > 0) || ((r.deliveryRetryCount ?? 0) > 0))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '↺ ${r.retryCount + (r.deliveryRetryCount ?? 0)}',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Session Stats', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13, fontWeight: FontWeight.w600)),
              Text('SIM: ${session.simLabel}', style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statItem('Total', session.totalCount.toString(), const Color(0xFFD4D4D8)),
              const SizedBox(width: 20),
              _statItem('Sent ✓', session.sentCount.toString(), Colors.greenAccent),
              const SizedBox(width: 20),
              _statItem('Failed ✗', session.failedCount.toString(), Colors.redAccent),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _statItem('Pending ⌛', session.pendingCount.toString(), const Color(0xFF71717A)),
              const SizedBox(width: 20),
              _statItem('Not Delivered ⚠️', session.sentButNotDeliveredCount.toString(), Colors.orangeAccent),
              const Spacer(),
              if (session.retryPass > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('Retry ${session.retryPass}', style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              if (!session.isComplete) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Running', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if ((session.failedCount > 0 || session.sentButNotDeliveredCount > 0) && session.isComplete)
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => store.retrySession(session.id),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Failed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
      ],
    );
  }

  Widget _buildStateBadge() {
    String label;
    Color color;
    if (!session.isComplete) {
      label = session.state == SmsSessionState.retrying ? 'Retrying…' : 'Sending…';
      color = Colors.blueAccent;
    } else if (session.failedCount == 0) {
      label = 'Done ✓';
      color = Colors.greenAccent;
    } else {
      label = '${session.failedCount} failed';
      color = Colors.orangeAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _recipientIcon(SmsRecipientStatus status) {
    switch (status) {
      case SmsRecipientStatus.sent:
        return const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20);
      case SmsRecipientStatus.sentNotDelivered:
        return const Icon(Icons.check_circle_outline_rounded, color: Colors.orangeAccent, size: 20);
      case SmsRecipientStatus.failed:
        return const Icon(Icons.error_rounded, color: Colors.redAccent, size: 20);
      case SmsRecipientStatus.pending:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF71717A)),
        );
    }
  }
}
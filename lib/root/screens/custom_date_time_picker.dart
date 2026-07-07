import 'dart:ui';
import 'package:flutter/material.dart';

/// ── Custom glass-styled date & time picker, fully independent of
/// showDatePicker/showTimePicker. Matches HomeScreen's dark, minimal,
/// glass aesthetic (#1C1C1E surfaces, translucent white fills, hairline
/// borders, rounded pill CTAs).
///
/// Time format (12h vs 24h) is detected automatically from the device's
/// locale/system setting via MediaQuery.alwaysUse24HourFormat — no manual
/// toggle needed.
///
/// Usage:
/// final result = await showCustomDateTimePicker(
///   context: context,
///   initialDateTime: _scheduledTime,
/// );
/// if (result != null) setState(() => _scheduledTime = result);
Future<DateTime?> showCustomDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final use24Hour = MediaQuery.of(context).alwaysUse24HourFormat;
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return _CustomDateTimeSheet(
        initialDateTime: initialDateTime,
        firstDate: firstDate ?? DateTime.now(),
        lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
        use24Hour: use24Hour,
      );
    },
  );
}

class _Palette {
  static const Color surface = Color(0xFF18181B);
  static const Color hairline = Color(0xFF3F3F46);
  static const Color muted = Color(0xFF71717A);
  static const Color mutedLight = Color(0xFFA1A1AA);
}

class _CustomDateTimeSheet extends StatefulWidget {
  final DateTime initialDateTime;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool use24Hour;
  const _CustomDateTimeSheet({
    required this.initialDateTime,
    required this.firstDate,
    required this.lastDate,
    required this.use24Hour,
  });

  @override
  State<_CustomDateTimeSheet> createState() => _CustomDateTimeSheetState();
}

class _CustomDateTimeSheetState extends State<_CustomDateTimeSheet> {
  late DateTime _selectedDate;
  late int _hour24;
  late int _minute;
  late DateTime _visibleMonth;
  int _tabIndex = 0; // 0 = date, 1 = time

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDateTime.year,
      widget.initialDateTime.month,
      widget.initialDateTime.day,
    );
    _hour24 = widget.initialDateTime.hour;
    _minute = widget.initialDateTime.minute;
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  DateTime get _combined => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _hour24,
        _minute,
      );

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isDateEnabled(DateTime d) {
    final first = DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final last = DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
    return !d.isBefore(first) && !d.isAfter(last);
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  // ── Formats the confirmed time preview/label according to the detected
  // device format (24h: "14:05", 12h: "2:05 PM").
  String _formatHourMinute(int hour24, int minute) {
    final mm = minute.toString().padLeft(2, '0');
    if (widget.use24Hour) {
      return '${hour24.toString().padLeft(2, '0')}:$mm';
    }
    final isPm = hour24 >= 12;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:$mm ${isPm ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20, 14, 20,
            MediaQuery.of(context).viewPadding.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: _Palette.surface.withValues(alpha: 0.97),
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Schedule Time',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white54, size: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSegmentedTabs(),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _tabIndex == 0
                    ? _buildDateTab(key: const ValueKey('date'))
                    : _buildTimeTab(key: const ValueKey('time')),
              ),
              const SizedBox(height: 20),
              _buildConfirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Segmented tab control (Date / Time), same visual language as the
  // SIM-card segmented selector in the compose sheet. Time tab shows the
  // currently selected time formatted per the device's 12h/24h setting.
  Widget _buildSegmentedTabs() {
    return Row(
      children: [
        Expanded(child: _tabButton('Date', 0)),
        const SizedBox(width: 8),
        Expanded(child: _tabButton(_formatHourMinute(_hour24, _minute), 1)),
      ],
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
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
    );
  }

  // ── Custom calendar grid, hand-built (no Material date picker).
  Widget _buildDateTab({required Key key}) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // Monday-first offset (weekday: Mon=1..Sun=7)
    final leadingBlanks = firstOfMonth.weekday - 1;

    final canGoPrev = DateTime(_visibleMonth.year, _visibleMonth.month - 1)
        .isAfter(DateTime(widget.firstDate.year, widget.firstDate.month - 1));
    final canGoNext = DateTime(_visibleMonth.year, _visibleMonth.month + 1)
        .isBefore(DateTime(widget.lastDate.year, widget.lastDate.month + 1));

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _navArrow(Icons.chevron_left_rounded, canGoPrev ? () => _changeMonth(-1) : null),
            Expanded(
              child: Center(
                child: Text(
                  '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            _navArrow(Icons.chevron_right_rounded, canGoNext ? () => _changeMonth(1) : null),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: _weekdayLabels
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(color: _Palette.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingBlanks + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = index - leadingBlanks + 1;
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
            final enabled = _isDateEnabled(date);
            final isSelected = _isSameDay(date, _selectedDate);
            final isToday = _isSameDay(date, DateTime.now());

            return GestureDetector(
              onTap: enabled ? () => setState(() => _selectedDate = date) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  shape: BoxShape.circle,
                  border: (!isSelected && isToday)
                      ? Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.black
                        : (enabled ? Colors.white : Colors.white.withValues(alpha: 0.18)),
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _navArrow(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white70, size: 18),
      ),
    );
  }

  // ── Custom scrolling wheel-style time selector (hour / minute [/ AM-PM]),
  // hand-built with ListWheelScrollView instead of the Material time picker.
  // Layout adapts automatically: 24h shows only Hour:Minute (00-23), 12h
  // shows Hour:Minute + an AM/PM wheel — based on widget.use24Hour, which
  // was detected from the device's system setting.
  Widget _buildTimeTab({required Key key}) {
    if (widget.use24Hour) {
      return Column(
        key: key,
        children: [
          SizedBox(
            height: 160,
            child: Row(
              children: [
                Expanded(
                  child: _WheelColumn(
                    itemCount: 24,
                    initialIndex: _hour24,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onChanged: (i) => setState(() => _hour24 = i),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    ':',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: _WheelColumn(
                    itemCount: 60,
                    initialIndex: _minute,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onChanged: (i) => setState(() => _minute = i),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final isPm = _hour24 >= 12;
    final hour12 = _hour24 % 12 == 0 ? 12 : _hour24 % 12;

    return Column(
      key: key,
      children: [
        SizedBox(
          height: 160,
          child: Row(
            children: [
              Expanded(
                child: _WheelColumn(
                  itemCount: 12,
                  initialIndex: hour12 - 1,
                  labelBuilder: (i) => (i + 1).toString().padLeft(2, '0'),
                  onChanged: (i) {
                    final newHour12 = i + 1;
                    setState(() {
                      _hour24 = isPm
                          ? (newHour12 == 12 ? 12 : newHour12 + 12)
                          : (newHour12 == 12 ? 0 : newHour12);
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  ':',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: _WheelColumn(
                  itemCount: 60,
                  initialIndex: _minute,
                  labelBuilder: (i) => i.toString().padLeft(2, '0'),
                  onChanged: (i) => setState(() => _minute = i),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WheelColumn(
                  itemCount: 2,
                  initialIndex: isPm ? 1 : 0,
                  labelBuilder: (i) => i == 0 ? 'AM' : 'PM',
                  onChanged: (i) {
                    setState(() {
                      final wasPm = _hour24 >= 12;
                      final nowPm = i == 1;
                      if (wasPm != nowPm) {
                        _hour24 = nowPm ? _hour24 + 12 : _hour24 - 12;
                        _hour24 = _hour24 % 24;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton() {
    return ClipRRect(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () => Navigator.pop(context, _combined),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Confirm', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Reusable scrolling wheel column used for hour / minute / AM-PM.
class _WheelColumn extends StatefulWidget {
  final int itemCount;
  final int initialIndex;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;

  const _WheelColumn({
    required this.itemCount,
    required this.initialIndex,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: 40,
          perspective: 0.003,
          diameterRatio: 1.6,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: widget.onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.itemCount,
            builder: (context, index) {
              return Center(
                child: Text(
                  widget.labelBuilder(index),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
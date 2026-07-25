import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Compact month-grid calendar. Days with meetings get a small dot; the
/// selected day is highlighted. Convene-only (no external calendar sync) -
/// just visualizes meetings already loaded from Firestore.
class MiniMonthCalendar extends StatelessWidget {
  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final Map<DateTime, int> eventCounts; // keyed by day at midnight
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onMonthChanged;

  const MiniMonthCalendar({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.eventCounts,
    required this.onDaySelected,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    // Monday = 0 .. Sunday = 6, so the grid always starts on a Monday.
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday) % 7;
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: context.colors.textMuted),
                onPressed: () => onMonthChanged(DateTime(visibleMonth.year, visibleMonth.month - 1)),
              ),
              Text(
                DateFormat('MMMM y').format(visibleMonth),
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textMain),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: context.colors.textMuted),
                onPressed: () => onMonthChanged(DateTime(visibleMonth.year, visibleMonth.month + 1)),
              ),
            ],
          ),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.textLight),
                        ),
                      ),
                    ))
                .toList(),
          ),
          SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final date = DateTime(visibleMonth.year, visibleMonth.month, day);
              final isToday = date == todayKey;
              final isSelected = selectedDate != null &&
                  date.year == selectedDate!.year &&
                  date.month == selectedDate!.month &&
                  date.day == selectedDate!.day;
              final count = eventCounts[date] ?? 0;

              return GestureDetector(
                onTap: () => onDaySelected(date),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected ? context.colors.primary : (isToday ? context.colors.primaryLight : null),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isToday ? context.colors.primary : context.colors.textMain),
                        ),
                      ),
                      if (count > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : context.colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

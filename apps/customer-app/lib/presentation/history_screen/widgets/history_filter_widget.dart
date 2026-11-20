import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class HistoryFilterWidget extends StatelessWidget {
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final Map<String, int> counts;

  const HistoryFilterWidget({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final filters = [
      {'key': 'all', 'label': 'الكل'},
      {'key': 'deposit', 'label': 'شحن'},
      {'key': 'withdraw', 'label': 'دفع'},
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = filters[i];
          final isActive = activeFilter == f['key'];
          final count = counts[f['key']] ?? 0;

          return GestureDetector(
            onTap: () => onFilterChanged(f['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.emeraldDark
                    : AppTheme.surfaceCard.withAlpha(128),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isActive
                      ? AppTheme.emeraldPrimary.withAlpha(128)
                      : AppTheme.emeraldMuted.withAlpha(51),
                  width: 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppTheme.emeraldPrimary.withAlpha(38),
                          blurRadius: 8,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f['label']!,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? AppTheme.emeraldPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.emeraldPrimary.withAlpha(51)
                          : AppTheme.backgroundDeep.withAlpha(102),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.sora(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppTheme.emeraldPrimary
                            : AppTheme.textMuted,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

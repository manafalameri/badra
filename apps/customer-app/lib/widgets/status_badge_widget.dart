import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum TransactionStatus {
  completed,
  pending,
  failed,
  incoming,
  outgoing,
  service,
}

class StatusBadgeWidget extends StatelessWidget {
  final TransactionStatus status;
  final String? customLabel;

  const StatusBadgeWidget({super.key, required this.status, this.customLabel});

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: config.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: config.borderColor, width: 1),
      ),
      child: Text(
        customLabel ?? config.label,
        style: GoogleFonts.sora(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: config.textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  _BadgeConfig _getConfig(TransactionStatus s) {
    switch (s) {
      case TransactionStatus.completed:
        return _BadgeConfig(
          label: 'مكتملة',
          bgColor: AppTheme.emeraldPrimary.withAlpha(31),
          borderColor: AppTheme.emeraldPrimary.withAlpha(102),
          textColor: AppTheme.emeraldPrimary,
        );
      case TransactionStatus.pending:
        return _BadgeConfig(
          label: 'قيد التنفيذ',
          bgColor: AppTheme.warning.withAlpha(31),
          borderColor: AppTheme.warning.withAlpha(102),
          textColor: AppTheme.warning,
        );
      case TransactionStatus.failed:
        return _BadgeConfig(
          label: 'فشلت',
          bgColor: AppTheme.error.withAlpha(31),
          borderColor: AppTheme.error.withAlpha(102),
          textColor: AppTheme.error,
        );
      case TransactionStatus.incoming:
        return _BadgeConfig(
          label: 'وارد',
          bgColor: AppTheme.incoming.withAlpha(31),
          borderColor: AppTheme.incoming.withAlpha(102),
          textColor: AppTheme.incoming,
        );
      case TransactionStatus.outgoing:
        return _BadgeConfig(
          label: 'صادر',
          bgColor: AppTheme.textSecondary.withAlpha(26),
          borderColor: AppTheme.textSecondary.withAlpha(77),
          textColor: AppTheme.textSecondary,
        );
      case TransactionStatus.service:
        return _BadgeConfig(
          label: 'خدمة',
          bgColor: AppTheme.goldAccent.withAlpha(26),
          borderColor: AppTheme.goldAccent.withAlpha(77),
          textColor: AppTheme.goldAccent,
        );
    }
  }
}

class _BadgeConfig {
  final String label;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  _BadgeConfig({
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../data/mock_transactions.dart';

class DateRangeDialog extends StatefulWidget {
  final TransactionModel transaction;

  const DateRangeDialog({super.key, required this.transaction});

  @override
  State<DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<DateRangeDialog> {
  // TODO: Replace with Riverpod/Bloc for production
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _generating = false;
  bool _generated = false;

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? now.subtract(const Duration(days: 30)))
          : (_toDate ?? now),
      firstDate: DateTime(2023),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.emeraldPrimary,
              onPrimary: AppTheme.backgroundDeep,
              surface: AppTheme.surfaceDark,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _generateStatement() async {
    if (_fromDate == null || _toDate == null) return;
    setState(() => _generating = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _generating = false;
      _generated = true;
    });
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'اختر التاريخ';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark.withAlpha(242),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(51),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: _generated ? _buildSuccessState() : _buildPickerState(),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'تحميل الكشف',
              style: GoogleFonts.sora(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard.withAlpha(128),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'حدد الفترة الزمنية لاستخراج كشف الحساب',
          style: GoogleFonts.sora(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 24),
        _buildDateSelector(
          label: 'من تاريخ',
          value: _formatDate(_fromDate),
          icon: Icons.calendar_today_outlined,
          onTap: () => _pickDate(true),
        ),
        const SizedBox(height: 12),
        _buildDateSelector(
          label: 'إلى تاريخ',
          value: _formatDate(_toDate),
          icon: Icons.event_outlined,
          onTap: () => _pickDate(false),
        ),
        if (_fromDate != null &&
            _toDate != null &&
            _toDate!.isBefore(_fromDate!)) ...[
          const SizedBox(height: 10),
          Text(
            'تاريخ النهاية يجب أن يكون بعد تاريخ البداية',
            style: GoogleFonts.sora(fontSize: 11, color: AppTheme.error),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed:
                (_fromDate != null &&
                    _toDate != null &&
                    !_toDate!.isBefore(_fromDate!) &&
                    !_generating)
                ? _generateStatement
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emeraldPrimary,
              foregroundColor: AppTheme.backgroundDeep,
              disabledBackgroundColor: AppTheme.emeraldDark.withAlpha(102),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.backgroundDeep,
                    ),
                  )
                : Text(
                    'استخراج الكشف',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withAlpha(128),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.emeraldMuted.withAlpha(77),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.emeraldPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success.withAlpha(31),
            border: Border.all(color: AppTheme.success.withAlpha(77), width: 1),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 32,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'تم استخراج الكشف',
          style: GoogleFonts.sora(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'من ${_formatDate(_fromDate)} إلى ${_formatDate(_toDate)}',
          style: GoogleFonts.sora(fontSize: 12, color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emeraldPrimary,
              foregroundColor: AppTheme.backgroundDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: Text(
              'إغلاق',
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

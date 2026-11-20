import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/mock_transactions.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/badra_luxury_toast.dart';

class TransactionReceiptScreen extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionReceiptScreen({super.key, required this.transaction});

  String get _statusLabel {
    switch (transaction.status) {
      case TxStatus.completed:
        return 'مكتملة بنجاح';
      case TxStatus.pending:
        return 'قيد المعالجة';
      case TxStatus.failed:
        return 'فشلت العملية';
    }
  }

  Color get _statusColor {
    switch (transaction.status) {
      case TxStatus.completed:
        return AppTheme.success;
      case TxStatus.pending:
        return AppTheme.warning;
      case TxStatus.failed:
        return AppTheme.error;
    }
  }

  IconData get _statusIcon {
    switch (transaction.status) {
      case TxStatus.completed:
        return Icons.check_circle_outline;
      case TxStatus.pending:
        return Icons.hourglass_top;
      case TxStatus.failed:
        return Icons.error_outline;
    }
  }

  /// Returns true if notes contain meaningful content beyond just the ref
  bool get _hasMeaningfulNotes {
    final notes = transaction.notes.trim();
    if (notes.isEmpty) return false;
    final ref = transaction.ref.trim();
    // Hide notes if they're just a duplicate of ref or id
    if (notes == ref || notes == transaction.id) return false;
    // Hide if notes only contain the ref with common prefixes
    if (notes.startsWith('order_ref:') || notes.startsWith('order:')) {
      final stripped = notes.replaceFirst(RegExp(r'^order(_ref)?:\s*'), '').trim();
      if (stripped == ref || stripped == transaction.id || stripped.isEmpty) {
        return false;
      }
    }
    // Hide discount notes if the discount card already displays it
    if (transaction.discountAmount != null &&
        transaction.discountAmount! > 0 &&
        notes.startsWith('خصم:')) {
      return false;
    }
    return true;
  }

  String get _displayNotes {
    final notes = transaction.notes.trim();
    if (!_hasMeaningfulNotes) return '';
    return notes;
  }

  String get _shareContent {
    final buffer = StringBuffer();
    buffer.writeln('إيصال المعاملة');
    buffer.writeln('الحالة: $_statusLabel');
    if (transaction.discountAmount != null && transaction.discountAmount! > 0) {
      final orig = transaction.originalAmount != null
          ? transaction.originalAmount!.toStringAsFixed(0)
          : '';
      if (orig.isNotEmpty) buffer.writeln('المبلغ الأصلي: $orig ر.ي');
      buffer.writeln('قيمة الخصم: -${transaction.discountAmount!.toStringAsFixed(0)} ر.ي 🔥');
      buffer.writeln('المبلغ الصافي المدفوع: ${transaction.formattedAmount} ر.ي');
    } else {
      buffer.writeln('المبلغ: ${transaction.formattedAmount} ر.ي');
    }
    buffer.writeln('من: ${transaction.debtor.isNotEmpty ? transaction.debtor : '—'}');
    buffer.writeln('إلى: ${transaction.creditor.isNotEmpty ? transaction.creditor : '—'}');
    buffer.writeln('تاريخ ووقت المعاملة: ${transaction.fullDateTime}');
    final displayRef = transaction.shortRef.isNotEmpty
        ? '•••• ${transaction.shortRef}'
        : (transaction.ref.isNotEmpty ? transaction.ref : transaction.id);
    buffer.writeln('رقم المعاملة: $displayRef');
    if (_hasMeaningfulNotes) {
      buffer.writeln('الملاحظات: $_displayNotes');
    }
    return buffer.toString();
  }

  void _shareReceipt(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareContent));
    BadraLuxuryToast.show(
      context,
      'تم نسخ الإيصال إلى الحافظة',
      type: BadraToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildSectionTile(
    String title,
    String value,
    IconData icon, {
    VoidCallback? onCopy,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withAlpha(220),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.emeraldPrimary.withAlpha(20),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.emeraldPrimary.withAlpha(18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.emeraldPrimary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCopy,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldPrimary.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.copy_rounded,
                  color: AppTheme.emeraldPrimary,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDeep,
        appBar: AppBar(
          backgroundColor: AppTheme.surfaceDark,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.textPrimary),
          title: Text(
            'إيصال المعاملة',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppTheme.emeraldPrimary.withAlpha(24),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.emeraldPrimary.withAlpha(16),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor.withAlpha(26),
                            ),
                            child: Icon(
                              _statusIcon,
                              color: _statusColor,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'حالة المعاملة',
                                  style: GoogleFonts.sora(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _statusLabel,
                                  style: GoogleFonts.sora(
                                    fontSize: 14,
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              transaction.formattedAmount,
                              style: GoogleFonts.sora(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            'ر.ي',
                            style: GoogleFonts.sora(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.goldAccent,
                            ),
                          ),
                        ],
                      ),
                      if (transaction.discountAmount != null && transaction.discountAmount! > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B5E20).withAlpha(35),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.greenAccent.withAlpha(80),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.local_offer_rounded,
                                    color: Colors.greenAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'تفاصيل كود الخصم والتوفير',
                                    style: GoogleFonts.sora(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (transaction.originalAmount != null && transaction.originalAmount! > 0) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'المبلغ الأصلي:',
                                      style: GoogleFonts.sora(
                                        fontSize: 13,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    Text(
                                      '${transaction.originalAmount!.toStringAsFixed(0)} ر.ي',
                                      style: GoogleFonts.sora(
                                        fontSize: 13,
                                        color: AppTheme.textMuted,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'قيمة الخصم:',
                                    style: GoogleFonts.sora(
                                      fontSize: 13,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '- ${transaction.discountAmount!.toStringAsFixed(0)} ر.ي 🔥',
                                    style: GoogleFonts.sora(
                                      fontSize: 14,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildSectionTile(
                        'من',
                        transaction.debtor.isNotEmpty ? transaction.debtor : '—',
                        Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildSectionTile(
                        'إلى',
                        transaction.creditor.isNotEmpty ? transaction.creditor : '—',
                        Icons.storefront_outlined,
                      ),
                      const SizedBox(height: 18),
                      _buildSectionTile(
                        'تاريخ ووقت المعاملة',
                        transaction.fullDateTime,
                        Icons.access_time_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildSectionTile(
                        'رقم المعاملة',
                        '•••• ${transaction.shortRef.isNotEmpty ? transaction.shortRef : TransactionModel.computeShortRef(transaction.ref, transaction.id)}',
                        Icons.tag_rounded,
                        onCopy: () {
                          final short = transaction.shortRef.isNotEmpty
                              ? transaction.shortRef
                              : TransactionModel.computeShortRef(transaction.ref, transaction.id);
                          Clipboard.setData(ClipboardData(text: short));
                          BadraLuxuryToast.show(
                            context,
                            'تم نسخ رقم المعاملة (#$short)',
                            type: BadraToastType.info,
                            duration: const Duration(seconds: 2),
                          );
                        },
                      ),
                      if (_hasMeaningfulNotes) ...[
                        const SizedBox(height: 14),
                        _buildSectionTile(
                          'الملاحظات',
                          _displayNotes,
                          Icons.notes_rounded,
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => _shareReceipt(context),
                          icon: const Icon(Icons.share_rounded, size: 20),
                          label: Text(
                            'مشاركة',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.emeraldPrimary,
                            foregroundColor: AppTheme.backgroundDeep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

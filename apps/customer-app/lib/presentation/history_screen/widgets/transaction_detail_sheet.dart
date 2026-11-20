import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/string_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../data/mock_transactions.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionDetailSheet({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark.withAlpha(242),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(38),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.emeraldMuted.withAlpha(102),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _buildHeader(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildDivider(),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      'المدين',
                      transaction.debtor,
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      'الدائن',
                      transaction.creditor,
                      Icons.account_balance_outlined,
                    ),
                    const SizedBox(height: 12),
                    if (transaction.notes.trim().isNotEmpty &&
                        !transaction.notes.startsWith('order_ref:') &&
                        !transaction.notes.startsWith('order:')) ...[
                      _buildDetailRow(
                        'الملاحظات',
                        transaction.notes.toLatinDigits(),
                        Icons.notes_rounded,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildDetailRow(
                      'التاريخ والوقت',
                      transaction.fullDateTime,
                      Icons.access_time_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      'رقم المعاملة',
                      '•••• ${transaction.shortRef.isNotEmpty ? transaction.shortRef : TransactionModel.computeShortRef(transaction.ref, transaction.id)}',
                      Icons.tag_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildDivider(),
                    const SizedBox(height: 20),
                    _buildStatusRow(),
                    const SizedBox(height: 28),
                    _buildCloseButton(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isIncoming = transaction.type == TransactionType.incoming;
    final isFailed = transaction.status == TxStatus.failed;

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFailed
                ? AppTheme.error.withAlpha(31)
                : isIncoming
                ? AppTheme.incoming.withAlpha(31)
                : AppTheme.textSecondary.withAlpha(26),
            border: Border.all(
              color: isFailed
                  ? AppTheme.error.withAlpha(77)
                  : isIncoming
                  ? AppTheme.incoming.withAlpha(77)
                  : AppTheme.textSecondary.withAlpha(51),
              width: 1,
            ),
          ),
          child: Icon(
            isFailed
                ? Icons.error_outline_rounded
                : isIncoming
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            size: 28,
            color: isFailed
                ? AppTheme.error
                : isIncoming
                ? AppTheme.incoming
                : AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          transaction.title,
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${isIncoming ? '+' : '-'}${transaction.formattedAmount}',
              style: GoogleFonts.sora(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: isFailed
                    ? AppTheme.error
                    : isIncoming
                    ? AppTheme.incoming
                    : AppTheme.outgoing,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'ر.ي',
              style: GoogleFonts.sora(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.goldAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.emeraldPrimary.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: AppTheme.emeraldPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    Color statusColor;
    String statusLabel;
    switch (transaction.status) {
      case TxStatus.completed:
        statusColor = AppTheme.success;
        statusLabel = 'مكتملة بنجاح';
        break;
      case TxStatus.pending:
        statusColor = AppTheme.warning;
        statusLabel = 'قيد المعالجة';
        break;
      case TxStatus.failed:
        statusColor = AppTheme.error;
        statusLabel = 'فشلت العملية';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withAlpha(64), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: statusColor.withAlpha(128), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'حالة المعاملة: $statusLabel',
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 1, color: AppTheme.emeraldPrimary.withAlpha(26));
  }

  Widget _buildCloseButton(BuildContext context) {
    return SizedBox(
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
          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

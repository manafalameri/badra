import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../widgets/app_theme.dart';

class DepositHistoryList extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final VoidCallback? onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;

  const DepositHistoryList({
    super.key, 
    required this.records,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = false,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.history_rounded, size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'لا توجد إيداعات حتى الآن',
              style: AppTextStyles.bodySecondary,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...records.map((r) => _DepositRecordTile(record: r)),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: isLoadingMore
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : TextButton.icon(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: const Text(
                        'تحميل المزيد',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                      ),
                      onPressed: onLoadMore,
                    ),
            ),
          ),
      ],
    );
  }
}

class _DepositRecordTile extends StatelessWidget {
  final Map<String, dynamic> record;

  const _DepositRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat('#,###', 'en');
    final amount = (record['amount'] as num).toDouble();
    final date = DateTime.tryParse(record['created_at'] ?? '');
    final bankName = record['bank_name'] ?? '';
    final userName = record['user_name'] ?? 'غير معروف';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_rounded,
                color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userName,
                  style: AppTextStyles.body.copyWith(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$bankName • ${record['user_wallet_id'] ?? ''}',
                  style: AppTextStyles.label,
                ),
                if (date != null)
                  Text(
                    DateFormat('yyyy/MM/dd - HH:mm', 'en').format(date),
                    style: AppTextStyles.label,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${format.format(amount)} ﷼',
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.success,
                  fontSize: 14,
                ),
              ),
              if (record['admin_name'] != null)
                Text(
                  'بواسطة: ${record['admin_name']}',
                  style: AppTextStyles.label.copyWith(fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
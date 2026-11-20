import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class PaymentRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const PaymentRequestCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onReject,
  });

  @override
  State<PaymentRequestCard> createState() => _PaymentRequestCardState();
}

class _PaymentRequestCardState extends State<PaymentRequestCard> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  @override
  void didUpdateWidget(PaymentRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request['expires_at'] != widget.request['expires_at']) {
      _updateRemaining();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    try {
      final expiresAtStr = widget.request['expires_at'] as String?;
      if (expiresAtStr == null) {
        _timer?.cancel();
        setState(() => _remaining = Duration.zero);
        return;
      }
      final expiresAt = DateTime.parse(expiresAtStr);
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining.isNegative) {
        _timer?.cancel();
        setState(() => _remaining = Duration.zero);
      } else {
        setState(() => _remaining = remaining);
      }
    } catch (e) {
      _timer?.cancel();
      setState(() => _remaining = Duration.zero);
    }
  }

  String get _formattedTime {
    if (_remaining.isNegative || _remaining == Duration.zero) {
      return 'منتهي';
    }
    final secs = _remaining.inSeconds;
    final min = secs ~/ 60;
    final sec = secs % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _formatAmount(dynamic amount) {
    final num = double.tryParse(amount.toString()) ?? 0;
    if (num == num.toInt()) return num.toInt().toString();
    return num.toStringAsFixed(2);
  }

  String _formatShortRef(String ref) {
    if (ref.isEmpty) return '';
    final digits = ref.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    return ref;
  }

  String get _displayMerchantName {
    final raw = (widget.request['merchant_name'] as String? ?? '').trim();
    if (raw.isEmpty || raw == 'برسيم' || raw.contains('برسيم')) return 'تليد';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.request['amount'] ?? 0;
    final orderRef = widget.request['order_ref'] as String? ?? '';
    final items = widget.request['items'] as List<dynamic>? ?? [];
    final isExpired = _remaining.isNegative || _remaining == Duration.zero;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpired
              ? AppTheme.error.withAlpha(60)
              : AppTheme.emeraldPrimary.withAlpha(40),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldPrimary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.emeraldPrimary.withAlpha(80),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.emeraldPrimary.withAlpha(30),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/tallet.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.storefront_rounded,
                        color: AppTheme.emeraldPrimary,
                        size: 20,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayMerchantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'طلب #${_formatShortRef(orderRef)}',
                        style: GoogleFonts.sora(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? AppTheme.error.withAlpha(30)
                          : AppTheme.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formattedTime,
                      style: GoogleFonts.sora(
                        color: isExpired ? AppTheme.error : AppTheme.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'المبلغ:',
                  style: GoogleFonts.sora(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_formatAmount(amount)} ريال',
                  style: GoogleFonts.sora(
                    color: AppTheme.emeraldPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'الأصناف:',
                style: GoogleFonts.sora(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              ...items.take(3).map((item) {
                final name = item is Map ? (item['name'] ?? item['title'] ?? '') : item.toString();
                final qty = item is Map ? (item['quantity'] ?? item['qty'] ?? '') : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $name${qty.toString().isNotEmpty ? " ($qty)" : ""}',
                    style: GoogleFonts.sora(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                );
              }),
              if (items.length > 3)
                Text(
                  '+${items.length - 3} أصناف أخرى',
                  style: GoogleFonts.sora(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
            if (!isExpired) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onReject,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.error.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.error.withAlpha(60),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'رفض',
                            style: GoogleFonts.sora(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onApprove,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldPrimary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'موافقة',
                            style: GoogleFonts.sora(
                              color: AppTheme.backgroundDeep,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

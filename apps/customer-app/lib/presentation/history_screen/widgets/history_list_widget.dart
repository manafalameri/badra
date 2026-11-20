import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/pdf_generator.dart';
import '../../../data/mock_transactions.dart';
import '../../../theme/app_theme.dart';
import './transaction_receipt_screen.dart';

class HistoryListWidget extends StatefulWidget {
  final List<Map<String, dynamic>> transactions;

  const HistoryListWidget({super.key, required this.transactions});

  @override
  State<HistoryListWidget> createState() => _HistoryListWidgetState();
}

class _HistoryListWidgetState extends State<HistoryListWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void didUpdateWidget(HistoryListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transactions != widget.transactions) {
      _entranceController.reset();
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.25,
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد معاملات',
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'لا توجد عمليات في هذه الفئة',
                  style: GoogleFonts.sora(fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: widget.transactions.length,
      itemBuilder: (context, i) {
        final tx = widget.transactions[i];
        final delay = (i * 0.05).clamp(0.0, 0.8);
        final end = (delay + 0.35).clamp(0.0, 1.0);

        final animation = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(delay, end, curve: Curves.easeOutCubic),
        );

        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, 24 * (1 - animation.value)),
              child: Opacity(opacity: animation.value, child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryTile(
              transaction: tx,
              onViewDetails: () => _showDetailSheet(context, tx),
              onDownload: () => _showReceipt(context, tx),
            ),
          ),
        );
      },
    );
  }

  void _showDetailSheet(BuildContext context, Map<String, dynamic> tx) {
    final model = _toTransactionModel(tx);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionReceiptScreen(transaction: model),
      ),
    );
  }

  void _showReceipt(BuildContext context, Map<String, dynamic> tx) {
    // ignore: avoid_print
    print('=== Generating PDF for: ${tx['ref']} ===');
    PdfGenerator.generateReceipt(tx);
  }

  TransactionModel _toTransactionModel(Map<String, dynamic> tx) {
    final normalized = Map<String, dynamic>.from(tx);
    normalized['date'] = _rawDateToString(normalized['date']);
    normalized['type'] =
        normalized['type']?.toString().toLowerCase() ?? 'outgoing';
    normalized['status'] = _rawStatusToString(normalized['status']);
    normalized['creditor'] =
        normalized['creditor']?.toString() ??
        normalized['store']?.toString() ??
        '';
    normalized['debtor'] = normalized['debtor']?.toString() ?? '';
    normalized['notes'] = normalized['notes']?.toString() ?? '';
    normalized['title'] =
        normalized['title']?.toString() ??
        normalized['store']?.toString() ??
        'عملية';
    normalized['id'] = normalized['id']?.toString() ?? '';
    normalized['ref'] = normalized['ref']?.toString() ?? '';
    normalized['short_ref'] = normalized['short_ref']?.toString() ?? '';
    normalized['amount'] = _parseAmount(normalized['amount']);
    if (normalized['original_amount'] != null) {
      normalized['original_amount'] = _parseAmount(normalized['original_amount']);
    }
    if (normalized['discount_amount'] != null) {
      normalized['discount_amount'] = _parseAmount(normalized['discount_amount']);
    }
    return TransactionModel.fromMap(normalized);
  }

  String _rawDateToString(Object? raw) {
    if (raw is DateTime) return raw.toIso8601String();
    if (raw is String && raw.isNotEmpty) return raw;
    return DateTime.now().toIso8601String();
  }

  String _rawStatusToString(Object? raw) {
    final status = raw?.toString().toLowerCase() ?? 'completed';
    if (status == 'مكتملة' || status == 'completed') return 'completed';
    if (status == 'pending' || status == 'معلقة') return 'pending';
    if (status == 'failed' || status == 'فشلت') return 'failed';
    return 'completed';
  }

  double _parseAmount(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final VoidCallback onViewDetails;
  final VoidCallback onDownload;

  const _HistoryTile({
    required this.transaction,
    required this.onViewDetails,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isIncoming = _isIncoming(transaction);
    final isFailed =
        _statusFromString(transaction['status']?.toString() ?? 'completed') ==
        TxStatus.failed;
    final type = _typeFromString(transaction['type']?.toString() ?? 'outgoing');
    final date = _formatArabicDate(
      _parseDate(transaction['date']?.toString() ?? ''),
    );
    final title =
        transaction['title']?.toString() ??
        transaction['store']?.toString() ??
        'عملية';
    final amount = _formatAmount(transaction['amount']);
    final status = _statusFromString(
      transaction['status']?.toString() ?? 'completed',
    );

    Color amountColor;
    if (isFailed) {
      amountColor = AppTheme.error;
    } else if (isIncoming) {
      amountColor = AppTheme.incoming;
    } else {
      amountColor = AppTheme.outgoing;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onViewDetails,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard.withAlpha(153),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFailed
                    ? AppTheme.error.withAlpha(51)
                    : AppTheme.emeraldPrimary.withAlpha(26),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TypeIcon(type: type, isFailed: isFailed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              date,
                              style: GoogleFonts.sora(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusDot(status: status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '${isIncoming ? '+' : '-'}$amount',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: GoogleFonts.sora(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: amountColor,
                                fontFeatures: [
                                  const FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ActionButton(
                                icon: Icons.info_outline_rounded,
                                color: AppTheme.emeraldPrimary,
                                tooltip: 'رؤية التفاصيل',
                                onTap: onViewDetails,
                              ),
                              const SizedBox(width: 6),
                              _ActionButton(
                                icon: Icons.file_download_outlined,
                                color: AppTheme.goldAccent,
                                tooltip: 'تحميل الكشف',
                                onTap: onDownload,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isIncoming(Map<String, dynamic> tx) {
    final type = tx['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty) {
      return type == 'deposit' || type == 'incoming';
    }
    final isIn = tx['is_in'];
    if (isIn is int) return isIn == 1;
    if (isIn is String) return isIn == '1';
    return false;
  }

  double _parseAmount(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }

  String _formatAmount(Object? value) {
    final amount = _parseAmount(value);
    return amount.toStringAsFixed(0);
  }

  DateTime _parseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      try {
        final parts = value.split(' ');
        if (parts.isNotEmpty) return DateTime.parse(parts[0]);
      } catch (_) {}
    }
    return DateTime.now();
  }

  String _formatArabicDate(DateTime d) {
    final months = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  TransactionType _typeFromString(String type) {
    final normalized = type.toLowerCase();
    switch (normalized) {
      case 'deposit':
      case 'incoming':
        return TransactionType.incoming;
      case 'withdraw':
      case 'withdrawal':
      case 'outgoing':
        return TransactionType.outgoing;
      case 'service':
        return TransactionType.service;
      default:
        return TransactionType.outgoing;
    }
  }

  TxStatus _statusFromString(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'completed':
      case 'مكتملة':
        return TxStatus.completed;
      case 'pending':
      case 'معلقة':
        return TxStatus.pending;
      case 'failed':
      case 'فشلت':
        return TxStatus.failed;
      default:
        return TxStatus.completed;
    }
  }
}

class _TypeIcon extends StatelessWidget {
  final TransactionType type;
  final bool isFailed;

  const _TypeIcon({required this.type, required this.isFailed});

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTheme.error.withAlpha(31),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
        ),
        child: const Icon(
          Icons.error_outline_rounded,
          size: 20,
          color: AppTheme.error,
        ),
      );
    }

    IconData icon;
    Color color;
    Color bg;

    switch (type) {
      case TransactionType.incoming:
        icon = Icons.south_west_rounded;
        color = AppTheme.incoming;
        bg = AppTheme.incoming.withAlpha(26);
        break;
      case TransactionType.outgoing:
        icon = Icons.north_east_rounded;
        color = AppTheme.textSecondary;
        bg = AppTheme.textSecondary.withAlpha(20);
        break;
      case TransactionType.service:
        icon = Icons.swap_horiz_rounded;
        color = AppTheme.goldAccent;
        bg = AppTheme.goldAccent.withAlpha(26);
        break;
    }

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(51), width: 1),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final TxStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case TxStatus.completed:
        color = AppTheme.success;
        label = 'مكتملة';
        break;
      case TxStatus.pending:
        color = AppTheme.warning;
        label = 'معلقة';
        break;
      case TxStatus.failed:
        color = AppTheme.error;
        label = 'فشلت';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withAlpha(128), blurRadius: 3)],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(64), width: 1),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

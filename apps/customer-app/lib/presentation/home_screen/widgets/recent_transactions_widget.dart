import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/supabase_service.dart';
import '../../../theme/app_theme.dart';
import '../../../data/mock_transactions.dart';

class RecentTransactionsWidget extends StatefulWidget {
  final VoidCallback? onViewAll;

  const RecentTransactionsWidget({super.key, this.onViewAll});

  @override
  State<RecentTransactionsWidget> createState() =>
      _RecentTransactionsWidgetState();
}

class _RecentTransactionsWidgetState extends State<RecentTransactionsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  final List<Animation<double>> _itemAnimations = [];
  late Future<List<TransactionModel>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _transactionsFuture = SupabaseService.getMyTransactionsFast().then(
      (data) => data.map(TransactionModel.fromFlexibleMap).toList(),
    );

    _transactionsFuture.then((transactions) {
      for (int i = 0; i < transactions.length; i++) {
        final start = (i * 0.12).clamp(0.0, 1.0);
        final end = (start + 0.4).clamp(0.0, 1.0);
        _itemAnimations.add(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
      }
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _entranceController.forward();
      });
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TransactionModel>>(
      future: _transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Center(child: Text('No transactions found')),
          );
        } else {
          final recent = snapshot.data!.take(5).toList();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'سجل العمليات',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'آخر ٥ عمليات',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...recent.asMap().entries.map((entry) {
                  final i = entry.key;
                  final tx = entry.value;
                  return AnimatedBuilder(
                    animation: _itemAnimations[i],
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - _itemAnimations[i].value)),
                        child: Opacity(
                          opacity: _itemAnimations[i].value,
                          child: child,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TransactionTile(transaction: tx),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                _buildViewAllButton(),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildViewAllButton() {
    return GestureDetector(
      onTap: widget.onViewAll,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard.withAlpha(102),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(64),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'عرض السجل الكامل',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.emeraldPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: AppTheme.emeraldPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIncoming = transaction.type == TransactionType.incoming;
    final isFailed = transaction.status == TxStatus.failed;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(140),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(26),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              _TransactionIcon(type: transaction.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.title,
                      style: GoogleFonts.sora(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      transaction.formattedDate,
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncoming ? '+' : '-'} ${transaction.formattedAmount}',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isFailed
                          ? AppTheme.error
                          : isIncoming
                          ? AppTheme.incoming
                          : AppTheme.outgoing,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ر.ي',
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionIcon extends StatelessWidget {
  final TransactionType type;
  const _TransactionIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    Color bg;

    switch (type) {
      case TransactionType.incoming:
        icon = Icons.arrow_downward_rounded;
        color = AppTheme.incoming;
        bg = AppTheme.incoming.withAlpha(31);
        break;
      case TransactionType.outgoing:
        icon = Icons.arrow_upward_rounded;
        color = AppTheme.textSecondary;
        bg = AppTheme.textSecondary.withAlpha(26);
        break;
      case TransactionType.service:
        icon = Icons.sync_alt_rounded;
        color = AppTheme.goldAccent;
        bg = AppTheme.goldAccent.withAlpha(26);
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(64), width: 1),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

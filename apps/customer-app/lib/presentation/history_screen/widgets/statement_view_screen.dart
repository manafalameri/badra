import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/string_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/badra_luxury_toast.dart';

class StatementViewScreen extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final String? customerName;
  final String? walletId;

  const StatementViewScreen({
    super.key,
    required this.transactions,
    this.customerName,
    this.walletId,
  });

  String _formatFullDate(DateTime date) {
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
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}\n$h:$m';
  }

  double get _totalIncoming => transactions.fold(0.0, (sum, t) {
    final amount = _parseAmount(t['amount']);
    final isIncoming =
        (t['is_in'] == 1) || t['type']?.toString().toLowerCase() == 'deposit';
    return isIncoming ? sum + amount : sum;
  });

  double get _totalOutgoing => transactions.fold(0.0, (sum, t) {
    final amount = _parseAmount(t['amount']);
    final isIncoming =
        (t['is_in'] == 1) || t['type']?.toString().toLowerCase() == 'deposit';
    return isIncoming ? sum : sum + amount;
  });

  double _parseAmount(Object? amount) {
    if (amount is num) {
      return amount.toDouble();
    }
    if (amount is String) {
      return double.tryParse(amount.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }

  DateTime _parseDate(Object? date) {
    if (date is DateTime) {
      return date;
    }
    if (date is String) {
      return DateTime.tryParse(date) ?? DateTime.now();
    }
    return DateTime.now();
  }

  String _formatNumber(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
    final statementDate = '${now.day} ${months[now.month - 1]} ${now.year}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDeep,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      _buildStatementHeader(statementDate),
                      const SizedBox(height: 16),
                      _buildSummaryRow(),
                      const SizedBox(height: 20),
                      _buildTableHeader(),
                      ...transactions.asMap().entries.map(
                        (e) => _buildTableRow(e.value, e.key.isEven),
                      ),
                      const SizedBox(height: 16),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundMid,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.emeraldPrimary.withAlpha(40),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.emeraldMuted.withAlpha(60),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.textSecondary,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'كشف الحساب',
              style: GoogleFonts.sora(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              BadraLuxuryToast.show(
                context,
                'تم النسخ',
                type: BadraToastType.success,
                duration: const Duration(seconds: 2),
              );
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.emeraldGlow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.emeraldPrimary.withAlpha(60),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.share_rounded,
                color: AppTheme.emeraldPrimary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementHeader(String statementDate) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF0D2A1A), Color(0xFF0A1510)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(50),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'بذرة',
                          style: GoogleFonts.sora(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.emeraldPrimary,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'المحفظة الإلكترونية',
                          style: GoogleFonts.sora(
                            fontSize: 12,
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
                        'كشف حساب',
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.goldAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statementDate,
                        style: GoogleFonts.sora(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 1,
                color: AppTheme.emeraldPrimary.withAlpha(30),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildHeaderInfo('اسم العميل', customerName?.isNotEmpty == true ? customerName! : '—'),
                  ),
                  Expanded(
                    child: _buildHeaderInfo('رقم الحساب', walletId?.isNotEmpty == true ? walletId! : '—'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildHeaderInfo(
                      'إجمالي العمليات',
                      '${transactions.length} عملية',
                    ),
                  ),
                  Expanded(child: _buildHeaderInfo('حالة الحساب', 'نشط ✓')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.sora(fontSize: 10, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            label: 'إجمالي الوارد',
            amount: _formatNumber(_totalIncoming),
            color: AppTheme.incoming,
            icon: Icons.arrow_downward_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            label: 'إجمالي الصادر',
            amount: _formatNumber(_totalOutgoing),
            color: AppTheme.error,
            icon: Icons.arrow_upward_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(50), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
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
                  amount,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.emeraldDark.withAlpha(180),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(
          color: AppTheme.emeraldPrimary.withAlpha(40),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'اسم المتجر / الجهة',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.emeraldPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'التاريخ',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.emeraldPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المبلغ',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.emeraldPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              'النوع',
              style: GoogleFonts.sora(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.emeraldPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> tx, bool isEven) {
    final isIncoming =
        (tx['is_in'] == 1) || tx['type']?.toString().toLowerCase() == 'deposit';
    final status = tx['status']?.toString().toLowerCase() ?? '';
    final isFailed = status == 'failed' || status == 'فاشلة';

    Color amountColor;
    if (isFailed) {
      amountColor = AppTheme.error;
    } else if (isIncoming) {
      amountColor = AppTheme.incoming;
    } else {
      amountColor = AppTheme.outgoing;
    }

    final typeLabel = isIncoming ? 'دائن' : 'مدين';
    final typeColor = isIncoming ? AppTheme.incoming : AppTheme.error;
    final title = tx['store']?.toString() ?? tx['ref']?.toString() ?? 'معاملة';
    final date = _parseDate(tx['date']);
    final amount = _parseAmount(tx['amount']);
    final notes = tx['notes']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isEven
            ? AppTheme.surfaceCard.withAlpha(120)
            : AppTheme.backgroundMid.withAlpha(180),
        border: Border(
          left: BorderSide(
            color: AppTheme.emeraldPrimary.withAlpha(20),
            width: 1,
          ),
          right: BorderSide(
            color: AppTheme.emeraldPrimary.withAlpha(20),
            width: 1,
          ),
          bottom: BorderSide(
            color: AppTheme.emeraldPrimary.withAlpha(15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatFullDate(date),
                  style: GoogleFonts.sora(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${isIncoming ? '+' : '-'}${_formatNumber(amount)}',
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: typeColor.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    typeLabel,
                    style: GoogleFonts.sora(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'ملاحظة: ${notes.toLatinDigits()}',
              style: GoogleFonts.sora(
                fontSize: 10,
                color: AppTheme.textMuted,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withAlpha(120),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border.all(
          color: AppTheme.emeraldPrimary.withAlpha(30),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'صافي الرصيد:',
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                _formatNumber(_totalIncoming - _totalOutgoing),
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: (_totalIncoming - _totalOutgoing) >= 0
                      ? AppTheme.incoming
                      : AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppTheme.emeraldPrimary.withAlpha(25)),
          const SizedBox(height: 12),
          Text(
            'هذا الكشف صادر من تطبيق بذرة.\nجميع المعاملات موثقة ومحفوظة بشكل آمن.',
            style: GoogleFonts.sora(
              fontSize: 10,
              color: AppTheme.textMuted,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

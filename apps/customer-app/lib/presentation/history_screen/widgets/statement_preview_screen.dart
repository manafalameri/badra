import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/pdf_generator.dart';
import '../../../theme/app_theme.dart';

class StatementPreviewScreen extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final DateTime fromDate;
  final DateTime toDate;

  const StatementPreviewScreen({
    super.key,
    required this.transactions,
    required this.fromDate,
    required this.toDate,
  });

  void _downloadPdf() {
    PdfGenerator.generateStatementPdfFromMaps(transactions, fromDate, toDate);
  }

  String _formatDate(Map<String, dynamic> tx) {
    final createdAt = tx['date'];
    if (createdAt is DateTime) {
      return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    }
    if (createdAt is String) {
      return DateTime.parse(createdAt).toString().split(' ')[0];
    }
    return '';
  }

  bool _isIncoming(Map<String, dynamic> tx) {
    final type = (tx['type'] as String?)?.toLowerCase();
    if (type != null && type.isNotEmpty) {
      return type == 'deposit' || type == 'incoming';
    }
    final isIn = tx['is_in'];
    if (isIn is int) return isIn == 1;
    if (isIn is String) return isIn == '1';
    return false;
  }

  String _formatAmount(Map<String, dynamic> tx) {
    final amountStr = tx['amount'] as String? ?? '0';
    final amount = double.tryParse(amountStr) ?? 0.0;
    return amount.toStringAsFixed(0);
  }

  String _getTitle(Map<String, dynamic> tx) {
    return tx['store']?.toString() ?? tx['ref']?.toString() ?? 'عملية';
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
          iconTheme: IconThemeData(color: AppTheme.textPrimary),
          title: Text(
            'معاينة الكشف',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'من ${fromDate.toString().split(' ')[0]} إلى ${toDate.toString().split(' ')[0]}',
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isIncoming = _isIncoming(tx);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getTitle(tx),
                                  style: GoogleFonts.sora(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(tx),
                                  style: GoogleFonts.sora(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isIncoming ? '+' : '-'}${_formatAmount(tx)}',
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isIncoming
                                  ? AppTheme.incoming
                                  : AppTheme.outgoing,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _downloadPdf,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      'تحميل ومشاركة PDF',
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emeraldPrimary,
                      foregroundColor: AppTheme.backgroundDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

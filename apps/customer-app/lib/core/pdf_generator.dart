// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  static Future<pw.Font> _loadTajawal() async {
    try {
      final data = await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      return pw.Font.helvetica();
    }
  }

  static String _formatDateOnly(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt != null)
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return raw.split(' ').first;
  }

  static bool _isIncoming(Map<String, dynamic> tx) {
    final type = tx['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty) {
      return type == 'deposit' || type == 'incoming';
    }
    final isIn = tx['is_in'];
    if (isIn is int) return isIn == 1;
    if (isIn is String) return isIn == '1';
    return false;
  }

  static String _numberToArabicWords(int number) {
    if (number == 0) return 'صفر';
    final units = [
      '',
      'واحد',
      'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
    ];
    final teens = [
      'عشرة',
      'أحد عشر',
      'اثنا عشر',
      'ثلاثة عشر',
      'أربعة عشر',
      'خمسة عشر',
      'ستة عشر',
      'سبعة عشر',
      'ثمانية عشر',
      'تسعة عشر',
    ];
    final tens = [
      '',
      '',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون',
    ];
    final hundreds = [
      '',
      'مائة',
      'مائتان',
      'ثلاثمائة',
      'أربعمائة',
      'خمسمائة',
      'ستمائة',
      'سبعمائة',
      'ثمانمائة',
      'تسعمائة',
    ];

    String res = '';
    if (number >= 1000) {
      final th = number ~/ 1000;
      if (th == 1)
        res += 'ألف';
      else if (th == 2)
        res += 'ألفان';
      else if (th < 10)
        res += '${units[th]} آلاف';
      else if (th == 10)
        res += 'عشرة آلاف';
      else
        res += '${_numberToArabicWords(th)} ألف';
      number %= 1000;
      if (number > 0) res += ' و ';
    }
    if (number >= 100) {
      res += hundreds[number ~/ 100];
      number %= 100;
      if (number > 0) res += ' و ';
    }
    if (number >= 20) {
      res += tens[number ~/ 10];
      number %= 10;
      if (number > 0) res += ' و ';
    } else if (number >= 10) {
      res += teens[number - 10];
      number = 0;
    }
    if (number > 0) res += units[number];
    return res;
  }

  static Future<void> generateReceipt(Map<String, dynamic> transaction) async {
    print('=== PDF: START ===');
    try {
      final ttf = await _loadTajawal();

      final ref = transaction['ref']?.toString() ?? '';
      final date = _formatDateOnly(transaction['date']?.toString() ?? '');
      final amount =
          (double.tryParse(transaction['amount']?.toString() ?? '0') ?? 0.0);
      final amountWords = _numberToArabicWords(amount.round());
      final isIncoming = _isIncoming(transaction);
      final receiptLabel = isIncoming ? 'سند شحن' : 'سند دفع';
      
      // Use debtor/creditor from transaction data (now properly populated from DB)
      final fromAccount = transaction['debtor']?.toString().isNotEmpty == true
          ? transaction['debtor']!.toString()
          : (isIncoming ? 'البنك/الطرف المرسل' : 'محفظة العميل');
      final toAccount = transaction['creditor']?.toString().isNotEmpty == true
          ? transaction['creditor']!.toString()
          : (isIncoming ? 'محفظة العميل' : transaction['store']?.toString() ?? 'التاجر/الطرف المستلم');

      pw.MemoryImage? logo;
      try {
        final data = await rootBundle.load('assets/images/img_app_logo.png');
        logo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5.landscape,
          margin: pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // === رأس السند حسب التصميم المطلوب ===
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        receiptLabel,
                        style: pw.TextStyle(
                          font: ttf,
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            'بذرة',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 32,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '"حصن أمين.. لراحة تبين"',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 11,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      logo != null
                          ? pw.Image(logo, width: 60, height: 60)
                          : pw.SizedBox(width: 60, height: 60),
                    ],
                  ),

                  pw.SizedBox(height: 8),
                  pw.Divider(thickness: 2),

                  pw.SizedBox(height: 16),

                  // === رقم العملية والتاريخ ===
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'رقم العملية:',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.Text(
                            ref,
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'التاريخ:',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.Text(
                            date,
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 16),

                  // === مستطيل المبلغ ===
                  pw.Container(
                    height: 60,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 1),
                    ),
                    child: pw.Row(
                      children: [
                        // النصف الأيسر (خلفية سوداء)
                        pw.Expanded(
                          child: pw.Container(
                            color: PdfColors.black,
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              'ريال ${amount.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                font: ttf,
                                color: PdfColors.white,
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // النصف الأيمن (خلفية بيضاء)
                        pw.Expanded(
                          child: pw.Container(
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              '$amountWords ريال يمني لا غير',
                              style: pw.TextStyle(font: ttf, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 16),

                  // === من/إلى حساب ===
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'من حساب:',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.Text(
                            fromAccount,
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'إلى حساب:',
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 12,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.Text(
                            toAccount,
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.Spacer(),

                  pw.Divider(thickness: 1),

                  // === الموقع ===
                  pw.Center(
                    child: pw.Text(
                      'الجمهورية اليمنية | حضرموت | سيئون',
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: 12,
                        color: PdfColors.grey400,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.sharePdf(bytes: await pdf.save(), filename: 'receipt.pdf');
      print('=== PDF: Built ===');
    } catch (e, st) {
      print('PDF ERROR: $e');
      print(st);
    }
  }

  static Future<void> generateStatementPdfFromMaps(
    List<Map<String, dynamic>> transactions,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    try {
      final ttf = await _loadTajawal();

      String fmt(Map<String, dynamic> tx) {
        final createdAt = tx['date'];
        if (createdAt is DateTime)
          return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
        if (createdAt is String)
          return DateTime.tryParse(createdAt)?.toString().split(' ')[0] ??
              createdAt.split(' ').first;
        return '';
      }

      final data = transactions
          .map(
            (t) => [
              fmt(t),
              t['store'] ?? t['ref'] ?? '',
              (double.tryParse(t['amount']?.toString() ?? '0') ?? 0)
                  .toStringAsFixed(0),
              (t['type'] ?? '').toString(),
            ],
          )
          .toList();
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(24),
          build: (c) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'كشف الحساب',
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'من ${fromDate.toString().split(' ')[0]} إلى ${toDate.toString().split(' ')[0]}',
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 12,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    headers: ['التاريخ', 'الوصف', 'المبلغ', 'النوع'],
                    data: data,
                    headerStyle: pw.TextStyle(
                      font: ttf,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
                    cellAlignment: pw.Alignment.centerRight,
                    headerAlignment: pw.Alignment.centerRight,
                  ),
                ],
              ),
            );
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'statement.pdf',
      );
    } catch (e, st) {
      print('Statement ERROR: $e');
      print(st);
    }
  }
}

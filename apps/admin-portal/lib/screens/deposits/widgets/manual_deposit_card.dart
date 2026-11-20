import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../services/supabase_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/app_theme.dart';

/// منسق إدخال المبالغ المالية: يضع فواصل الآلاف لحظياً أثناء الكتابة
/// ويقوم بتحويل الأرقام العربية/الهندية إلى لاتينية تلقائياً
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat('#,###', 'en');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String text = newValue.text;
    const arabicDigits = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    arabicDigits.forEach((ar, en) {
      text = text.replaceAll(ar, en);
    });

    final cleanDigits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final number = int.tryParse(cleanDigits);
    if (number == null) {
      return oldValue;
    }

    final formatted = _formatter.format(number);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// منسق إدخال رقم الجوال: يحصر الإدخال في 9 أرقام محلية يمنية
/// وإذا تم لصق رقم يبدأ بـ 967 أو +967 يستخرج الـ 9 أرقام فوراً
class PhoneNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    const arabicDigits = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    arabicDigits.forEach((ar, en) {
      text = text.replaceAll(ar, en);
    });

    String digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('967') && digits.length > 9) {
      digits = digits.substring(3);
    }
    if (digits.length > 9) {
      digits = digits.substring(0, 9);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class ManualDepositCard extends StatefulWidget {
  final List<Map<String, dynamic>>? existingRecords;
  final VoidCallback? onSuccess;

  const ManualDepositCard({
    super.key,
    this.existingRecords,
    this.onSuccess,
  });

  @override
  State<ManualDepositCard> createState() => _ManualDepositCardState();
}

class _ManualDepositCardState extends State<ManualDepositCard> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _receiptController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedBank = 'العمقي';
  bool _isSubmitting = false;

  /// حالة جلب البيانات من سوبابيز بالرقم
  bool _isSearchingSupabase = false;

  /// بيانات العميل المؤكدة المسترجعة مباشرة من سوبابيز
  Map<String, dynamic>? _serverVerifiedProfile;

  /// رسالة التنبيه عند عدم العثور على الحساب
  String? _searchError;

  /// رقم المحفظة المشتق رياضياً من رقم الجوال (101967 + 9 أرقام)
  String _derivedWalletId = '';

  /// اسم العميل في حال العثور عليه في الفهرس المحلي
  String? _matchedUserName;

  /// فهرس الذاكرة المحلية: مفتاح: 9 أرقام الجوال -> القيمة: اسم العميل
  final Map<String, String> _localPhoneDirectory = {};

  /// قائمة مستخدمي الفهرس المحلي للاقتراحات
  final List<Map<String, String>> _localUsersList = [];

  final List<String> _banks = ['العمقي', 'الكرايمي', 'القطيبي', 'البسيري'];

  @override
  void initState() {
    super.initState();
    _buildLocalDirectory();
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void didUpdateWidget(covariant ManualDepositCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.existingRecords != widget.existingRecords) {
      _buildLocalDirectory();
    }
  }

  /// بناء الفهرس المحلي في الذاكرة من السجلات المحملة مسبقاً (Zero Network Cost)
  void _buildLocalDirectory() {
    _localPhoneDirectory.clear();
    _localUsersList.clear();
    final seen = <String>{};

    if (widget.existingRecords != null) {
      for (final r in widget.existingRecords!) {
        final name = (r['user_name'] ?? '').toString().trim();
        final rawPhone = (r['user_phone'] ?? '').toString();
        final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');

        if (name.isNotEmpty && digits.isNotEmpty) {
          final local9 = digits.length >= 9
              ? digits.substring(digits.length - 9)
              : digits;

          _localPhoneDirectory[local9] = name;

          if (!seen.contains(local9)) {
            seen.add(local9);
            _localUsersList.add({
              'name': name,
              'phone': local9,
              'wallet': '101967$local9',
            });
          }
        }
      }
    }
  }

  /// معالجة تغير رقم الجوال: اشتقاق المحفظة والبحث المحلي الفوري عن الاسم
  void _onPhoneChanged() {
    final digits = _phoneController.text.trim();

    if (digits.isEmpty) {
      if (_derivedWalletId.isNotEmpty ||
          _matchedUserName != null ||
          _serverVerifiedProfile != null) {
        setState(() {
          _derivedWalletId = '';
          _matchedUserName = null;
          _serverVerifiedProfile = null;
          _searchError = null;
        });
      }
      return;
    }

    final newWalletId = '101967$digits';
    String? matched;

    if (digits.length == 9) {
      matched = _localPhoneDirectory[digits];
      if (matched != null && matched.isNotEmpty) {
        // إذا كان حقل الاسم فارغاً أو مسجلاً بالاسم المطابق السابق، نحدثه
        if (_nameController.text.isEmpty ||
            _nameController.text == _matchedUserName) {
          _nameController.text = matched;
        }
      }
    }

    setState(() {
      _derivedWalletId = newWalletId;
      _matchedUserName = matched;
      if (_serverVerifiedProfile != null &&
          !_serverVerifiedProfile!['phone'].toString().contains(digits)) {
        _serverVerifiedProfile = null;
        _searchError = null;
      }
    });
  }

  /// البحث المباشر في سوبابيز بواسطة رقم الجوال أو المحفظة
  Future<void> _searchUserInSupabase() async {
    final digits = _phoneController.text.trim();
    if (digits.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة رقم الجوال كاملاً (9 أرقام) للبحث',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.warning,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSearchingSupabase = true;
      _searchError = null;
    });

    try {
      final profile = await SupabaseService.findProfileByPhoneOrWallet(digits);
      if (!mounted) return;

      if (profile != null) {
        final serverName = profile['name']?.toString() ?? '';
        final serverWallet =
            profile['wallet_id']?.toString() ?? '101967$digits';

        setState(() {
          _serverVerifiedProfile = profile;
          _nameController.text = serverName;
          _derivedWalletId = serverWallet;
          _matchedUserName = serverName;
          _searchError = null;
        });

        if (profile['is_in_cooldown'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '⛔ تنبيه أمني: العميل في فترة تهدئة (12 ساعة)! ${profile['cooldown_text'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ تم العثور على العميل: $serverName',
                  style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // فحص الفهرس المحلي كبديل
        final localMatched = _localPhoneDirectory[digits];
        if (localMatched != null) {
          setState(() {
            _nameController.text = localMatched;
            _matchedUserName = localMatched;
            _searchError =
                'تم العثور عليه في السجلات السابقة (غير مجلوب من سوبابيز)';
          });
        } else {
          setState(() {
            _searchError =
                'لم يتم العثور على مستخدم مسجل برقم $digits في سوبابيز';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searchError = 'خطأ أثناء البحث: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingSupabase = false);
      }
    }
  }

  /// إضافة سريعة للمبلغ
  void _addQuickAmount(int value) {
    final clean = _amountController.text.replaceAll(',', '').trim();
    final current = int.tryParse(clean) ?? 0;
    final updated = current + value;
    final formatted = NumberFormat('#,###', 'en').format(updated);
    _amountController.text = formatted;
    setState(() {});
  }

  /// خطوة التأكيد الاستباقية قبل التحويل
  Future<void> _handleProceed() async {
    if (!_formKey.currentState!.validate()) return;

    // فحص استباقي لمنع الإيداع أثناء فترة التهدئة (12 ساعة)
    if (_serverVerifiedProfile?['is_in_cooldown'] == true) {
      _showErrorDialog(
          'حظر أمني مطلق: لا يمكن تنفيذ أي إيداع لهذا الحساب قبل مرور 12 ساعة كاملة من آخر إيداع.\n\nالوقت المتبقي: ${_serverVerifiedProfile!['cooldown_text'] ?? ''}');
      return;
    }

    final phone = _phoneController.text.trim();
    final walletId = _derivedWalletId;
    final name = _nameController.text.trim();
    final amountText = _amountController.text.trim();
    final receipt = _receiptController.text.trim();
    final cleanReceipt = receipt.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final notes = _notesController.text.trim();

    // فحص استباقي لمنع تكرار السند في السجلات المحملة لنفس البنك
    if (widget.existingRecords != null) {
      final isDuplicate = widget.existingRecords!.any((r) {
        final rBank = (r['bank_name'] ?? '').toString().trim();
        final rReceipt = (r['receipt_number'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\s+'), '')
            .toUpperCase();
        return rBank == _selectedBank &&
            rReceipt == cleanReceipt &&
            cleanReceipt.isNotEmpty;
      });

      if (isDuplicate) {
        _showErrorDialog(
            'تنبيه أمني: رقم السند البنكي ($cleanReceipt) مسجل مسبقاً لدى بنك $_selectedBank!\n\nتم إيقاف العملية فوراً لمنع تكرار الإيداع.');
        return;
      }
    }

    // إظهار نافذة التأكيد الاستباقية للمراجعة الدقيقة
    final confirmed = await _showPreConfirmationDialog(
      amount: amountText,
      name: name,
      phone: phone,
      walletId: walletId,
      bank: _selectedBank,
      receiptNumber: cleanReceipt,
      notes: notes,
    );

    if (confirmed != true || !mounted) return;

    // التحقق بالبصمة البيومترية قبل الإيداع
    final ok = await AuthService.authenticateWithBiometrics(
      'تحقق من هويتك لتأكيد الإيداع اليدوي',
    );
    if (!ok || !mounted) return;

    // البدء في الإرسال وقفل الزر ضد النقر المتكرر
    setState(() => _isSubmitting = true);

    try {
      final cleanAmount = double.parse(amountText.replaceAll(',', ''));

      // استخدام القيم الدقيقة المجلوبة من السيرفر مباشرة إن وجدت
      final sendWallet =
          _serverVerifiedProfile?['wallet_id']?.toString() ?? walletId;
      final sendPhone =
          _serverVerifiedProfile?['phone']?.toString() ?? '+967$phone';
      final sendName =
          _serverVerifiedProfile?['name']?.toString() ?? name;

      final result = await SupabaseService.manualDeposit(
        amount: cleanAmount,
        bankName: _selectedBank,
        walletId: sendWallet,
        phone: sendPhone,
        name: sendName,
        receiptNumber: cleanReceipt,
        notes: notes,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // تحديث الفهرس المحلي في الذاكرة فوراً ليتذكر هذا المستخدم
        _localPhoneDirectory[phone] = name;
        _localUsersList.insert(0, {
          'name': name,
          'phone': phone,
          'wallet': walletId,
        });

        _showSuccessDialog(result);

        // مسح الحقول بعد النجاح
        _phoneController.clear();
        _nameController.clear();
        _amountController.clear();
        _receiptController.clear();
        _notesController.clear();
        setState(() {
          _derivedWalletId = '';
          _matchedUserName = null;
        });

        widget.onSuccess?.call();
      } else {
        _showErrorDialog(result['message'] ?? 'فشل الإيداع');
      }
    } catch (e) {
      if (mounted) _showErrorDialog(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// نافذة المراجعة والتأكيد الاستباقية الشاملة
  Future<bool?> _showPreConfirmationDialog({
    required String amount,
    required String name,
    required String phone,
    required String walletId,
    required String bank,
    required String receiptNumber,
    required String notes,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_user_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 10),
            const Text(
              'تأكيد تفاصيل الإيداع',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              // بطاقة عرض المبلغ المميزة
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text(
                      'المبلغ المراد إيداعه',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$amount ﷼',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // جدول مراجعة البيانات
              _confirmDetailRow('المستفيد:', name, isBold: true),
              _confirmDetailRow('رقم الجوال:', '+967 $phone'),
              _confirmDetailRow('رقم المحفظة:', walletId),
              _confirmDetailRow('البنك المحول منه:', bank),
              _confirmDetailRow('رقم السند البنكي:', receiptNumber,
                  isHighlight: true),
              if (notes.isNotEmpty) _confirmDetailRow('ملاحظات:', notes),

              const SizedBox(height: 14),

              // تنبيه أمني
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'يرجى مطابقة رقم السند وبيانات العميل، سيتم إيداع الرصيد مباشرة ولا يمكن التراجع.',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('إلغاء',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('تأكيد الإيداع',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confirmDetailRow(String label, String value,
      {bool isBold = false, bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: isHighlight ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    final format = NumberFormat('#,###', 'en');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('تم الإيداع بنجاح',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultRow('المبلغ', '${format.format(result['amount'])} ﷼'),
            _resultRow(
                'الرصيد القديم', '${format.format(result['old_balance'])} ﷼'),
            _resultRow(
                'الرصيد الجديد', '${format.format(result['new_balance'])} ﷼'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('حسناً',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('خطأ',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(message,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('حسناً',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _receiptController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_card_rounded,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إيداع يدوي',
                        style: AppTextStyles.heading3,
                      ),
                      Text(
                        'شحن رصيد مستخدم وتوثيق السند البنكي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // حقل رقم الجوال مع بادئة +967 الثابتة وزر البحث المباشر في سوبابيز
              TextFormField(
                controller: _phoneController,
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => _searchUserInSupabase(),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  PhoneNumberInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'رقم الجوال *',
                  hintText: '77XXXXXXX',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_android_rounded,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '+967',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSearchingSupabase)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        if (_serverVerifiedProfile != null)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Tooltip(
                              message: 'تم تأكيد الحساب من سوبابيز',
                              child: Icon(Icons.verified_rounded,
                                  color: AppColors.success, size: 20),
                            ),
                          )
                        else if (_matchedUserName != null)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Tooltip(
                              message: 'عميل معروف في السجل',
                              child: Icon(Icons.check_circle_rounded,
                                  color: AppColors.success, size: 20),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded,
                              color: AppColors.primary),
                          tooltip: 'بحث في سوبابيز بالرقم',
                          onPressed: _searchUserInSupabase,
                        ),
                      ],
                    ],
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'رقم الجوال مطلوب';
                  }
                  if (v.trim().length != 9) {
                    return 'يجب أن يتكون رقم الجوال من 9 أرقام (مثال: 771234567)';
                  }
                  return null;
                },
              ),

              // بطاقة بيانات العميل المجلوبة من سوبابيز أو رسالة التنبيه
              if (_serverVerifiedProfile != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '✓ تم جلب بيانات العميل من سوبابيز: ${_serverVerifiedProfile!['name']}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                            Text(
                              'الرصيد: ${_serverVerifiedProfile!['balance']} ﷼ • الهاتف: ${_serverVerifiedProfile!['phone']}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // تنبيه أمني بارز في حال كان الحساب محظوراً بالتهدئة (12 ساعة)
              if (_serverVerifiedProfile?['is_in_cooldown'] == true)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock_rounded,
                          color: AppColors.error, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⛔ حظر أمني مطلق: فترة تهدئة نشطة (12 ساعة)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'تم إيداع رصيد لهذا الحساب مؤخراً. بموجب سياسة الأمان الصارمة، لا يمكن الإيداع لنفس الحساب إلا بعد انقضاء 12 ساعة كاملة.\nالوقت المتبقي: ${_serverVerifiedProfile!['cooldown_text'] ?? ''}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else if (_searchError != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _searchError!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // بطاقة معاينة رقم المحفظة المشتق آلياً (مع زر النسخ)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(top: 8, bottom: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _derivedWalletId.isNotEmpty
                      ? AppColors.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _derivedWalletId.isNotEmpty
                        ? AppColors.divider
                        : Colors.transparent,
                  ),
                ),
                child: _derivedWalletId.isNotEmpty
                    ? Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          const Text(
                            'المحفظة: ',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            _derivedWalletId,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'توليد تلقائي',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: _derivedWalletId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ رقم المحفظة',
                                      style: TextStyle(fontFamily: 'Cairo')),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.copy_rounded,
                                  size: 16, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),

              // حقل الاسم مع الاقتراحات التلقائية من الذاكرة المحلية
              RawAutocomplete<Map<String, String>>(
                textEditingController: _nameController,
                focusNode: FocusNode(),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return const Iterable<Map<String, String>>.empty();
                  }
                  return _localUsersList.where((u) {
                    final n = (u['name'] ?? '').toLowerCase();
                    final p = (u['phone'] ?? '');
                    return n.contains(query) || p.contains(query);
                  });
                },
                displayStringForOption: (option) => option['name'] ?? '',
                onSelected: (Map<String, String> selection) {
                  _nameController.text = selection['name']!;
                  _phoneController.text = selection['phone']!;
                  setState(() {
                    _derivedWalletId = selection['wallet']!;
                    _matchedUserName = selection['name']!;
                  });
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: onEditingComplete,
                    decoration: InputDecoration(
                      labelText: 'اسم العميل *',
                      hintText: 'الاسم الثلاثي أو الرباعي للعميل',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      suffixIcon: _matchedUserName != null
                          ? Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded,
                                      color: AppColors.success, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'مسجل',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'اسم العميل مطلوب' : null,
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        width: MediaQuery.of(context).size.width - 72,
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history_rounded,
                                        size: 18, color: AppColors.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option['name']!,
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'الجوال: +967 ${option['phone']} • المحفظة: ${option['wallet']}',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // حقل المبلغ وحقل البنك
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _amountController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'المبلغ (﷼) *',
                        hintText: '50,000',
                        prefixIcon: Icon(Icons.monetization_on_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'المبلغ مطلوب';
                        }
                        final clean = v.replaceAll(',', '').trim();
                        final amount = double.tryParse(clean);
                        if (amount == null || amount <= 0) {
                          return 'المبلغ غير صالح';
                        }
                        if (amount < 500) {
                          return 'الحد الأدنى للإيداع 500 ريال';
                        }
                        if (amount > 250000) {
                          return 'الحد الأقصى للإيداع 250,000 ريال';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'البنك *',
                        prefixIcon: Icon(Icons.account_balance_rounded),
                      ),
                      items: _banks
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(b,
                                    style:
                                        const TextStyle(fontFamily: 'Cairo')),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedBank = v);
                      },
                    ),
                  ),
                ],
              ),

              // أزرار المبالغ السريعة لتسهيل وتسريع الإدخال
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text(
                        'مبالغ سريعة: ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      _quickAmountChip('+ 5,000', 5000),
                      _quickAmountChip('+ 10,000', 10000),
                      _quickAmountChip('+ 50,000', 50000),
                      _quickAmountChip('+ 100,000', 100000),
                      InkWell(
                        onTap: () {
                          _amountController.clear();
                          setState(() {});
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'مسح',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // رقم السند البنكي (إجباري صارم لتوثيق كل إيداع ومنع التكرار)
              TextFormField(
                controller: _receiptController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم السند / الإيصال البنكي *',
                  hintText: 'أدخل رقم السند أو الإشعار البنكي',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'رقم السند البنكي إجباري لتوثيق وتأكيد الإيداع';
                  }
                  final clean =
                      v.replaceAll(RegExp(r'\s+'), '').toUpperCase();
                  if (clean.length < 4) {
                    return 'رقم السند يجب أن يتكون من 4 خانات على الأقل';
                  }
                  if (const [
                    '0000',
                    '00000',
                    '000000',
                    '1111',
                    '1234',
                    '12345',
                    'TEST',
                    'NONE',
                    'NULL',
                    'N/A'
                  ].contains(clean)) {
                    return 'رقم السند المدخل وهمي وغير مقبول';
                  }
                  if (widget.existingRecords != null) {
                    final exists = widget.existingRecords!.any((r) {
                      final rBank =
                          (r['bank_name'] ?? '').toString().trim();
                      final rReceipt = (r['receipt_number'] ?? '')
                          .toString()
                          .replaceAll(RegExp(r'\s+'), '')
                          .toUpperCase();
                      return rBank == _selectedBank && rReceipt == clean;
                    });
                    if (exists) {
                      return 'رقم السند مسجل مسبقاً لدى بنك $_selectedBank! (مكرر)';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ملاحظات اختيارية
              TextFormField(
                controller: _notesController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleProceed(),
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  hintText: 'أي ملاحظات إضافية على العملية',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 22),

              // زر تأكيد الإيداع مع الحماية الاستباقية وقفل فترة التهدئة
              Builder(
                builder: (context) {
                  final isBlockedByCooldown =
                      _serverVerifiedProfile?['is_in_cooldown'] == true;

                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: (_isSubmitting || isBlockedByCooldown)
                          ? null
                          : _handleProceed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isBlockedByCooldown
                            ? AppColors.error
                            : AppColors.primary,
                        disabledBackgroundColor: isBlockedByCooldown
                            ? AppColors.error.withValues(alpha: 0.3)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: isBlockedByCooldown ? 0 : 2,
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              isBlockedByCooldown
                                  ? Icons.lock_clock_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: Colors.white,
                            ),
                      label: Text(
                        _isSubmitting
                            ? 'جارٍ التحقق والإيداع...'
                            : isBlockedByCooldown
                                ? 'محظور أمنياً: فترة تهدئة (12 ساعة)'
                                : 'مراجعة وتأكيد الإيداع',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: isBlockedByCooldown ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAmountChip(String label, int value) {
    return InkWell(
      onTap: () => _addQuickAmount(value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

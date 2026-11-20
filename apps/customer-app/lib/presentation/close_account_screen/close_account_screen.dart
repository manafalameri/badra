import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/security_service.dart';
import '../../core/supabase_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/otp_input_widget.dart';

class CloseAccountScreen extends StatefulWidget {
  const CloseAccountScreen({super.key});

  @override
  State<CloseAccountScreen> createState() => _CloseAccountScreenState();
}

class _CloseAccountScreenState extends State<CloseAccountScreen> {
  final _security = SecurityService.instance;
  final _pinFocus = FocusNode();
  String _pin = '';
  bool _pinValid = false;
  String? _pinError;
  String? _generalError;
  bool _isProcessing = false;
  bool _confirmed = false;

  @override
  void dispose() {
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isProcessing) return;

    if (_pin.length != 6 || int.tryParse(_pin) == null) {
      setState(() => _pinError = 'الرقم السري يجب أن يكون 6 أرقام');
      return;
    }

    if (!_confirmed) {
      setState(() => _generalError = 'يجب تأكيد فهمك لإغلاق الحساب أولاً');
      return;
    }

    setState(() {
      _pinError = null;
      _generalError = null;
      _isProcessing = true;
    });

    final result = await SupabaseService.closeMyAccount(_pin);

    if (!mounted) return;

    if (result['success'] == true) {
      // تنظيف البيانات المحلية
      try {
        await _security.clearAllSession();
        await _security.clearLoginTimestamp();
        await _security.clearPhone();
        await _security.deleteDeviceKeyPair();
        await _security.setBiometricEnabled(false);
      } catch (_) {}
      try {
        await SupabaseService.signOut();
      } catch (_) {}

      if (!mounted) return;
      Get.offAllNamed(AppRoutes.signUpLogin);
      return;
    }

    setState(() {
      _isProcessing = false;
      final error = result['error']?.toString();
      final reason = result['reason']?.toString();
      if (reason == 'balance_not_zero') {
        _generalError = error ?? 'لا يمكن إغلاق الحساب والرصيد غير صفر';
      } else {
        _generalError = error ?? 'فشل إغلاق الحساب. حاول مرة أخرى.';
      }
    });
  }

  TextStyle _sora({Color? color, double? fontSize, FontWeight? fontWeight, double? height}) {
    return GoogleFonts.sora(
        color: color, fontSize: fontSize, fontWeight: fontWeight, height: height);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDeep,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text('إغلاق الحساب'),
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppTheme.error, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'إغلاق الحساب نهائي',
                            style: _sora(
                              color: AppTheme.error,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'عند إغلاق الحساب:\n'
                        '• تُحذف جميع بياناتك الشخصية (الاسم، الأجهزة، الحسابات المالية).\n'
                        '• لن تتمكن من تسجيل الدخول مجدداً.\n'
                        '• لا يمكن التراجع عن هذه العملية.',
                        style: _sora(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2016),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF1A3A28),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مهم جداً: الرصيد يجب أن يكون صفراً',
                        style: _sora(
                          color: AppTheme.goldAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'لا يمكن إغلاق الحساب إذا كان رصيدك الحالي غير صفر. '
                        'أنفق رصيدك أولاً في متاجر المنصة ثم عد لإغلاق الحساب.',
                        style: _sora(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'أدخل الرقم السري (كود الأمان)',
                  style: _sora(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                OtpInputWidget(
                  fieldCount: 6,
                  firstFocusNode: _pinFocus,
                  obscure: true,
                  onCompleted: (v) => setState(() {
                    _pin = v;
                    _pinValid = true;
                  }),
                  onChanged: (v) => setState(() {
                    _pin = v;
                    _pinValid = v.length == 6;
                    _pinError = null;
                  }),
                ),
                if (_pinError != null) ...[
                  const SizedBox(height: 10),
                  Text(_pinError!,
                      style: _sora(color: AppTheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _confirmed
                              ? AppTheme.error
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _confirmed
                                ? AppTheme.error
                                : AppTheme.textMuted,
                            width: 1.5,
                          ),
                        ),
                        child: _confirmed
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'أؤكد أنني أفهم أن إغلاق الحساب نهائي ولا يمكن التراجع عنه',
                          style: _sora(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_generalError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _generalError!,
                            style: _sora(color: AppTheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        (_isProcessing || !_pinValid || !_confirmed)
                            ? null
                            : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.error.withValues(
                          alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'إغلاق الحساب نهائياً',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
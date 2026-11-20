import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../controllers/auth_controller.dart';
import '../../../core/security_service.dart';
import '../../../core/supabase_service.dart';
import '../../../widgets/otp_input_widget.dart';
import '../../../widgets/animated_background.dart';
import '../../../theme/app_theme.dart';

class ApprovalDialog extends StatefulWidget {
  final String merchantName;
  final String amount;
  final String requestId;
  final String deviceId;
  final String orderRef;
  final String? userBalance;
  final Future<Map<String, dynamic>> Function({
    required String securityCode,
    required String signature,
    required String timestamp,
    String? couponCode,
  }) onApproved;
  final VoidCallback onRejected;

  const ApprovalDialog({
    super.key,
    required this.merchantName,
    required this.amount,
    required this.requestId,
    required this.deviceId,
    this.orderRef = '',
    this.userBalance,
    required this.onApproved,
    required this.onRejected,
  });

  @override
  State<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<ApprovalDialog> {
  final _security = SecurityService.instance;
  final _pinController = TextEditingController();
  final _couponController = TextEditingController();
  final _pinFocus = FocusNode();
  final _couponFocus = FocusNode();
  String _pin = '';
  String _couponCode = '';
  String? _pinError;
  String? _generalError;
  bool _balanceError = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pinFocus.addListener(_onFocusChange);
    _couponFocus.addListener(_onFocusChange);
    _tryBiometric();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pinFocus.removeListener(_onFocusChange);
    _couponFocus.removeListener(_onFocusChange);
    _pinController.dispose();
    _couponController.dispose();
    _pinFocus.dispose();
    _couponFocus.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final available = await _security.isDeviceSupported();
    final enabled = await _security.isBiometricEnabled();
    if (!available || !enabled) return;
    final success = await _security.authenticateBiometrics();
    if (!mounted) return;
    if (success) _pinFocus.requestFocus();
  }

  Future<void> _submit() async {
    if (_isProcessing) return;

    if (_pin.length != 6 || int.tryParse(_pin) == null) {
      setState(() => _pinError = 'الرقم السري يجب أن يكون 6 أرقام');
      return;
    }

    setState(() {
      _pinError = null;
      _generalError = null;
      _isProcessing = true;
    });

    // 1. Check lockout
    final lockout = await SupabaseService.checkLockout('security_code');
    if (!mounted) return;
    if (lockout['locked'] == true) {
      _pinController.clear();
      setState(() {
        _pin = '';
        _isProcessing = false;
        _pinError = 'تم قفل الحساب مؤقتاً. حاول بعد 30 دقيقة.';
      });
      _pinFocus.requestFocus();
      return;
    }

    // 2. Ensure device key is set up and synced to DB
    try {
      await Get.find<AuthController>().carveCurrentDevice();
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _generalError = 'فشل تجهيز مفتاح الأمان: $e';
      });
      return;
    }

    // 3. Sign payload (bound cryptographically to requestId + timestamp + deviceId)
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final payload = '${widget.requestId}|$timestamp|${widget.deviceId}';
    final signature = await _security.signApprovalPayload(payload);

    if (signature.isEmpty) {
      setState(() {
        _isProcessing = false;
        _generalError = 'فشل توقيع الطلب';
      });
      return;
    }

    // 4. Call onApproved
    final result = await widget.onApproved(
      securityCode: _pin,
      signature: signature,
      timestamp: timestamp,
      couponCode: _couponCode.trim().length == 6 ? _couponCode.trim() : null,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Get.back(result: true);
      return;
    }

    final errorMsg = result['error']?.toString() ?? 'فشلت المعاملة';
    final isPinError = errorMsg.contains('رقم السري') ||
        errorMsg.contains('رمز الأمان') ||
        errorMsg.contains('الرمز السري') ||
        errorMsg.contains('كود التحدي');
    final isBalanceError = errorMsg.contains('الرصيد') || errorMsg.contains('رصيد');
    final isCouponError = errorMsg.contains('كود الخصم');
    final isLockout = errorMsg.contains('قفل') || errorMsg.contains('30 دقيقة');

    _pinController.clear();
    setState(() {
      _pin = '';
      _isProcessing = false;
      if (isLockout) {
        _pinError = errorMsg;
        _generalError = null;
        _balanceError = false;
      } else if (isPinError) {
        _pinError = errorMsg;
        _generalError = null;
        _balanceError = false;
        _pinFocus.requestFocus();
      } else if (isBalanceError) {
        _generalError = 'عفواً، رصيدك غير كافٍ لإتمام هذه المعاملة';
        _pinError = null;
        _balanceError = true;
      } else if (isCouponError) {
        _couponController.clear();
        _couponCode = '';
        _generalError = errorMsg;
        _pinError = null;
        _balanceError = false;
      } else {
        _generalError = errorMsg;
        _pinError = null;
        _balanceError = false;
      }
    });
  }

  String get _displayMerchantName {
    final raw = widget.merchantName.trim();
    if (raw.isEmpty || raw == 'برسيم' || raw.contains('برسيم')) return 'تليد';
    return raw;
  }

  TextStyle _sora({Color? color, double? fontSize, FontWeight? fontWeight}) {
    return GoogleFonts.sora(color: color, fontSize: fontSize, fontWeight: fontWeight);
  }

  String _formatShortRef(String ref) {
    if (ref.isEmpty) {
      final id = widget.requestId;
      return id.length >= 4 ? id.substring(id.length - 4) : id;
    }
    final digits = ref.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    if (ref.length >= 4) return ref.substring(ref.length - 4);
    return ref;
  }

  Widget _buildStoreLogo(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.emeraldPrimary.withAlpha(25),
        border: Border.all(
          color: AppTheme.emeraldPrimary.withAlpha(80),
          width: 1.5,
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
          return Center(
            child: Icon(
              Icons.storefront_rounded,
              color: AppTheme.emeraldPrimary,
              size: size * 0.55,
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderRefBadge(double sw) {
    final shortRef = _formatShortRef(widget.orderRef);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sw * 0.025, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(30), width: 1),
      ),
      child: Text(
        '#$shortRef',
        style: _sora(
          fontSize: sw * 0.028,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildBalanceBadge(double sw) {
    final reqAmount = num.tryParse(widget.amount.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final curBalance = num.tryParse((widget.userBalance ?? '0').replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final isInsufficient = curBalance < reqAmount;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: sw * 0.03, vertical: sw * 0.010),
      decoration: BoxDecoration(
        color: isInsufficient
            ? AppTheme.error.withAlpha(22)
            : AppTheme.emeraldPrimary.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInsufficient
              ? AppTheme.error.withAlpha(70)
              : AppTheme.emeraldPrimary.withAlpha(50),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isInsufficient ? Icons.warning_amber_rounded : Icons.account_balance_wallet_outlined,
            size: sw * 0.034,
            color: isInsufficient ? AppTheme.error : AppTheme.emeraldPrimary,
          ),
          SizedBox(width: sw * 0.015),
          Text(
            isInsufficient
                ? 'رصيدك المتاح: ${widget.userBalance} ر.ي (غير كافٍ)'
                : 'رصيدك المتاح: ${widget.userBalance} ر.ي',
            style: _sora(
              fontSize: sw * 0.027,
              fontWeight: FontWeight.w600,
              color: isInsufficient ? AppTheme.error : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final pad = sw * 0.045;
    final gapSm = sh * 0.010;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: sw * 0.05, vertical: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(sw * 0.065),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: AnimatedBackground(
            child: Container(
              width: sw * 0.90,
              constraints: BoxConstraints(maxHeight: sh * 0.58),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard.withAlpha(225),
                border: Border.all(color: AppTheme.emeraldPrimary.withAlpha(50), width: 1),
                borderRadius: BorderRadius.circular(sw * 0.065),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(130), blurRadius: 40, offset: const Offset(0, 20)),
                  BoxShadow(color: AppTheme.emeraldPrimary.withAlpha(25), blurRadius: 35, spreadRadius: -5),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── الشريط العلوي (شعار المتجر + تأكيد الدفع + رقم العملية) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildStoreLogo(sw * 0.095),
                        Text(
                          'تأكيد الدفع',
                          style: _sora(
                            fontSize: sw * 0.042,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        _buildOrderRefBadge(sw),
                      ],
                    ),
                    SizedBox(height: gapSm),

                    // ── بيانات الدفع (المتجر والمبلغ) ──────────────────────
                    Text(
                      'الدفع لـ $_displayMerchantName',
                      style: _sora(
                        fontSize: sw * 0.033,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.amount} ريال',
                      style: _sora(
                        fontSize: sw * 0.055,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.emeraldPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.userBalance != null) ...[
                      const SizedBox(height: 6),
                      _buildBalanceBadge(sw),
                    ],
                    SizedBox(height: gapSm),

                    // ── حقل الرقم السري ─────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الرقم السري',
                          style: _sora(
                            fontSize: sw * 0.032,
                            fontWeight: FontWeight.w600,
                            color: _pinFocus.hasFocus
                                ? AppTheme.emeraldPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        if (_pinFocus.hasFocus)
                          Text(
                            '● جارِ الإدخال',
                            style: _sora(
                              fontSize: sw * 0.026,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.emeraldPrimary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    OtpInputWidget(
                      controller: _pinController,
                      fieldCount: 6,
                      firstFocusNode: _pinFocus,
                      obscure: true,
                      onSubmitted: _submit,
                      onCompleted: (v) {},
                      onChanged: (v) => setState(() {
                        _pin = v;
                        _pinError = null;
                        if (!_balanceError) {
                          _generalError = null;
                        }
                      }),
                    ),
                    if (_pinError != null) ...[
                      const SizedBox(height: 4),
                      Text(_pinError!, style: _sora(color: AppTheme.error, fontSize: sw * 0.028)),
                    ],
                    if (_generalError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.error.withAlpha(70)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _generalError!,
                                style: _sora(
                                  color: AppTheme.error,
                                  fontSize: sw * 0.028,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: gapSm),

                    // ── حقل كود الخصم (اختياري) ─────────────────────────────
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: sw * 0.035,
                        vertical: sw * 0.022,
                      ),
                      decoration: BoxDecoration(
                        color: _couponFocus.hasFocus
                            ? AppTheme.emeraldPrimary.withAlpha(20)
                            : AppTheme.emeraldPrimary.withAlpha(10),
                        borderRadius: BorderRadius.circular(sw * 0.035),
                        border: Border.all(
                          color: _couponFocus.hasFocus
                              ? AppTheme.emeraldPrimary
                              : (_couponCode.isNotEmpty
                                  ? AppTheme.emeraldPrimary.withAlpha(90)
                                  : AppTheme.borderGlass),
                          width: _couponFocus.hasFocus ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_offer_rounded,
                                    size: sw * 0.036,
                                    color: _couponFocus.hasFocus
                                        ? AppTheme.emeraldPrimary
                                        : AppTheme.emeraldPrimary.withAlpha(180),
                                  ),
                                  SizedBox(width: sw * 0.015),
                                  Text(
                                    'كود الخصم (اختياري)',
                                    style: _sora(
                                      fontSize: sw * 0.030,
                                      fontWeight: FontWeight.w600,
                                      color: _couponFocus.hasFocus
                                          ? AppTheme.emeraldPrimary
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              if (_couponCode.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _couponController.clear();
                                    setState(() => _couponCode = '');
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(25),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: sw * 0.032,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          OtpInputWidget(
                            controller: _couponController,
                            fieldCount: 6,
                            firstFocusNode: _couponFocus,
                            obscure: false,
                            onSubmitted: _submit,
                            onCompleted: (v) {},
                            onChanged: (v) => setState(() {
                              _couponCode = v;
                              if (_generalError != null && _generalError!.contains('كود الخصم')) {
                                _generalError = null;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gapSm * 1.2),

                    // ── أزرار الإجراءات (إلغاء وتأكيد الدفع) ──────────────────
                    _buildActionButtons(sw, sh),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(double sw, double sh) {
    final canSubmit = _pin.length == 6;
    final btnHeight = sh * 0.052;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _isProcessing ? null : () { widget.onRejected(); Get.back(); },
            child: Container(
              height: btnHeight,
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(22),
                borderRadius: BorderRadius.circular(sw * 0.035),
                border: Border.all(color: AppTheme.error.withAlpha(55), width: 1),
              ),
              child: Center(
                child: Text('إلغاء', style: _sora(color: AppTheme.error, fontWeight: FontWeight.w600, fontSize: sw * 0.035)),
              ),
            ),
          ),
        ),
        SizedBox(width: sw * 0.035),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: canSubmit && !_isProcessing ? _submit : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: btnHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: canSubmit
                      ? [AppTheme.emeraldPrimary, AppTheme.emeraldPrimary.withAlpha(220)]
                      : [AppTheme.emeraldPrimary.withAlpha(60), AppTheme.emeraldPrimary.withAlpha(40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(sw * 0.035),
                boxShadow: canSubmit ? [BoxShadow(color: AppTheme.emeraldPrimary.withAlpha(60), blurRadius: 12, offset: const Offset(0, 4))] : [],
              ),
              child: Center(
                child: _isProcessing
                    ? SizedBox(width: sw * 0.045, height: sw * 0.045, child: const CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.backgroundDeep))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, color: canSubmit ? AppTheme.backgroundDeep : AppTheme.backgroundDeep.withAlpha(100), size: sw * 0.045),
                          SizedBox(width: sw * 0.015),
                          Text('تأكيد الدفع', style: _sora(color: canSubmit ? AppTheme.backgroundDeep : AppTheme.backgroundDeep.withAlpha(100), fontWeight: FontWeight.w700, fontSize: sw * 0.036)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

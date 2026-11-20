import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/device_binding_service.dart';
import '../../widgets/app_theme.dart';

/// شاشة القفل الإلزامية عند كل فتح بارد للتطبيق.
///
/// حتى لو كانت الجلسة محفوظة وصالحة، لا يدخل المدير اللوحة إلا بعد:
/// 1. تأكيد الهوية محليًا (بصمة) أو الدخول بالبيانات الكاملة.
/// 2. إعادة التحقق من الجهاز مع الخادم قبل الفتح (fail-closed).
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onRequestCredentials,
    required this.onSecurityReject,
  });

  /// يُستدعى بعد نجاح البصمة وتأكيد الخادم للجهاز.
  final VoidCallback onUnlocked;

  /// يُستدعى عندما يختار المدير الدخول برقم الجوال وكلمة المرور.
  final VoidCallback onRequestCredentials;

  /// يُستدعى عند رفض الخادم للجهاز — خروج كامل إجباري.
  final VoidCallback onSecurityReject;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _checkTimeout = Duration(seconds: 15);
  bool _hasSavedCredentials = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final saved = await AuthService.hasSavedCredentials();
    debugPrint('[LOCK] hasSavedCredentials = $saved');
    if (mounted) setState(() => _hasSavedCredentials = saved);
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await AuthService.authenticateWithBiometrics(
        'أدخل بصمتك لفتح لوحة التحكم',
      );
      if (!ok) {
        debugPrint('[LOCK] Biometric failed/cancelled');
        _showInfo('لم يتم التحقق من البصمة', AppColors.warning);
        return;
      }

      debugPrint('[LOCK] Biometric OK -> re-verifying device with server...');
      final result =
          await DeviceBindingService.verifyDevice().timeout(_checkTimeout);

      if (result['success'] == true) {
        widget.onUnlocked();
      } else if (result['transient'] == true) {
        _showInfo('تعذر الاتصال بالخادم، تحقق من الإنترنت وحاول مجددًا',
            AppColors.error);
      } else {
        debugPrint('[LOCK] Server rejected device -> force sign-out');
        widget.onSecurityReject();
      }
    } on TimeoutException {
      _showInfo('انتهت مهلة الاتصال بالخادم، حاول مجددًا', AppColors.error);
    } catch (e) {
      debugPrint('[LOCK] Unlock error: $e');
      _showInfo('حدث خطأ أثناء الفتح، حاول مجددًا', AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showInfo(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a237e), Color(0xFF283593), Color(0xFF1565C0)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'التطبيق مقفل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أكّد هويتك للمتابعة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_hasSavedCredentials) ...[
                          Center(
                            child: Text(
                              'افتح بالبصمة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: GestureDetector(
                              onTap: _busy ? null : _unlockWithBiometrics,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5),
                                      )
                                    : Icon(
                                        Icons.fingerprint,
                                        size: 44,
                                        color: AppColors.primary,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Expanded(
                                  child:
                                      Divider(color: AppColors.divider)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'أو',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                              const Expanded(
                                  child:
                                      Divider(color: AppColors.divider)),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _busy
                                ? null
                                : widget.onRequestCredentials,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.person_outline_rounded,
                                size: 20),
                            label: const Text(
                              'الدخول برقم الجوال وكلمة المرور',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Icon(Icons.security_rounded,
                      size: 16, color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(height: 6),
                  Text(
                    'الخادم يتحقق من هويتك وجهازك في كل مرة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/security_service.dart';
import '../../core/supabase_service.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badra_brand_logo.dart';
import '../../widgets/otp_input_widget.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final AuthController _authController = Get.find();
  final SecurityService _security = SecurityService.instance;
  bool _loading = false;
  String? _error;

  String _pin = '';
  String _pinConfirm = '';
  bool _showConfirm = false;
  Key _otpKey = UniqueKey();
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final supported = await _security.isDeviceSupported();
    if (mounted) setState(() => _biometricAvailable = supported);
  }

  Future<void> _save() async {
    if (_loading) return;
    if (_pin.isEmpty || _pin != _pinConfirm) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _authController.setupPinAndCarve(
        pin: _pin,
        enableBiometric: _biometricEnabled,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
      return;
    }

    if (!mounted) return;

    try {
      final profile = await SupabaseService.getCurrentProfile();
      if (!mounted) return;
      final args = {
        'name': profile.name,
        'phone': SupabaseService.currentUser?.phone ?? '',
        'balance': profile.balance.toString(),
      };
      Get.offAllNamed(AppRoutes.mainNavigation, arguments: args);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
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
          title: const Text('إعداد الحماية'),
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),
                const BadraBrandLogo(size: 56, showText: true),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xFF0D2016),
                    border: Border.all(
                      color: const Color(0xFF1A3A28),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 56,
                        color: AppTheme.emeraldPrimary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _showConfirm ? 'تأكيد الرقم السري' : 'أدخل الرقم السري',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _showConfirm
                            ? 'أعد إدخال الكود للتأكيد'
                            : '٦ أرقام لحماية معاملاتك',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      OtpInputWidget(
                        key: _otpKey,
                        fieldCount: 6,
                        obscure: true,
                        onSubmitted: _save,
                        onCompleted: (code) {
                          if (!_showConfirm) {
                            _pin = code;
                            setState(() {
                              _showConfirm = true;
                              _otpKey = UniqueKey();
                            });
                          } else {
                            _pinConfirm = code;
                            if (_pin != _pinConfirm) {
                              setState(() {
                                _error = 'الكودان غير متطابقين';
                                _showConfirm = false;
                                _pin = '';
                                _pinConfirm = '';
                                _otpKey = UniqueKey();
                              });
                            } else {
                              setState(() => _error = null);
                            }
                          }
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_biometricAvailable) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'تفعيل البصمة لتسجيل دخول سريع',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Switch(
                              value: _biometricEnabled,
                              onChanged: (v) => setState(() => _biometricEnabled = v),
                              activeThumbColor: AppTheme.emeraldPrimary,
                            ),
                          ],
                        ),
                      ],
                      if (_pin.isNotEmpty && _pin == _pinConfirm) ...[
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: _loading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.backgroundDeep,
                                    ),
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'حفظ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ],
                    ],
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

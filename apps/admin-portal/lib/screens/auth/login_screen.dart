import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/device_binding_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSuccess, this.onCancel});

  /// يُستدعى بدل التنقل المباشر عندما تدير البوابة (AuthGate) الحالة.
  final void Function()? onSuccess;

  /// يُستدعى للعودة إلى شاشة القفل عند الدخول من داخل سياق القفل.
  final VoidCallback? onCancel;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _hasSavedCredentials = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final hasCredentials = await AuthService.hasSavedCredentials();
    debugPrint('[LOGIN] hasSavedCredentials = $hasCredentials');
    if (mounted) setState(() => _hasSavedCredentials = hasCredentials);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final enteredPhone = _phoneController.text.trim();
    final enteredPassword = _passwordController.text;

    if (enteredPhone.isEmpty) {
      _showError('أدخل رقم الهاتف');
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (enteredPassword.isEmpty) {
      _showError('أدخل كلمة المرور');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final resp =
          await AuthService.signInWithPhone(enteredPhone, enteredPassword);

      final session = resp.session;
      if (session != null && mounted) {
        debugPrint('[LOGIN] Normal login SUCCESS. Verifying device...');
        final deviceResult = await DeviceBindingService.verifyDevice();
        if (deviceResult['success'] != true) {
          await AuthService.signOut();
          _showError(deviceResult['error'] ?? 'جهاز غير معروف');
          return;
        }
        debugPrint('[LOGIN] Device verified. Saving credentials...');
        await AuthService.saveCredentials(enteredPhone, enteredPassword);
        debugPrint('[LOGIN] Credentials saved. phone=$enteredPhone (len=${enteredPhone.length})');
        if (!mounted) return;
        debugPrint('[LOGIN] Handing off to gate (onSuccess)');
        widget.onSuccess!();
      } else {
        _showError('فشل تسجيل الدخول. لم يتم إنشاء جلسة صحيحة.');
      }
    } catch (e) {
      await AuthService.signOut();
      _showError('حدث خطأ أثناء تسجيل الدخول: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithBiometrics() async {
    setState(() => _isLoading = true);
    try {
      final success = await AuthService.loginWithBiometrics();
      if (success && mounted) {
        debugPrint('[LOGIN] Biometric login SUCCESS. Verifying device...');
        final deviceResult = await DeviceBindingService.verifyDevice();
        if (deviceResult['success'] != true) {
          await AuthService.signOut();
          DeviceBindingService.clearDeviceId();
          _showError(deviceResult['error'] ?? 'جهاز غير معروف');
          return;
        }
        if (!mounted) return;
        debugPrint('[LOGIN] Biometric handoff to gate (onSuccess)');
        widget.onSuccess!();
      } else if (mounted) {
        _showError('فشل تسجيل الدخول بالبصمة');
      }
    } catch (e) {
      _showError('حدث خطأ أثناء تسجيل الدخول بالبصمة: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.error,
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
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Section
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
                          Icons.admin_panel_settings_rounded,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'لوحة التحكم',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'سجّل دخولك للمتابعة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Card Form
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
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                textAlign: TextAlign.left,
                                style: AppTextStyles.body,
                                decoration: const InputDecoration(
                                  labelText: 'رقم الجوال',
                                  labelStyle: AppTextStyles.bodySecondary,
                                  prefixIcon: Icon(Icons.phone_android_outlined,
                                      color: AppColors.primary),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'أدخل رقم الجوال';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _login(),
                                style: AppTextStyles.body,
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  labelStyle: AppTextStyles.bodySecondary,
                                  prefixIcon: const Icon(Icons.lock_outline,
                                      color: AppColors.primary),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'أدخل كلمة المرور';
                                  }
                                  if (v.length < 6) {
                                    return 'كلمة المرور قصيرة جداً';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.login_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'دخول',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'تطبيق إدارة آمن',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (_hasSavedCredentials) ...[
                                const SizedBox(height: 12),
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        'أو سجّل الدخول بالبصمة',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: _isLoading ? null : _loginWithBiometrics,
                                        child: Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.primary.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.fingerprint,
                                            size: 36,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.onCancel != null)
                        TextButton.icon(
                          onPressed: widget.onCancel,
                          icon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'العودة إلى شاشة القفل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

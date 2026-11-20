import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/auth_controller.dart';
import '../../core/security_service.dart';
import '../../core/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/badra_brand_logo.dart';
import '../../widgets/badra_luxury_toast.dart';
import '../../widgets/badra_legal_modal.dart';

class SignUpLoginScreen extends StatefulWidget {
  const SignUpLoginScreen({super.key});

  @override
  State<SignUpLoginScreen> createState() => _SignUpLoginScreenState();
}

class _SignUpLoginScreenState extends State<SignUpLoginScreen>
    with TickerProviderStateMixin {
  // TODO: Replace with Riverpod/Bloc for production
  late TabController _tabController;

  // Login form
  final _loginFormKey = GlobalKey<FormState>();
  final _loginPhoneCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginPasswordVisible = false;
  bool _loginLoading = false;
  // True while the biometric unlock flow (fingerprint → session restore) runs:
  // blocks double-taps and shows the "opening app" overlay.
  bool _biometricOpening = false;
  // Inline notice shown under the biometric icon when a fallback is required.
  String? _biometricNotice;
  late final AuthController _authController;

  // Sign up form
  final _signupFormKey = GlobalKey<FormState>();
  final _signupNameCtrl = TextEditingController();
  final _signupPhoneCtrl = TextEditingController();
  final _signupPasswordCtrl = TextEditingController();
  final _signupConfirmCtrl = TextEditingController();
  bool _signupPasswordVisible = false;
  bool _signupConfirmVisible = false;
  bool _signupLoading = false;
  bool _agreeToTerms = false;

  // Focus nodes for Enter-key navigation
  final _loginPhoneFocus = FocusNode();
  final _loginPasswordFocus = FocusNode();
  final _signupNameFocus = FocusNode();
  final _signupPhoneFocus = FocusNode();
  final _signupPasswordFocus = FocusNode();
  final _signupConfirmFocus = FocusNode();

  void _focusNext(FocusNode node) {
    FocusScope.of(context).requestFocus(node);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      node.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _hideKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  void initState() {
    super.initState();
    // AuthController is already registered in main() with permanent: true.
    // Using Get.find() avoids a duplicate registration race that used to
    // surface as a transient "Something went wrong" screen on first login.
    _authController = Get.find<AuthController>();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    // Local-only safety net: if the pre-boot security state load failed,
    // reload it here fire-and-forget. Never blocks or shows any loading UI.
    if (!_authController.securityStateReady.value) {
      _authController.loadSecurityState();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginPhoneCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _signupNameCtrl.dispose();
    _signupPhoneCtrl.dispose();
    _signupPasswordCtrl.dispose();
    _signupConfirmCtrl.dispose();
    _loginPhoneFocus.dispose();
    _loginPasswordFocus.dispose();
    _signupNameFocus.dispose();
    _signupPhoneFocus.dispose();
    _signupPasswordFocus.dispose();
    _signupConfirmFocus.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) {
      if (_loginPhoneCtrl.text.trim().isEmpty) {
        _focusNext(_loginPhoneFocus);
      } else {
        _focusNext(_loginPasswordFocus);
      }
      return;
    }
    setState(() => _loginLoading = true);
    _biometricNotice = null;
    final navigator = Navigator.of(context);
    debugPrint(
      '[LOGIN] Attempting login with phone: ${_loginPhoneCtrl.text.trim()}',
    );

    try {
      final profile = await _authController.signInAuth(
        phone: _loginPhoneCtrl.text.trim(),
        password: _loginPasswordCtrl.text.trim(),
      );
      if (profile == null) {
        if (_authController.errorMessage.value.isNotEmpty) {
          throw Exception(_authController.errorMessage.value);
        }
        return;
      }
      if (!mounted) return;
      debugPrint('[LOGIN] Success: ${profile.name}');

      final phone = SupabaseService.currentUser?.phone ?? '';
      await SecurityService.instance.savePhone(phone);

      final securityCheck = await SupabaseService.checkSecuritySetup();
      final args = {
        'name': profile.name,
        'phone': phone,
        'balance': profile.balance.toString(),
      };

      if (securityCheck['setup_required'] == true) {
        debugPrint('[LOGIN] Security setup required → pinSetup');
        navigator.pushNamedAndRemoveUntil(
          AppRoutes.pinSetup,
          (route) => false,
          arguments: args,
        );
      } else {
        debugPrint('[LOGIN] Navigating to mainNavigation');
        navigator.pushNamedAndRemoveUntil(
          AppRoutes.mainNavigation,
          (route) => false,
          arguments: args,
        );
      }
    } catch (error) {
      debugPrint('[LOGIN] ERROR: $error');
      if (!mounted) return;
      final msg = error.toString().replaceFirst('Exception: ', '');
      BadraLuxuryToast.show(context, msg, type: BadraToastType.error);
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  Future<void> _openAppAfterBiometric() async {
    debugPrint('[BIO] Starting post-biometric flow');

    try {
      if (SupabaseService.currentUserId == null) {
        debugPrint('[BIO] No active session, attempting restore...');
        final restored = await SecurityService.instance
            .restoreSessionWithRefreshToken();
        if (!mounted) return;
        if (!restored) {
          debugPrint('[BIO] FAIL: Session restore failed');
          await _fallbackToPasswordLogin(
            message: 'انتهت صلاحية الجلسة. سجّل الدخول بكلمة المرور مرة أخرى.',
          );
          return;
        }
        debugPrint('[BIO] Session restored successfully');
      } else {
        debugPrint('[BIO] Active session exists, skipping restore');
      }

      // Security: every successful biometric unlock refreshes the session
      // clock, so the inactivity lock never bounces a valid unlock back to
      // the login screen (the "enters then kicks us out" bug).
      await SecurityService.instance.saveLoginTimestamp(DateTime.now());

      // Re-verify the device binding, mirroring the password-login check:
      // a session must not be usable from a device that was unbound since.
      final deviceOk = await SupabaseService.checkBiometricDeviceBinding();
      if (!mounted) return;
      if (!deviceOk) {
        debugPrint('[BIO] FAIL: Device binding rejected');
        await SecurityService.instance.clearAllSession();
        await SecurityService.instance.clearLoginTimestamp();
        await _fallbackToPasswordLogin(
          message: 'تعذر التحقق من الجهاز. سجّل الدخول بكلمة المرور.',
        );
        return;
      }

      final profile = await SupabaseService.getCurrentProfile();
      if (!mounted) return;
      debugPrint('[BIO] Profile loaded: ${profile.name}');

      // A deactivated/locked account must never enter via biometrics —
      // mirror the password-login behavior that routes to the activation
      // screen and terminates the session.
      if (!profile.isActive) {
        debugPrint('[BIO] FAIL: Profile is not active');
        try {
          await SupabaseService.signOut();
        } catch (_) {
          // Best-effort: local cleanup below must still run.
        }
        await SecurityService.instance.clearAllSession();
        await SecurityService.instance.clearLoginTimestamp();
        if (!mounted) return;
        BadraLuxuryToast.show(
          context,
          'هذا الحساب غير نشط. يرجى التواصل مع الدعم الفني.',
          type: BadraToastType.error,
        );
        return;
      }

      final securityCheck = await SupabaseService.checkSecuritySetup();
      final args = {
        'name': profile.name,
        'phone': SupabaseService.currentUser?.phone ?? '',
        'balance': profile.balance.toString(),
      };

      if (securityCheck['setup_required'] == true) {
        debugPrint('[BIO] Security setup required → pinSetup');
        Get.offAllNamed(AppRoutes.pinSetup, arguments: args);
      } else {
        debugPrint('[BIO] Navigating to mainNavigation');
        Get.offAllNamed(AppRoutes.mainNavigation, arguments: args);
      }
    } catch (error) {
      debugPrint('[BIO] ERROR: $error');
      if (!mounted) return;
      BadraLuxuryToast.show(
        context,
        'حدث خطأ عند فتح التطبيق: $error',
        type: BadraToastType.error,
      );
    } finally {
      _biometricOpening = false;
      if (mounted) setState(() {});
    }
  }

  /// Fall back from the biometric flow to password login: pre-fill the saved
  /// phone, switch to the login tab and surface a clear inline notice.
  Future<void> _fallbackToPasswordLogin({required String message}) async {
    final savedPhone = await SecurityService.instance.readPhone();
    if (!mounted) return;
    setState(() => _biometricNotice = message);
    if (savedPhone != null && savedPhone.isNotEmpty) {
      _loginPhoneCtrl.text = savedPhone;
    }
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
    BadraLuxuryToast.show(context, message, type: BadraToastType.error);
  }

  Future<void> _openForgotPasswordSupport() async {
    final loginPhone = _loginPhoneCtrl.text.trim();
    final signupPhone = _signupPhoneCtrl.text.trim();
    var phone = loginPhone.isNotEmpty ? loginPhone : signupPhone;
    if (phone.isEmpty) {
      final saved = await SecurityService.instance.readPhone();
      if (saved != null && saved.isNotEmpty) phone = saved;
    }

    final device = await _authController.getDeviceContext();
    final deviceId = device['deviceId'] ?? '';
    final deviceName = device['deviceName'] ?? '';

    final now = DateTime.now();
    final timestampStr =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final seal = SecurityService.instance.generateRecoverySecuritySeal(
      deviceId,
      timestampStr,
    );

    final phonePart = phone.isNotEmpty ? phone : '[اكتب رقمك هنا]';

    final message =
        'السلام عليكم، أرجو استعادة كلمة المرور لمحفظة بذرة.\n'
        '- الاسم: [اكتب اسمك هنا]\n'
        '- رقم الهاتف: $phonePart\n'
        '- معرّف الجهاز الفيزيائي (Device ID): $deviceId\n'
        '- موديل الهاتف: $deviceName\n'
        '- وقت وتاريخ الطلب: $timestampStr\n'
        '- ختم الأمان المشفر: $seal';

    final uri = Uri.parse(
      'https://wa.me/967730975496?text=${Uri.encodeComponent(message)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('تعذر فتح واتساب');
      }
    } catch (e) {
      if (!mounted) return;
      BadraLuxuryToast.show(
        context,
        'لا يمكن فتح واتساب الآن. ${e.toString()}',
        type: BadraToastType.error,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _handleSignUp() async {
    if (!_agreeToTerms) {
      BadraLuxuryToast.show(
        context,
        'يجب الموافقة على الشروط وسياسة الخصوصية لإنشاء الحساب.',
        type: BadraToastType.error,
      );
      return;
    }
    if (!_signupFormKey.currentState!.validate()) {
      if (_signupNameCtrl.text.trim().isEmpty) {
        _focusNext(_signupNameFocus);
      } else if (_signupPhoneCtrl.text.trim().isEmpty) {
        _focusNext(_signupPhoneFocus);
      } else if (_signupPasswordCtrl.text.isEmpty) {
        _focusNext(_signupPasswordFocus);
      } else {
        _focusNext(_signupConfirmFocus);
      }
      return;
    }
    setState(() => _signupLoading = true);
    final navigator = Navigator.of(context);
    debugPrint(
      '[SIGNUP] Attempting signup with phone: ${_signupPhoneCtrl.text.trim()}',
    );

    try {
      final signupName = _signupNameCtrl.text.trim();
      final signupPhone = _signupPhoneCtrl.text.trim();
      final signupPassword = _signupPasswordCtrl.text.trim();

      final success = await _authController.signUpWithPassword(
        name: signupName,
        phone: signupPhone,
        password: signupPassword,
      );

      if (!success) {
        throw Exception(_authController.errorMessage.value);
      }
      debugPrint('[SIGNUP] Success — logging in automatically...');

      if (!mounted) return;
      await SecurityService.instance.savePhone(signupPhone);

      // تسجيل الدخول التلقائي فوراً
      final profile = await _authController.signInAuth(
        phone: signupPhone,
        password: signupPassword,
      );

      if (profile == null) {
        if (_authController.errorMessage.value.isNotEmpty) {
          throw Exception(_authController.errorMessage.value);
        }
        throw Exception('فشل تسجيل الدخول التلقائي.');
      }

      if (!mounted) return;

      BadraLuxuryToast.show(
        context,
        'تم إنشاء الحساب بنجاح! مرحباً بك، ${profile.name}',
        type: BadraToastType.success,
      );

      final securityCheck = await SupabaseService.checkSecuritySetup();
      final args = {
        'name': profile.name,
        'phone': signupPhone,
        'balance': profile.balance.toString(),
      };

      if (securityCheck['setup_required'] == true) {
        debugPrint('[SIGNUP] Security setup required → pinSetup');
        navigator.pushNamedAndRemoveUntil(
          AppRoutes.pinSetup,
          (route) => false,
          arguments: args,
        );
      } else {
        debugPrint('[SIGNUP] Navigating to mainNavigation');
        navigator.pushNamedAndRemoveUntil(
          AppRoutes.mainNavigation,
          (route) => false,
          arguments: args,
        );
      }
    } catch (error) {
      debugPrint('[SIGNUP] ERROR: $error');
      if (!mounted) return;
      final msg = error.toString().replaceFirst('Exception: ', '');
      BadraLuxuryToast.show(context, msg, type: BadraToastType.error);
    } finally {
      if (mounted) setState(() => _signupLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Content
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 480 : double.infinity,
                      ),
                      child: Column(
                        children: [
                          _buildLogo(),
                          const SizedBox(height: 40),
                          _buildAuthCard(),
                        ],
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

  Widget _buildLogo() {
    return Column(
      children: [
        const BadraBrandLogo(size: 72),
        const SizedBox(height: 16),
        Text(
          'بذرة',
          style: GoogleFonts.sora(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'محفظتك الرقمية الفاخرة',
          style: GoogleFonts.sora(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppTheme.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(210),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(40),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_buildTabBar(), _buildTabContent()],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      height: 46,
      decoration: BoxDecoration(
        color: AppTheme.backgroundDeep.withAlpha(128),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [AppTheme.emeraldPrimary, Color(0xFF00A844)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emeraldPrimary.withAlpha(77),
              blurRadius: 8,
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppTheme.backgroundDeep,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.sora(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        tabs: const [
          Tab(text: 'تسجيل الدخول'),
          Tab(text: 'إنشاء حساب'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    final available = MediaQuery.of(context).size.height;
    final desiredHeight = _tabController.index == 0
        ? math.min(available * 0.6, 520)
        : math.min(available * 0.8, 680);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: desiredHeight.toDouble()),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _tabController.index == 0
              ? KeyedSubtree(
                  key: const ValueKey('login_form'),
                  child: _buildLoginForm(),
                )
              : KeyedSubtree(
                  key: const ValueKey('signup_form'),
                  child: _buildSignupForm(),
                ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            _buildPhoneField(
              controller: _loginPhoneCtrl,
              label: 'رقم الهاتف',
              focusNode: _loginPhoneFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusNext(_loginPasswordFocus),
            ),
            const SizedBox(height: 12),
            _buildPasswordField(
              controller: _loginPasswordCtrl,
              label: 'كلمة المرور',
              visible: _loginPasswordVisible,
              focusNode: _loginPasswordFocus,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                _hideKeyboard();
                _handleLogin();
              },
              onToggle: () => setState(
                () => _loginPasswordVisible = !_loginPasswordVisible,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openForgotPasswordSupport,
                child: Text(
                  'نسيت كلمة المرور؟',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    color: AppTheme.emeraldPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _buildSubmitButton(
              label: 'دخول',
              loading: _loginLoading || _biometricOpening,
              onPressed: _handleLogin,
            ),
            const SizedBox(height: 12),
            // Biometric icon centered inside the card
            Obx(() {
              final available = _authController.biometricAvailable.value;
              final enabled = _authController.biometricEnabled.value;
              if (!available) return const SizedBox.shrink();
              return Center(
                child: InkWell(
                  onTap: () async {
                    debugPrint('[BIO] Button tapped');
                    if (_biometricOpening) return;
                    _biometricOpening = true;
                    _biometricNotice = null;
                    if (mounted) setState(() {});
                    try {
                      final success = await _authController
                          .authenticateBiometric();
                      if (!mounted) return;
                      debugPrint('[BIO] Auth result: $success');
                      if (success) {
                        debugPrint('[BIO] Auth success → opening app');
                        await _openAppAfterBiometric();
                      } else {
                        debugPrint('[BIO] Auth failed → showing error');
                        BadraLuxuryToast.show(
                          context,
                          'فشل التحقق بالبصمة',
                          type: BadraToastType.error,
                        );
                      }
                    } finally {
                      _biometricOpening = false;
                      if (mounted) setState(() {});
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard.withAlpha(30),
                      border: Border.all(
                        color: AppTheme.emeraldPrimary.withAlpha(110),
                        width: 1.4,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      enabled ? Icons.fingerprint : Icons.fingerprint_outlined,
                      color: AppTheme.emeraldPrimary,
                      size: 36,
                    ),
                  ),
                ),
              );
            }),
            if (_biometricNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _biometricNotice!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _signupFormKey,
        child: Column(
          children: [
            _buildTextField(
              controller: _signupNameCtrl,
              label: 'الاسم الكامل',
              icon: Icons.person_outline_rounded,
              focusNode: _signupNameFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusNext(_signupPhoneFocus),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                if (v.trim().length < 3) {
                  return 'الاسم يجب أن يكون 3 أحرف على الأقل';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildPhoneField(
              controller: _signupPhoneCtrl,
              label: 'رقم الهاتف',
              focusNode: _signupPhoneFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusNext(_signupPasswordFocus),
            ),
            const SizedBox(height: 14),
            _buildPasswordField(
              controller: _signupPasswordCtrl,
              label: 'كلمة المرور',
              visible: _signupPasswordVisible,
              focusNode: _signupPasswordFocus,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _focusNext(_signupConfirmFocus),
              onToggle: () => setState(
                () => _signupPasswordVisible = !_signupPasswordVisible,
              ),
            ),
            const SizedBox(height: 14),
            _buildPasswordField(
              controller: _signupConfirmCtrl,
              label: 'تأكيد كلمة المرور',
              visible: _signupConfirmVisible,
              focusNode: _signupConfirmFocus,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                _hideKeyboard();
                _handleSignUp();
              },
              onToggle: () => setState(
                () => _signupConfirmVisible = !_signupConfirmVisible,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'تأكيد كلمة المرور مطلوب';
                if (v != _signupPasswordCtrl.text) {
                  return 'كلمتا المرور غير متطابقتين';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _buildTermsConsent(),
            const SizedBox(height: 14),
            _buildSubmitButton(
              label: 'إنشاء الحساب',
              loading: _signupLoading,
              onPressed: _agreeToTerms ? _handleSignUp : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsConsent() {
    return InkWell(
      onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _agreeToTerms
                ? AppTheme.emeraldPrimary.withAlpha(120)
                : AppTheme.textMuted.withAlpha(60),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: _agreeToTerms
                    ? AppTheme.emeraldPrimary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _agreeToTerms
                      ? AppTheme.emeraldPrimary
                      : AppTheme.textMuted,
                  width: 1.5,
                ),
              ),
              child: _agreeToTerms
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppTheme.backgroundDeep,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    height: 1.6,
                    color: AppTheme.textSecondary,
                  ),
                  children: [
                    const TextSpan(text: 'أوافق على '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => BadraLegalModal.showTerms(context),
                        child: Text(
                          'الشروط والأحكام',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emeraldPrimary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' و '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => BadraLegalModal.showPrivacy(context),
                        child: Text(
                          'سياسة الخصوصية',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emeraldPrimary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneField({
    required TextEditingController controller,
    required String label,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return _GlassmorphicField(
      controller: controller,
      label: label,
      prefixIcon: Icons.phone_outlined,
      keyboardType: TextInputType.number,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      validator: (v) {
        if (v == null || v.isEmpty) return 'رقم الهاتف مطلوب';
        if (!RegExp(r'^7\d{8}$').hasMatch(v)) {
          return 'الرجاء إدخال رقم يمني محلي فقط';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return _GlassmorphicField(
      controller: controller,
      label: label,
      prefixIcon: Icons.lock_outline_rounded,
      obscureText: !visible,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      suffixIcon: IconButton(
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppTheme.textMuted,
          size: 20,
        ),
        onPressed: onToggle,
      ),
      validator:
          validator ??
          (v) {
            if (v == null || v.isEmpty) return 'كلمة المرور مطلوبة';
            if (v.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
            return null;
          },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return _GlassmorphicField(
      controller: controller,
      label: label,
      prefixIcon: icon,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
    );
  }

  Widget _buildSubmitButton({
    required String label,
    required bool loading,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.emeraldPrimary,
          foregroundColor: AppTheme.backgroundDeep,
          disabledBackgroundColor: AppTheme.emeraldDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          shadowColor: AppTheme.emeraldPrimary.withAlpha(102),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.backgroundDeep,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.backgroundDeep,
                ),
              ),
      ),
    );
  }
}

// ── Glassmorphic Form Field ────────────────────────────────────
class _GlassmorphicField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _GlassmorphicField({
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.focusNode,
    this.inputFormatters,
    this.validator,
  });

  @override
  State<_GlassmorphicField> createState() => _GlassmorphicFieldState();
}

class _GlassmorphicFieldState extends State<_GlassmorphicField>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeOutCubic,
    );
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _focused = _focusNode.hasFocus;
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final hasFocus = _focusNode.hasFocus;
    setState(() => _focused = hasFocus);
    if (hasFocus) {
      _glowController.forward();
    } else {
      _glowController.reverse();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppTheme.emeraldPrimary.withValues(
                        alpha: 0.25 * _glowAnimation.value,
                      ),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: TextFormField(
                controller: widget.controller,
                focusNode: _focusNode,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                onFieldSubmitted: widget.onFieldSubmitted,
                inputFormatters: widget.inputFormatters,
                validator: widget.validator,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  labelText: widget.label,
                  labelStyle: GoogleFonts.sora(
                    fontSize: 13,
                    color: _focused
                        ? AppTheme.emeraldPrimary
                        : AppTheme.textSecondary,
                  ),
                  prefixIcon: Icon(
                    widget.prefixIcon,
                    size: 18,
                    color: _focused
                        ? AppTheme.emeraldPrimary
                        : AppTheme.textMuted,
                  ),
                  suffixIcon: widget.suffixIcon,
                  filled: true,
                  fillColor: AppTheme.surfaceCard.withAlpha(153),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.emeraldMuted.withAlpha(77),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.emeraldPrimary,
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.error,
                      width: 1,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.error,
                      width: 1.5,
                    ),
                  ),
                  errorStyle: GoogleFonts.sora(
                    fontSize: 11,
                    color: AppTheme.error,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

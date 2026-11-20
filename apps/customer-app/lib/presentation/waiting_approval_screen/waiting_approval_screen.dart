import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/security_service.dart';
import '../../core/string_utils.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/badra_brand_logo.dart';
import '../../widgets/badra_luxury_toast.dart';

class WaitingApprovalScreen extends StatefulWidget {
  final String? userName;
  final String? userPhone;

  const WaitingApprovalScreen({
    super.key,
    this.userName,
    this.userPhone,
  });

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  String _name = '';
  String _phone = '';
  bool _isLoadingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    _name = widget.userName ?? '';
    _phone = widget.userPhone ?? '';

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.02),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveUserInfo());
  }

  Future<void> _resolveUserInfo() async {
    final routeArgs =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final getArgs = Get.arguments as Map<String, dynamic>?;

    String resolvedName = _name.isNotEmpty
        ? _name
        : (routeArgs?['name'] as String? ?? getArgs?['name'] as String? ?? '');

    String resolvedPhone = _phone.isNotEmpty
        ? _phone
        : (routeArgs?['phone'] as String? ?? getArgs?['phone'] as String? ?? '');

    if (resolvedPhone.isEmpty) {
      final savedPhone = await SecurityService.instance.readPhone();
      if (savedPhone != null && savedPhone.isNotEmpty) {
        resolvedPhone = savedPhone;
      }
    }

    if (mounted) {
      setState(() {
        _name = resolvedName;
        _phone = resolvedPhone;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _openActivationWhatsApp() async {
    if (_isLoadingWhatsApp) return;
    setState(() => _isLoadingWhatsApp = true);

    try {
      final namePart = _name.trim().isNotEmpty ? _name.trim() : '[ضع اسمي هنا]';
      final phonePart = _phone.trim().isNotEmpty ? _phone.trim() : '[ضع رقمك هنا]';

      final message =
          'السلام عليكم ورحمة الله وبركاته،\n'
          'لقد قمت بإنشاء حساب جديد في تطبيق بذرة وأرغب في المتابعة.\n\n'
          '📌 بيانات الحساب:\n'
          '- الاسم: $namePart\n'
          '- رقم الهاتف: $phonePart\n\n'
          'يرجى التكرم بمتابعة حالة الحساب.\n'
          'شاكر ومقدّر لتعاونكم.';

      final uri = Uri.parse(
        'https://wa.me/967730975496?text=${Uri.encodeComponent(message)}',
      );

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('تعذر فتح تطبيق واتساب. تأكد من تثبيته على هاتفك.');
      }
    } catch (e) {
      if (!mounted) return;
      BadraLuxuryToast.show(
        context,
        'تعذر فتح واتساب: ${e.toString().replaceFirst('Exception: ', '')}',
        type: BadraToastType.error,
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) setState(() => _isLoadingWhatsApp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent, // شفاف لكي تظهر خلفية AnimatedBackground
        body: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _BadraBrandHeader(),
                        const SizedBox(height: 32),
                        _buildGlassCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(210),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(40),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(31),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGlowingIcon(),
              const SizedBox(height: 20),
              _buildStatusBadge(),
              const SizedBox(height: 20),
              Text(
                'تم إرسال طلبك بنجاح',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'حرصاً على أمان محفظتك وأموالك، تتم مراجعة وتفعيل الحسابات يدوياً من قبل إدارة بذرة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _buildUserInfoCard(),
              const SizedBox(height: 28),
              _buildWhatsAppButton(),
              const SizedBox(height: 16),
              _buildBackToLoginButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard() {
    final displayName = _name.isNotEmpty ? _name : 'المستخدم الجديد';
    final displayPhone = _phone.isNotEmpty ? _phone.withoutCountryCode() : 'غير مسجل';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDeep.withAlpha(160),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.emeraldPrimary.withAlpha(35),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.goldAccent.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: AppTheme.goldAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اسم صاحب الطلب',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              color: Colors.white10,
              height: 1,
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldPrimary.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone_iphone_rounded,
                  size: 18,
                  color: AppTheme.emeraldPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'رقم الهاتف المسجل',
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayPhone,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.emeraldPrimary,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (_phone.isNotEmpty)
                IconButton(
                  tooltip: 'نسخ الرقم',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _phone));
                    BadraLuxuryToast.show(
                      context,
                      'تم نسخ رقم الهاتف',
                      type: BadraToastType.success,
                    );
                  },
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppTheme.goldAccent.withAlpha(21),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.goldAccent.withAlpha(64),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.emeraldPrimary.withAlpha(38),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emeraldPrimary.withAlpha(44),
              blurRadius: 24,
            ),
          ],
        ),
        child: const Icon(
          Icons.hourglass_top_rounded,
          size: 38,
          color: AppTheme.goldAccent,
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.goldAccent.withAlpha(21),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.goldAccent.withAlpha(64),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_clock_rounded,
            size: 14,
            color: AppTheme.goldAccent,
          ),
          const SizedBox(width: 8),
          Text(
            'قيد المراجعة والتدقيق',
            style: GoogleFonts.sora(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.goldAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF25D366), // لون واتساب الرسمي
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF25D366).withAlpha(100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _isLoadingWhatsApp ? null : _openActivationWhatsApp,
        icon: _isLoadingWhatsApp
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.chat_bubble_outline_rounded, size: 20),
        label: Text(
          'التواصل مع الدعم عبر واتساب',
          style: GoogleFonts.sora(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBackToLoginButton() {
    return TextButton(
      onPressed: () {
        Navigator.pushReplacementNamed(context, AppRoutes.signUpLogin);
      },
      child: Text(
        'العودة إلى تسجيل الدخول',
        style: GoogleFonts.sora(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _BadraBrandHeader extends StatelessWidget {
  const _BadraBrandHeader();

  @override
  Widget build(BuildContext context) {
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
            fontWeight: FontWeight.normal,
            color: AppTheme.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
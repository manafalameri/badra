import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/home_controller.dart';
import '../../core/notification_preference_service.dart';
import '../../core/security_service.dart';
import '../../core/string_utils.dart';
import '../../core/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../widgets/badra_luxury_toast.dart';

class ProfileScreen extends StatefulWidget {
  final String userName;
  final String userPhone;
  final String balance;
  final String joinedAt;

  const ProfileScreen({
    super.key,
    this.userName = 'المستخدم',
    this.userPhone = '',
    this.balance = '0',
    this.joinedAt = '',
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // final String _userName = 'محمد سالم العمري';
  // final String _phone = '779025473';
  final String _joinDate = '00/00/0000';

  late final AuthController _authController;
  bool _securityLoading = false;
  bool _notificationEnabled = true;
  bool _notificationLoading = false;

  String get _supportWhatsAppNumber {
    final digits = widget.userPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('967') && digits.length >= 12) {
      return digits;
    }
    if (digits.startsWith('7') && digits.length == 9) {
      return '967$digits';
    }
    if (digits.startsWith('0') && digits.length == 10) {
      return '967${digits.substring(1)}';
    }
    return '967730975496';
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return parts[0].isNotEmpty ? parts[0][0] : '?';
  }

  @override
  void initState() {
    super.initState();
    _authController = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>()
        : Get.put(AuthController());
    _authController.loadSecurityState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final enabled = await NotificationPreferenceService.instance.isEnabled();
    if (mounted) setState(() => _notificationEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await Get.find<HomeController>().retry();
        },
        color: AppTheme.emeraldPrimary,
        backgroundColor: AppTheme.surfaceDark,
        displacement: 40,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildProfileHeader()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildAccountDetailsCard(),
                    const SizedBox(height: 16),
                    _buildSettingsList(),
                    const SizedBox(height: 24),
                    _buildVersionFooter(),
                    const SizedBox(height: 16),
                    _buildCloseAccountButton(),
                    const SizedBox(height: 16),
                    _buildLogoutButton(),
                    SizedBox(
                      height: 40 + MediaQuery.of(context).padding.bottom,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D2A1A), Color(0xFF080F0C)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            children: [
              // Glowing avatar
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.emeraldPrimary, AppTheme.emeraldDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.emeraldPrimary.withAlpha(102),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: AppTheme.emeraldPrimary.withAlpha(38),
                      blurRadius: 50,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _getInitials(widget.userName),
                    style: GoogleFonts.sora(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.backgroundDeep,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.userName,
                style: GoogleFonts.sora(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBadge(
                    'عضو VIP',
                    AppTheme.goldAccent,
                    Icons.star_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildBadge(
                    'نشط',
                    AppTheme.emeraldPrimary,
                    Icons.circle,
                    small: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.userPhone.withoutCountryCode(),
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    String label,
    Color color,
    IconData icon, {
    bool small = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(89), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 7 : 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDetailsCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(153),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(38),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  'معلومات الحساب',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              _buildInfoTile(
                icon: Icons.phone_outlined,
                label: 'رقم الهاتف',
                value: widget.userPhone.withoutCountryCode(),
              ),
              _buildTileDivider(),
              _buildInfoTile(
                icon: Icons.verified_outlined,
                label: 'حالة الحساب',
                value: 'نشط',
                valueColor: AppTheme.emeraldPrimary,
                trailing: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.emeraldPrimary.withAlpha(128),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              _buildTileDivider(),
              _buildInfoTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'الرصيد الحالي',
                value: '${widget.balance} ريال',
                valueColor: AppTheme.emeraldPrimary,
              ),
              _buildTileDivider(),
              _buildInfoTile(
                icon: Icons.calendar_month_outlined,
                label: 'تاريخ الانضمام',
                value: widget.joinedAt.isNotEmpty ? widget.joinedAt : _joinDate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.emeraldPrimary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppTheme.emeraldPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: valueColor ?? AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildTileDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.emeraldPrimary.withAlpha(18),
    );
  }

  Widget _buildSettingsList() {
    final settings = [
      {
        'icon': Icons.fingerprint_rounded,
        'label': 'إعدادات الأمان',
        'color': AppTheme.emeraldPrimary,
      },
      {
        'icon': Icons.notifications_outlined,
        'label': 'الإشعارات',
        'color': AppTheme.emeraldPrimary,
      },
      {
        'icon': Icons.pin_rounded,
        'label': 'نسيت رمز الأمان؟',
        'color': AppTheme.emeraldPrimary,
      },
      {
        'icon': Icons.help_outline_rounded,
        'label': 'مركز المساعدة',
        'color': AppTheme.emeraldPrimary,
      },
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(153),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(31),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  'الإعدادات',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...settings.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                final label = s['label'] as String;
                return Column(
                  children: [
                    if (i > 0)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        color: AppTheme.emeraldPrimary.withAlpha(18),
                      ),
                    if (label == 'إعدادات الأمان')
                      _buildSecurityToggleTile()
                    else if (label == 'الإشعارات')
                      _buildNotificationToggleTile()
                    else
                      _buildSettingTile(
                        icon: s['icon'] as IconData,
                        label: label,
                        color: s['color'] as Color,
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isHelpCenter = label == 'مركز المساعدة';
    final isForgotPin = label == 'نسيت رمز الأمان؟';
    return InkWell(
      onTap: onTap ?? (isHelpCenter
          ? _openHelpCenter
          : isForgotPin
              ? _openForgotPinWhatsApp
              : () {}),
      splashColor: AppTheme.emeraldPrimary.withAlpha(13),
      highlightColor: AppTheme.emeraldPrimary.withAlpha(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withAlpha(38), width: 1),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_back_ios_rounded,
              size: 14,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityToggleTile() {
    return Obx(() {
      final enabled = _authController.biometricEnabled.value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.emeraldPrimary.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.emeraldPrimary.withAlpha(38),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.fingerprint_rounded,
                size: 17,
                color: AppTheme.emeraldPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تفعيل الدخول بالبصمة',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'استخدم أمان الجهاز (بصمة أو PIN) لتسجيل الدخول السريع.',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              activeThumbColor: AppTheme.emeraldPrimary,
              activeTrackColor: AppTheme.emeraldPrimary.withAlpha(80),
              inactiveThumbColor: AppTheme.textSecondary,
              inactiveTrackColor: AppTheme.textMuted.withAlpha(28),
              onChanged: _securityLoading ? null : _handleBiometricToggle,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildNotificationToggleTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.emeraldPrimary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(38),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.notifications_outlined,
              size: 17,
              color: AppTheme.emeraldPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفعيل الإشعارات',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'استلم إشعارات طلبات الدفع الجديدة.',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _notificationEnabled,
            activeThumbColor: AppTheme.emeraldPrimary,
            activeTrackColor: AppTheme.emeraldPrimary.withAlpha(80),
            inactiveThumbColor: AppTheme.textSecondary,
            inactiveTrackColor: AppTheme.textMuted.withAlpha(28),
            onChanged: _notificationLoading ? null : _handleNotificationToggle,
          ),
        ],
      ),
    );
  }

  void _handleBiometricToggle(bool enabled) async {
    setState(() => _securityLoading = true);
    final result = await _authController.changeBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _securityLoading = false);

    if (!result) {
      BadraLuxuryToast.show(
        context,
        'لا يمكن تفعيل الدخول بالبصمة حالياً. تأكد من إعدادات الجهاز وحاول مرة أخرى.',
        type: BadraToastType.error,
      );
      return;
    }

    if (!enabled) {
      await SecurityService.instance.clearRefreshToken();
      await SecurityService.instance.clearAccessToken();
    }

    if (!mounted) return;

    BadraLuxuryToast.show(
      context,
      enabled
          ? 'تم تفعيل الدخول بالبصمة بنجاح.'
          : 'تم تعطيل الدخول بالبصمة.',
      type: BadraToastType.success,
    );
  }

  Future<void> _handleNotificationToggle(bool enabled) async {
    setState(() => _notificationLoading = true);
    await NotificationPreferenceService.instance.setEnabled(enabled);
    if (mounted) setState(() {
      _notificationEnabled = enabled;
      _notificationLoading = false;
    });
    if (!mounted) return;
    BadraLuxuryToast.show(
      context,
      enabled ? 'تم تفعيل الإشعارات.' : 'تم تعطيل الإشعارات.',
      type: BadraToastType.success,
    );
  }

  Widget _buildCloseAccountButton() {
    return GestureDetector(
      onTap: () => _showCloseAccountDialog(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.error.withAlpha(12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withAlpha(51), width: 1),
              boxShadow: [
                BoxShadow(color: AppTheme.error.withAlpha(15), blurRadius: 12),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.delete_forever_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  'إغلاق الحساب',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCloseAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark.withAlpha(242),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.error.withAlpha(51),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.error.withAlpha(26),
                      border: Border.all(
                        color: AppTheme.error.withAlpha(77),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: AppTheme.error,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'إغلاق الحساب',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'إغلاق الحساب نهائي ويحذف جميع بياناتك الشخصية. '
                    'سيُطلب منك إدخال كود الأمان، ولا يمكن الإغلاق إلا برصيد صفر. '
                    'هل أنت متأكد من رغبتك في المتابعة؟',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(
                              color: AppTheme.emeraldMuted.withAlpha(102),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).pushNamed(AppRoutes.closeAccount);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error,
                            foregroundColor: AppTheme.textPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'متابعة',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: () => _showLogoutDialog(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.error.withAlpha(15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withAlpha(64), width: 1),
              boxShadow: [
                BoxShadow(color: AppTheme.error.withAlpha(20), blurRadius: 12),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  'تسجيل الخروج',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionFooter() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(153),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.emeraldPrimary.withAlpha(31),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppTheme.emeraldPrimary.withAlpha(180),
              ),
              const SizedBox(width: 8),
              Text(
                'إصدار التطبيق 1.0.0',
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>> _collectDeviceInfo() async {
    String deviceId = '';
    String deviceName = '';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        deviceId = info.browserName.name.toLowerCase();
        deviceName = info.browserName.name;
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await deviceInfo.androidInfo;
            deviceId = info.id;
            deviceName = '${info.brand} ${info.model}'.trim();
            break;
          case TargetPlatform.iOS:
            final info = await deviceInfo.iosInfo;
            deviceId = info.identifierForVendor ?? '';
            deviceName = '${info.name} ${info.model}'.trim();
            break;
          case TargetPlatform.windows:
            final info = await deviceInfo.windowsInfo;
            deviceId = info.deviceId;
            deviceName = info.computerName;
            break;
          case TargetPlatform.macOS:
            final info = await deviceInfo.macOsInfo;
            deviceId = info.systemGUID ?? '';
            deviceName = info.computerName;
            break;
          case TargetPlatform.linux:
            final info = await deviceInfo.linuxInfo;
            deviceId = info.machineId ?? '';
            deviceName = '${info.name} ${info.prettyName}'.trim();
            break;
          default:
            break;
        }
      }
    } catch (_) {}
    return {'deviceId': deviceId, 'deviceName': deviceName};
  }

  Future<void> _openForgotPinWhatsApp() async {
    final deviceInfo = await _collectDeviceInfo();
    final name = widget.userName;
    final phone = widget.userPhone.withoutCountryCode();
    final walletId = widget.userPhone.toWalletId();

    final message = Uri.encodeComponent(
      'السلام عليكم ورحمة الله وبركاته،\n'
      'أنا $name،\n'
      'رقم هاتفي $phone،\n'
      'ورقم بطاقتي $walletId\n'
      'بيانات الجهاز:\n'
      '- معرّف الجهاز: ${deviceInfo['deviceId']}\n'
      '- نوع الجهاز: ${deviceInfo['deviceName']}.\n'
      'نسيت رمز الأمان الخاص بحسابي في تطبيق بذرة، '
      'وأرجو مساعدتكم في استعادة الوصول لحسابي. لكم جزيل الشكر.\n'
      'جزاكم الله خيراً.',
    );
    final uri = Uri.parse('https://wa.me/967730975496?text=$message');

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('تعذر فتح واتساب');
      }
    } catch (e) {
      if (mounted) {
        BadraLuxuryToast.show(
          context,
          'لا يمكن فتح واتساب الآن. ${e.toString()}',
          type: BadraToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<void> _openHelpCenter() async {
    final message = 'السلام عليكم، أحتاج مساعدة في تطبيق بذرة';
    final uri = Uri.parse('https://wa.me/967730975496?text=$message');

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('تعذر فتح واتساب');
      }
    } catch (e) {
      if (mounted) {
        BadraLuxuryToast.show(
          context,
          'لا يمكن فتح واتساب الآن. ${e.toString()}',
          type: BadraToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark.withAlpha(242),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.error.withAlpha(51),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.error.withAlpha(26),
                      border: Border.all(
                        color: AppTheme.error.withAlpha(77),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: AppTheme.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'تسجيل الخروج',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'هل أنت متأكد من رغبتك في تسجيل الخروج من حسابك؟',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(
                              color: AppTheme.emeraldMuted.withAlpha(102),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final navigator = Navigator.of(context);
                            try {
                              await SupabaseService.signOut();
                            } catch (_) {
                              print('Failed to sign out from Supabase');
                            }
                            try {
                              await SecurityService.instance.clearAllSession();
                              await SecurityService.instance.clearLoginTimestamp();
                            } catch (_) {
                              print('Failed to clear session on logout');
                            }
                            try {
                              await SecurityService.instance.clearPhone();
                            } catch (_) {
                              print('Failed to clear saved phone on logout');
                            }
                            try {
                              if (Get.isRegistered<HomeController>()) {
                                Get.delete<HomeController>(force: true);
                              }
                            } catch (_) {
                              print(
                                'Failed to delete HomeController on logout',
                              );
                            }
                            if (!mounted) return;
                            navigator.pushNamedAndRemoveUntil(
                              AppRoutes.signUpLogin,
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error,
                            foregroundColor: AppTheme.textPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            'خروج',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
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

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/home_controller.dart';
import '../../core/string_utils.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badra_luxury_toast.dart';
import './widgets/home_header_widget.dart';
import './widgets/luxury_card_widget.dart';
import './widgets/recent_transactions_widget.dart';
import './widgets/deposit_bottom_sheet.dart';

class HomeScreen extends StatelessWidget {
  final String userName;
  final String userPhone;
  final String walletId;
  final String balance;
  final VoidCallback? onNavigateToHistory;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onNavigateToPaymentRequests;

  const HomeScreen({
    super.key,
    this.userName = 'المستخدم',
    this.userPhone = '',
    this.walletId = '',
    this.balance = '0',
    this.onNavigateToHistory,
    this.onNavigateToProfile,
    this.onNavigateToPaymentRequests,
  });

  String get _formattedCardNumber {
    final digits = userPhone.toLatinDigits().replaceAll(RegExp(r'[^0-9]'), '');
    final phoneSegment = digits.length >= 9
        ? digits.substring(digits.length - 9)
        : digits.padLeft(9, '0');
    final rawNumber = '101$phoneSegment';
    return _formatCardNumber(rawNumber);
  }

  String _formatCardNumber(String value) {
    final digits = value.toLatinDigits().replaceAll(RegExp(r'[^0-9]'), '');
    final groups = RegExp(
      r'.{1,4}',
    ).allMatches(digits).map((m) => m.group(0)).whereType<String>().toList();
    return groups.join(' ');
  }

  String get _supportWhatsAppNumber {
    final digits = userPhone.toLatinDigits().replaceAll(RegExp(r'[^0-9]'), '');
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

  void _showDepositSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DepositBottomSheet(),
    );
  }


  Future<void> _openSupportWhatsApp(BuildContext context) async {
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
      if (!context.mounted) return;
      BadraLuxuryToast.show(
        context,
        'لا يمكن فتح واتساب الآن. ${e.toString()}',
        type: BadraToastType.error,
        duration: const Duration(seconds: 4),
      );
    }
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: Column(
            children: [
            HomeHeaderWidget(
              userName: userName,
              onProfileTap: onNavigateToProfile,
            ),
            const SizedBox(height: 24),
            // Card with WhatsApp support icon overlay
            Stack(
              clipBehavior: Clip.none,
              children: [
                LuxuryCardWidget(
                  holderName: userName,
                  cardNumber: walletId.isNotEmpty
                      ? _formatCardNumber(walletId)
                      : _formattedCardNumber,
                  balance: balance,
                ),
                // WhatsApp support floating icon on card corner
                Positioned(
                  bottom: -14,
                  left: 32,
                  child: GestureDetector(
                    onTap: () => _openSupportWhatsApp(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF25D366).withAlpha(100),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.backgroundDeep,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // Action Buttons — Deposit (Right in RTL) & Payment Requests (Left in RTL)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'شحن',
                      icon: Icons.arrow_downward_rounded,
                      color: AppTheme.emeraldPrimary,
                      onTap: () => _showDepositSheet(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      label: 'طلبات الدفع',
                      icon: Icons.payments_rounded,
                      color: AppTheme.emeraldPrimary,
                      onTap: () => onNavigateToPaymentRequests?.call(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            RecentTransactionsWidget(onViewAll: onNavigateToHistory),
            const SizedBox(height: 120),
          ],
        ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool fullWidth;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          vertical: fullWidth ? 14 : 14,
          horizontal: fullWidth ? 20 : 0,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(60), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: fullWidth
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );

    return content;
  }
}

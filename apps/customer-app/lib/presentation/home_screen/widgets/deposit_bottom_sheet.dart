import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../controllers/deposit_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/badra_luxury_toast.dart';

class BankInfo {
  final String bankName;
  final String imagePath;

  const BankInfo({required this.bankName, required this.imagePath});
}

const List<BankInfo> kBanks = [
  BankInfo(bankName: 'العمقي', imagePath: 'assets/images/banks/al_amr.jpg'),
  BankInfo(bankName: 'الكريمي', imagePath: 'assets/images/banks/kuraim.png'),
  BankInfo(bankName: 'البسيري', imagePath: 'assets/images/banks/busairi.png'),
  BankInfo(bankName: 'القطيبي', imagePath: 'assets/images/banks/qutaibi.png'),
];

class DepositBottomSheet extends StatelessWidget {
  const DepositBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<DepositController>(
      init: DepositController(),
      builder: (controller) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.backgroundMid,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: _buildContent(controller),
          ),
        );
      },
    );
  }

  Future<void> _openWhatsApp(String bankName) async {
    final message = Uri.encodeComponent(
      'أهلاً بذرة، قمت بشحن مبلغ عبر $bankName، الرجاء توجيهه لحسابي.',
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
      BadraLuxuryToast.show(
        Get.context!,
        'لا يمكن فتح واتساب الآن. ${e.toString()}',
        type: BadraToastType.error,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    BadraLuxuryToast.show(
      context,
      'تم النسخ',
      type: BadraToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildContent(DepositController controller) {
    if (controller.error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'خطأ في تحميل بيانات الشحن: ${controller.error}',
                style: GoogleFonts.sora(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: controller.retry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.emeraldMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          _buildHeader(controller),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'أرسل المبلغ إلى أحد حسابات الشحن التالية ثم أرسل إشعاراً عبر واتساب',
              style: GoogleFonts.sora(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kBanks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final bank = kBanks[index];
              final accountNumber = _getAccountNumber(controller, index);
              return _BankTile(
                bank: bank,
                accountNumber: accountNumber,
                onCopy: accountNumber != null
                    ? () => _copyToClipboard(context, accountNumber)
                    : null,
                onWhatsApp: () => _openWhatsApp(bank.bankName),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String? _getAccountNumber(DepositController controller, int index) {
    switch (index) {
      case 0:
        return controller.bank1.value.isNotEmpty
            ? controller.bank1.value
            : null;
      case 1:
        return controller.bank2.value.isNotEmpty
            ? controller.bank2.value
            : null;
      case 2:
        return controller.bank3.value.isNotEmpty
            ? controller.bank3.value
            : null;
      case 3:
        return controller.bank4.value.isNotEmpty
            ? controller.bank4.value
            : null;
      default:
        return null;
    }
  }

  Widget _buildHeader(DepositController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'شحن الرصيد - قنوات الشحن',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.isLoading.value
                ? 'جارٍ التحميل...'
                : controller.userName.value,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  final BankInfo bank;
  final String? accountNumber;
  final VoidCallback? onCopy;
  final VoidCallback onWhatsApp;

  const _BankTile({
    required this.bank,
    required this.accountNumber,
    required this.onCopy,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderGlass, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emeraldPrimary.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 52,
                  height: 52,
                  color: AppTheme.backgroundDeep,
                  child: Image.asset(bank.imagePath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.bankName,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onCopy,
                      child: Row(
                        children: [
                          Expanded(
                            child: accountNumber == null
                                ? Row(
                                    children: const [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'جارٍ التحميل...',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    accountNumber!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.sora(
                                      fontSize: 14,
                                      color: AppTheme.textSecondary,
                                    ).copyWith(fontFamily: 'monospace'),
                                  ),
                          ),
                          if (accountNumber != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.copy,
                              size: 16,
                              color: AppTheme.emeraldPrimary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onWhatsApp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emeraldPrimary,
              foregroundColor: AppTheme.backgroundDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.message, size: 16),
                const SizedBox(width: 8),
                Text(
                  'إرسال إشعار',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

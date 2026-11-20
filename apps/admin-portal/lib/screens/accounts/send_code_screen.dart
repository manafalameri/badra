import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_theme.dart';

class SendCodeScreen extends StatelessWidget {
  final String userId;
  final String phone;
  final String? initialCode;

  const SendCodeScreen({
    super.key,
    required this.userId,
    required this.phone,
    this.initialCode,
  });

  String get _cleanPhone {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.startsWith('967')) return cleaned;
    if (cleaned.startsWith('0')) return '967${cleaned.substring(1)}';
    return cleaned;
  }

  String _smsMessage(String code) {
    return '''السلام عليكم ورحمة الله وبركاته

شكراً جزيلاً على انتظارك. تم إنشاء حسابك بنجاح في تطبيق بذرة.

كود التفعيل الخاص بك هو:
$code

يرجى استخدام هذا الكود لتفعيل حسابك في التطبيق.

مع تحيات فريق بذرة''';
  }

  Future<void> _sendSms(String code, BuildContext context) async {
    final message = _smsMessage(code);
    final uri = Platform.isAndroid
        ? Uri.parse('sms:$_cleanPhone?body=${Uri.encodeComponent(message)}')
        : Uri.parse('sms:$_cleanPhone&body=${Uri.encodeComponent(message)}');

    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('فشل فتح تطبيق الرسائل',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _copyCode(String code, BuildContext context) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم نسخ الكود',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = initialCode ?? '------';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'إرسال كود التفعيل',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1a237e), Color(0xFF1565C0)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'تم إنشاء الحساب بنجاح',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أرسل كود التفعيل إلى الزبون',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('رقم الجوال', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(phone, style: AppTextStyles.body),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('كود التفعيل', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _copyCode(code, context),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('نسخ الكود',
                          style: TextStyle(fontFamily: 'Cairo')),
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sms_outlined,
                          color: AppColors.primary, size: 20),
                      SizedBox(width: 8),
                      Text('رسالة التفعيل',
                          style: AppTextStyles.heading3),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _smsMessage(code),
                      style: AppTextStyles.body.copyWith(height: 1.8),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _sendSms(code, context),
                icon: const Icon(Icons.send_rounded, size: 22),
                label: const Text(
                  'إرسال عبر SMS',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text(
                  'تم الإرسال',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

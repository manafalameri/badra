import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/merchant_service.dart';
import '../../widgets/app_theme.dart';

class AddMerchantScreen extends StatefulWidget {
  const AddMerchantScreen({super.key});

  @override
  State<AddMerchantScreen> createState() => _AddMerchantScreenState();
}

class _AddMerchantScreenState extends State<AddMerchantScreen> {
  final _nameCtrl = TextEditingController();
  final _webhookCtrl = TextEditingController();
  bool _isLoading = false;
  String? _generatedKey;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _webhookCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'الرجاء إدخال اسم المتجر');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _generatedKey = null;
    });

    final result = await MerchantService.createMerchant(
      name: name,
      webhookUrl: _webhookCtrl.text.trim(),
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _generatedKey = result['api_key'] as String?;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result['error'] as String? ?? 'فشل إنشاء المتجر';
        _isLoading = false;
      });
    }
  }

  void _copyAndFinish() {
    if (_generatedKey != null) {
      Clipboard.setData(ClipboardData(text: _generatedKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم نسخ المفتاح بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إضافة متجر جديد',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_generatedKey != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'تم إنشاء المتجر بنجاح',
                      style: AppTextStyles.heading3,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'مفتاح API (لن يظهر مرة أخرى):',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: SelectableText(
                        _generatedKey!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'انسخ المفتاح الآن. لن تتمكن من رؤيته مرة أخرى.',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _copyAndFinish,
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('نسخ المفتاح والعودة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيانات المتجر',
                        style: AppTextStyles.heading3),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameCtrl,
                      textDirection: TextDirection.rtl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم المتجر *',
                        hintText: 'مثال: برسم',
                        prefixIcon: Icon(Icons.store_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _webhookCtrl,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _create(),
                      decoration: const InputDecoration(
                        labelText: 'رابط Webhook (اختياري)',
                        hintText: 'https://example.com/webhook',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _create,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                        label: Text(
                          _isLoading ? 'جارٍ الإنشاء...' : 'إنشاء المتجر',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
    );
  }
}

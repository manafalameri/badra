import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_theme.dart';

class CampaignCodesScreen extends StatefulWidget {
  const CampaignCodesScreen({super.key});

  @override
  State<CampaignCodesScreen> createState() => _CampaignCodesScreenState();
}

class _CampaignCodesScreenState extends State<CampaignCodesScreen> {
  bool _isLoading = true;
  List<String> _codes = [];
  DateTime? _dbCreatedAt;
  String? _campaignDate;
  DateTime? _dbExpiresAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await SupabaseService.getTodayCampaignCodes();
      if (!mounted) return;

      if (data.isEmpty) {
        setState(() {
          _codes = [];
          _isLoading = false;
        });
        return;
      }

      final codes = data
          .map((item) => item['coupon_code']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();

      final first = data.first;
      DateTime? dbCreatedAt;
      if (first['db_created_at'] != null) {
        dbCreatedAt = DateTime.tryParse(first['db_created_at'].toString())?.toLocal();
      } else if (first['created_at'] != null) {
        dbCreatedAt = DateTime.tryParse(first['created_at'].toString())?.toLocal();
      }

      DateTime? dbExpiresAt;
      if (first['db_expires_at'] != null) {
        dbExpiresAt = DateTime.tryParse(first['db_expires_at'].toString())?.toLocal();
      } else if (dbCreatedAt != null) {
        dbExpiresAt = dbCreatedAt.add(const Duration(hours: 6));
      }

      final campaignDate = first['campaign_date']?.toString();

      setState(() {
        _codes = codes;
        _dbCreatedAt = dbCreatedAt;
        _campaignDate = campaignDate;
        _dbExpiresAt = dbExpiresAt;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر جلب الأكواد: $e';
        _isLoading = false;
      });
    }
  }

  void _copyAllForWhatsApp() {
    if (_codes.isEmpty) return;

    final buffer = StringBuffer();
    final dateStr = _campaignDate ?? (_dbCreatedAt != null ? DateFormat('yyyy-MM-dd').format(_dbCreatedAt!) : '');
    buffer.writeln('🔥 *عروض الخصم الفوري ليوم ($dateStr) من بدرا!* 🔥');
    if (_dbExpiresAt != null) {
      buffer.writeln('⏰ صالحة حتى: ${DateFormat('hh:mm a', 'ar').format(_dbExpiresAt!)} (6 ساعات فقط)');
    } else {
      buffer.writeln('⏰ صالحة لمدة 6 ساعات فقط من وقت الإصدار');
    }
    buffer.writeln('💰 خصومات عشوائية مميزة تصل حتى *20%* على طلبك!');
    buffer.writeln('⚠️ كل كود صالح للاستخدام مرة واحدة فقط (من يسبق يفوز):\n');

    for (int i = 0; i < _codes.length; i++) {
      buffer.writeln('${i + 1}. `${_codes[i]}`');
    }

    buffer.writeln('\n💡 *طريقة الاستخدام:*');
    buffer.writeln('اطلب من المتجر، وعند تأكيد الدفع في محفظة بدرا، الصق الكود في خانة كود الخصم واستمتع بالتوفير الفوري!');

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'تم نسخ رسالة الواتساب الجاهزة بنجاح!',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _copySingleCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم نسخ الكود: $code',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'أكواد حملة اليوم (50 كود)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'تحديث',
            onPressed: _loadCodes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadCodes,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة',
                              style: TextStyle(fontFamily: 'Cairo')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _codes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_offer_outlined,
                              size: 64, color: AppColors.textSecondary),
                          const SizedBox(height: 16),
                          const Text(
                            'لم يتم توليد حملة لليوم حتى الآن\n(تنطلق تلقائياً الساعة 5:00 فجراً)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _loadCodes,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('تحديث القائمة',
                                style: TextStyle(fontFamily: 'Cairo')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Header Banner
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.campaign_rounded,
                                      color: Colors.white, size: 28),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'حملة اليوم نشطة 🔥',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_codes.length} كود',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.verified_rounded, size: 16, color: Colors.greenAccent),
                                        const SizedBox(width: 6),
                                        Text(
                                          _campaignDate != null 
                                              ? '📅 تاريخ الحملة بالسيرفر: $_campaignDate' 
                                              : '📅 تاريخ الحملة بالسيرفر: اليوم',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _dbCreatedAt != null
                                          ? '⏰ أُنشئت بالسيرفر: ${DateFormat('yyyy-MM-dd  •  hh:mm:ss a', 'ar').format(_dbCreatedAt!)}'
                                          : '⏰ وقت الإصدار: مسجل في السيرفر',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                    if (_dbExpiresAt != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '⏳ تنتهي الصلاحية بالسيرفر: ${DateFormat('hh:mm:ss a', 'ar').format(_dbExpiresAt!)} (6 ساعات)',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: Colors.white.withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _copyAllForWhatsApp,
                                  icon: const Icon(Icons.share_rounded,
                                      color: Color(0xFF1B5E20)),
                                  label: const Text(
                                    'نسخ رسالة الواتساب الجاهزة 📋',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B5E20),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Subtitle note
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              const Icon(Icons.security_rounded,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'الأكواد مجهولة النسب 100% لتحقيق العدالة ومنع التسريب',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Codes Grid
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: GridView.builder(
                              itemCount: _codes.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 2.6,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemBuilder: (context, index) {
                                final code = _codes[index];
                                return InkWell(
                                  onTap: () => _copySingleCode(code),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.divider,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: AppColors.primary
                                              .withValues(alpha: 0.1),
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          code,
                                          style: const TextStyle(
                                            fontFamily: 'Courier',
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(
                                          Icons.copy_rounded,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum LegalType { terms, privacy }

class BadraLegalModal extends StatelessWidget {
  final LegalType type;

  const BadraLegalModal({super.key, required this.type});

  static Future<void> showTerms(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BadraLegalModal(type: LegalType.terms),
    );
  }

  static Future<void> showPrivacy(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BadraLegalModal(type: LegalType.privacy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTerms = type == LegalType.terms;
    final title = isTerms ? 'الشروط والأحكام' : 'سياسة الخصوصية';
    final icon = isTerms ? Icons.gavel_rounded : Icons.shield_outlined;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: AppTheme.backgroundDeep,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: AppTheme.borderGlow, width: 1.5),
            left: BorderSide(color: AppTheme.borderGlass, width: 1),
            right: BorderSide(color: AppTheme.borderGlass, width: 1),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.emeraldMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldDark.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderGlass),
                    ),
                    child: Icon(icon, color: AppTheme.emeraldPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.sora(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'تطبيق بذرة (Badra) — المحفظة المغلقة',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.borderGlass, height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: isTerms ? _buildTermsContent() : _buildPrivacyContent(),
                ),
              ),
            ),

            // Bottom Button
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceDark,
                border: Border(top: BorderSide(color: AppTheme.borderGlass)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emeraldPrimary,
                      foregroundColor: AppTheme.backgroundDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isTerms ? 'فهمت وأوافق على الشروط' : 'إغلاق',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTermsContent() {
    return [
      _buildHighlightCard(
        title: 'محفظة إلكترونية مغلقة',
        content:
            'الرصيد الذي تشحنه يُستخدم حصرياً في شراء المنتجات والخدمات من المتاجر التابعة لمنصة بذرة داخل الجمهورية اليمنية. بذرة ليست خدمة تحويل أموال ولا توفر ميزة السحب النقدي.',
        icon: Icons.info_outline_rounded,
        borderColor: AppTheme.emeraldPrimary,
      ),
      const SizedBox(height: 16),
      _buildMetaRow('17 أغسطس 2026', 'مناف أحمد العامري'),
      const SizedBox(height: 20),
      _buildSection(
        '1. مقدمة وقبول الشروط',
        'مرحباً بك في تطبيق بذرة (Badra). باستخدامك للتطبيق فإنك توافق على هذه الشروط والأحكام بشكل كامل. إذا لم توافق عليها، يرجى عدم استخدام التطبيق. المشغّل لهذا التطبيق هو: مناف أحمد العامري داخل الجمهورية اليمنية.',
      ),
      _buildSection(
        '2. وصف الخدمة',
        'يوفر تطبيق بذرة للمستخدمين:\n'
            '• حساباً برصيد نقدي مسبق (محفظة مغلقة).\n'
            '• إمكانية شحن الرصيد عبر الحسابات المعتمدة (العمقي، الكريمي، القطيبي، البسيري).\n'
            '• الدفع داخل متاجر منصة بذرة بالموافقة الصريحة على طلبات الدفع الواردة.\n'
            '• سجل معاملات متكامل لكافة العمليات المالية.',
      ),
      _buildSection(
        '3. الأهلية والتسجيل',
        '• يجب أن يكون عمرك 18 عاماً أو أكثر.\n'
            '• يجب تقديم رقم هاتف يمني صالح وبيانات صحيحة.\n'
            '• الحساب شخصي ومحمي برمز PIN وكلمة المرور وكود الأمان، ولا يجوز تفويضه لطرف ثالث.\n'
            '• نستخدم أنظمة حماية متقدمة (RASP) وتشفير الاتصال لمنع التلاعب.',
      ),
      _buildSection(
        '4. شحن الرصيد والحدود المالية',
        '• الحد الأدنى لعملية الشحن: 500 ريال يمني.\n'
            '• الحد الأقصى لعملية الشحن: 250,000 ريال يمني.\n'
            '• يتم إضافة الرصيد بعد التحقق من إثبات الشحن البنكي من قبل إدارة المنصة.\n'
            '• بذرة لا تتحمل مسؤولية التحويل لحسابات غير معتمدة داخل التطبيق.',
      ),
      _buildSection(
        '5. القيود والاستخدام المحظور',
        '• يُحظر استخدام المحفظة في أي نشاط غير قانوني أو غسل أموال.\n'
            '• لا يوجد سحب نقدي أو بيع للرصيد خارج المنصة.\n'
            '• يُحظر تشغيل التطبيق على أجهزة معدلة برمجياً (Rooted).\n'
            '• يحق للإدارة تجميد أو إغلاق الحساب في حال الاشتباه بنشاط احتيالي.',
      ),
      _buildSection(
        '6. إغلاق الحساب وحذفه',
        'يحق لك إغلاق حسابك في أي وقت بشرط أن يكون الرصيد صفراً. وفقاً للمتطلبات القانونية، يتم الاحتفاظ بسجلات المعاملات المالية مع إخفاء الهوية الشخصية.',
      ),
      _buildSection(
        '7. القانون الحاكم والاتصال',
        'تخضع هذه الشروط لقوانين الجمهورية اليمنية.\n'
            'للتواصل: badraapp@gmail.com | هاتف: +967 730 975 496',
      ),
    ];
  }

  List<Widget> _buildPrivacyContent() {
    return [
      _buildHighlightCard(
        title: 'أمان وخصوصية بياناتك أولويتنا',
        content:
            'بياناتك المالية والشخصية مشفرة بالكامل. لن نبيع بياناتك ولن نشاركها لأغراض إعلانية أو تسويقية مع أي طرف ثالث.',
        icon: Icons.lock_outline_rounded,
        borderColor: AppTheme.goldAccent,
      ),
      const SizedBox(height: 16),
      _buildMetaRow('17 أغسطس 2026', 'الجمهورية اليمنية'),
      const SizedBox(height: 20),
      _buildSection(
        '1. من نحن',
        'تطبيق بذرة (Badra) مشغّل بواسطة مناف أحمد العامري داخل الجمهورية اليمنية. هذه السياسة توضح التزامنا الصارم بحماية بياناتك وخصوصيتك.',
      ),
      _buildSection(
        '2. البيانات التي نجمعها',
        '• بيانات الحساب: الاسم، رقم الهاتف، كلمة المرور المشفّرة، ورقم المحفظة.\n'
            '• البيانات المالية: الرصيد، سجل المعاملات، وإثباتات الشحن البنكية.\n'
            '• بيانات الجهاز والأمان: معرف الجهاز، البصمة (محلياً فقط)، وتشفير المفاتيح لمنع الاختراق.\n'
            '• تنبيه: لا نصل لجهات الاتصال، ولا للموقع الجغرافي، ولا لملفات هاتفك الشخصية.',
      ),
      _buildSection(
        '3. حماية البيانات والتشفير',
        '• تشفير كامل لكافة الاتصالات عبر HTTPS مع تقنية تثبيت الشهادات (SSL Pinning).\n'
            '• تخزين كلمات المرور ورموز الـ PIN بتشفير معقد لا يمكن فكه (bcrypt).\n'
            '• استخدام التخزين الآمن للأجهزة (Secure Storage) لحفظ الجلسات ومفاتيح التشفير.',
      ),
      _buildSection(
        '4. مقدمو الخدمات التقنية',
        'نعتمد على مزودين موثوقين فقط:\n'
            '• Supabase: لحفظ قاعدة البيانات والمصادقة بتشفير سحابي متقدم.\n'
            '• Firebase (Google): لإرسال إشعارات الدفع والعمليات المالية المباشرة.',
      ),
      _buildSection(
        '5. حقوقك وحذف الحساب',
        'يحق لك في أي وقت الاطلاع على بياناتك، تعديلها، أو طلب إغلاق الحساب وحذف البيانات الشخصية نهائياً عبر إعدادات التطبيق.',
      ),
      _buildSection(
        '6. الدعم والاستفسارات',
        'إذا كانت لديك أي استفسارات حول الخصوصية:\n'
            'البريد: badraapp@gmail.com | واتساب: +967 730 975 496',
      ),
    ];
  }

  Widget _buildHighlightCard({
    required String title,
    required String content,
    required IconData icon,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          right: BorderSide(color: borderColor, width: 4),
          top: BorderSide(color: borderColor.withValues(alpha: 0.2)),
          left: BorderSide(color: borderColor.withValues(alpha: 0.2)),
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: borderColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.sora(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: borderColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.sora(
              fontSize: 12.5,
              height: 1.6,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String date, String author) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderGlass),
          ),
          child: Text(
            'آخر تحديث: $date',
            style: GoogleFonts.sora(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderGlass),
          ),
          child: Text(
            author,
            style: GoogleFonts.sora(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.goldAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.sora(
              fontSize: 13,
              height: 1.7,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

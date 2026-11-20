import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'create_account_screen.dart';
import 'send_code_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Map<String, dynamic>> _waitingList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWaitingList();
  }

  Future<void> _loadWaitingList() async {
    setState(() => _isLoading = true);
    try {
      final list = await SupabaseService.getWaitingList();
      if (mounted) setState(() => _waitingList = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التحميل: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyRow(Map<String, dynamic> row) async {
    final text =
        'الاسم: ${row['name']}\nالرقم: ${row['phone']}';
    Clipboard.setData(ClipboardData(text: text));

    final phone = row['phone']?.toString() ?? '';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('جارٍ إنشاء الحساب...',
            style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );

    final result = await SupabaseService.approvePendingUser(phone);

    if (!mounted) return;

    if (result['success'] == true) {
      final userId = result['user']?.toString();
      final activationCode = result['activation_code']?.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم إنشاء الحساب بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );

      if (userId != null && userId.isNotEmpty && activationCode != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SendCodeScreen(
              userId: userId,
              phone: phone,
              initialCode: activationCode,
            ),
          ),
        );
      }

      _loadWaitingList();
    } else {
      final message = result['message']?.toString() ?? 'حدث خطأ غير معروف';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _openCreateAccount() async {
    final ok = await AuthService.authenticateWithBiometrics(
        'تحقق من هويتك لإنشاء حساب جديد');
    if (!ok || !mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateAccountScreen()),
    );
    if (result == true) _loadWaitingList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('إنشاء حساب',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadWaitingList,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateAccount,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text(
          'حساب جديد',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadWaitingList,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Row(
                          children: [
                            const SectionTitle(title: 'قائمة الانتظار'),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_waitingList.length} طلب',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                  if (_waitingList.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 64,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            const Text(
                              'قائمة الانتظار فارغة',
                              style: AppTextStyles.bodySecondary,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _WaitingListCard(
                            item: _waitingList[index],
                            onCopy: () => _copyRow(_waitingList[index]),
                            onDelete: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('حذف الطلب',
                                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                                  content: const Text('هل تريد حذف هذا الطلب من قائمة الانتظار؟',
                                      style: TextStyle(fontFamily: 'Cairo')),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('إلغاء',
                                          style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.error,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Text('حذف',
                                          style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              await SupabaseService.deleteFromWaitingList(
                                  _waitingList[index]['id']);
                              _loadWaitingList();
                            },
                          ),
                          childCount: _waitingList.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _WaitingListCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _WaitingListCard({
    required this.item,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(item['created_at'] ?? '');
    final formattedDate = date != null
        ? DateFormat('yyyy/MM/dd - HH:mm', 'en').format(date)
        : '--';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item['name'] ?? '',
                    style: AppTextStyles.heading3,
                  ),
                ),
                const _InfoChip(
                  label: 'في الانتظار',
                  color: AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 12),
            _InfoRow(
                icon: Icons.phone_outlined,
                label: 'الرقم',
                value: item['phone'] ?? ''),
            const SizedBox(height: 6),
            _InfoRow(
                icon: Icons.phone_android_rounded,
                label: 'الجهاز',
                value: item['device_name'] ?? ''),
            const SizedBox(height: 6),
            _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'التاريخ',
                value: formattedDate),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('نسخ',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text('$label: ',
            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value,
              style:
                  AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

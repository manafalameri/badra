import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/merchant_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'add_merchant_screen.dart';

class MerchantsScreen extends StatefulWidget {
  const MerchantsScreen({super.key});

  @override
  State<MerchantsScreen> createState() => _MerchantsScreenState();
}

class _MerchantsScreenState extends State<MerchantsScreen> {
  List<Map<String, dynamic>> _merchants = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMerchants();
  }

  Future<void> _loadMerchants() async {
    setState(() => _isLoading = true);
    try {
      final list = await MerchantService.listMerchants();
      if (mounted) setState(() => _merchants = list);
    } catch (_) {
      if (mounted) setState(() => _merchants = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMerchant(String id, bool currentActive) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          currentActive ? 'تعطيل المتجر' : 'تفعيل المتجر',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        content: Text(
          currentActive
              ? 'هل تريد تعطيل هذا المتجر؟ سيتم منع عمليات الدفع عبره.'
              : 'هل تريد تفعيل هذا المتجر؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentActive ? AppColors.error : AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(currentActive ? 'تعطيل' : 'تفعيل',
                style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await MerchantService.toggleMerchant(
      merchantId: id,
      isActive: !currentActive,
    );
    _loadMerchants();
  }

  Future<void> _openAddMerchant() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
    );
    if (result == true) _loadMerchants();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('المتاجر',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMerchants,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMerchant,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.store_rounded, color: Colors.white),
        label: const Text(
          'متجر جديد',
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
              onRefresh: _loadMerchants,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Row(
                          children: [
                            const SectionTitle(title: 'المتاجر المسجلة'),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_merchants.length} متجر',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                  if (_merchants.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.store_outlined,
                                size: 64,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            const Text(
                              'لا يوجد متاجر مسجلة',
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
                          (context, index) => _MerchantCard(
                            merchant: _merchants[index],
                            onToggle: () => _toggleMerchant(
                              _merchants[index]['id'],
                              _merchants[index]['is_active'] == true,
                            ),
                          ),
                          childCount: _merchants.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  final Map<String, dynamic> merchant;
  final VoidCallback onToggle;

  const _MerchantCard({
    required this.merchant,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(merchant['created_at'] ?? '');
    final formattedDate = date != null
        ? DateFormat('yyyy/MM/dd - HH:mm', 'en').format(date)
        : '--';
    final isActive = merchant['is_active'] == true;

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
                  child: const Icon(Icons.store_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    merchant['name'] ?? '',
                    style: AppTextStyles.heading3,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isActive ? AppColors.success : AppColors.textSecondary)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'نشط' : 'معطل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 12),
            _InfoRow(
                icon: Icons.vpn_key_rounded,
                label: 'مفتاح API',
                value: merchant['api_key_prefix'] ?? ''),
            if ((merchant['webhook_url'] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _InfoRow(
                    icon: Icons.link_rounded,
                    label: 'Webhook',
                    value: merchant['webhook_url'] ?? ''),
              ),
            const SizedBox(height: 6),
            _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'التاريخ',
                value: formattedDate),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                isActive ? 'تعطيل المتجر' : 'تفعيل المتجر',
                style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              value: isActive,
              activeThumbColor: AppColors.primary,
              onChanged: (_) => onToggle(),
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

  const _InfoRow({required this.icon, required this.label, required this.value});

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
              style: AppTextStyles.label.copyWith(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

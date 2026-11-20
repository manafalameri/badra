import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/home_controller.dart';
import '../../core/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badra_luxury_toast.dart';
import 'widgets/approval_dialog.dart';
import 'widgets/payment_request_card.dart';

class PaymentRequestsScreen extends StatefulWidget {
  final VoidCallback? onRequestsChanged;

  const PaymentRequestsScreen({super.key, this.onRequestsChanged});

  @override
  State<PaymentRequestsScreen> createState() => PaymentRequestsScreenState();
}

class PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;
  String? _lastApprovalMsg;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadRequestsSilent(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final requests = await SupabaseService.getMyPendingRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isLoading = false;
        _error = null;
      });
      widget.onRequestsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'فشل تحميل الطلبات';
      });
    }
  }

  Future<void> _loadRequestsSilent() async {
    try {
      final requests = await SupabaseService.getMyPendingRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _error = null;
      });
      widget.onRequestsChanged?.call();
    } catch (_) {}
  }

  Future<String> _collectDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        return info.browserName.name.toLowerCase();
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await deviceInfo.androidInfo;
          return info.id;
        case TargetPlatform.iOS:
          final info = await deviceInfo.iosInfo;
          return info.identifierForVendor ?? '';
        default:
          break;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _onApprove(Map<String, dynamic> request) async {
    final id = request['id'] as String;
    final rawMerchantName = (request['merchant_name'] as String? ?? '').trim();
    final merchantName = rawMerchantName.isEmpty || rawMerchantName == 'برسيم' || rawMerchantName.contains('برسيم') ? 'تليد' : rawMerchantName;
    final amount = (request['amount'] ?? 0).toString();
    final deviceId = await _collectDeviceId();
    final userBalance = Get.isRegistered<HomeController>() ? Get.find<HomeController>().balance.value : null;

    final approved = await Get.dialog<bool>(
      ApprovalDialog(
        merchantName: merchantName,
        amount: amount,
        requestId: id,
        deviceId: deviceId,
        orderRef: request['order_ref'] as String? ?? '',
        userBalance: userBalance,
        onApproved: ({
          required String securityCode,
          required String signature,
          required String timestamp,
          String? couponCode,
        }) async {
          final result = await SupabaseService.approvePaymentWithSignature(
            requestId: id,
            securityCode: securityCode,
            signature: signature,
            timestamp: timestamp,
            deviceId: deviceId,
            couponCode: couponCode,
          );
          if (result['success'] == true) {
            final discount = result['discount'];
            final finalAmount = result['final_amount'];
            if (result['coupon_applied'] == true && discount is num && discount > 0) {
              final finalStr = finalAmount is num ? finalAmount.toStringAsFixed(0) : finalAmount?.toString() ?? '0';
              _lastApprovalMsg = 'تم الدفع بنجاح لـ $merchantName!\nوفّرت ${discount.toStringAsFixed(0)} ر.ي بكود الخصم 🔥 (المدفوع: $finalStr ر.ي)';
            } else {
              _lastApprovalMsg = 'تمت الموافقة على الدفع لـ $merchantName بنجاح';
            }
          }
          return result;
        },
        onRejected: () {},
      ),
    );

    if (!mounted) return;

    if (approved == true) {
      _loadRequests();
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().retry();
      }
      BadraLuxuryToast.show(
        context,
        _lastApprovalMsg ?? 'تمت الموافقة على الدفع لـ $merchantName',
        type: BadraToastType.success,
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _onReject(Map<String, dynamic> request) async {
    final id = request['id'] as String;
    final merchantName = request['merchant_name'] as String? ?? '';

    final confirm = await Get.dialog<bool>(
      Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'تأكيد الرفض',
            style: GoogleFonts.sora(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'هل أنت متأكد من رفض طلب الدفع من $merchantName؟',
            style: GoogleFonts.sora(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text(
                'إلغاء',
                style: GoogleFonts.sora(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Get.back(result: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
              ),
              child: Text(
                'رفض',
                style: GoogleFonts.sora(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final result = await SupabaseService.rejectPaymentRequest(id);
    if (!mounted) return;
    if (result['success'] == true) {
      BadraLuxuryToast.show(
        context,
        'تم رفض طلب الدفع',
        type: BadraToastType.warning,
        duration: const Duration(seconds: 2),
      );
      _loadRequests();
    } else {
      BadraLuxuryToast.show(
        context,
        result['error']?.toString() ?? 'فشل الرفض',
        type: BadraToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppTheme.emeraldPrimary,
      backgroundColor: AppTheme.surfaceDark,
      displacement: 40,
      child: _isLoading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: const [
                SizedBox(height: 200),
                Center(
                  child: CircularProgressIndicator(color: AppTheme.emeraldPrimary),
                ),
              ],
            )
          : _error != null
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                const SizedBox(height: 150),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 48, color: AppTheme.error.withAlpha(150)),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: GoogleFonts.sora(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadRequests,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : _requests.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.2,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldPrimary.withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.payments_rounded,
                          size: 32,
                          color: AppTheme.emeraldPrimary.withAlpha(150),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد طلبات دفع معلقة',
                        style: GoogleFonts.sora(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'عند قدوم طلب دفع جديد سيظهر هنا',
                        style: GoogleFonts.sora(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.only(top: 12, bottom: 100),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final request = _requests[index];
                return PaymentRequestCard(
                  request: request,
                  onApprove: () => _onApprove(request),
                  onReject: () => _onReject(request),
                );
              },
            ),
    );
  }
}

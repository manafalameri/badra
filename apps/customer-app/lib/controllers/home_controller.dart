import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:get/get.dart';
import '../core/cache_service.dart';
import '../core/security_service.dart';
import '../core/string_utils.dart';
import '../core/supabase_service.dart';

class HomeController extends GetxController {

  final RxString userName = 'المستخدم'.obs;
  final RxString userPhone = ''.obs;
  final RxString walletId = ''.obs;
  final RxString balance = '0'.obs;
  final RxString joinedAt = ''.obs;
  final RxString error = ''.obs;
  final RxBool isLoading = false.obs;
  final RxList<Map<String, dynamic>> pendingRequests =
      <Map<String, dynamic>>[].obs;
  final RxBool hasDevice = false.obs;
  final RxBool setupRequired = false.obs;
  final RxBool locked = false.obs;

  HomeController({
    String initialName = 'المستخدم',
    String initialPhone = '',
    String initialBalance = '0',
  }) {
    userName.value = initialName;
    userPhone.value = initialPhone;
    walletId.value = initialPhone.toWalletId();
    balance.value = initialBalance;
  }

  @override
  void onInit() {
    super.onInit();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    isLoading.value = true;
    update();

    await _loadSavedPhone();
    _applyCachedHomeData();
    await _fetchHomeData();

    isLoading.value = false;
    update();
  }

  Future<void> _loadSavedPhone() async {
    final savedPhone = await SecurityService.instance.readPhone();
    if (savedPhone != null && savedPhone.isNotEmpty) {
      userPhone.value = savedPhone;
      walletId.value = savedPhone.toWalletId();
      update();
    }
  }

  void _applyCachedHomeData() {
    final cached = CacheService.getHomeData();
    if (cached == null) return;

    try {
      final data = HomeDataModel.fromMap(cached);
      _applyHomeData(data);
    } catch (_) {
      // Ignore malformed cache.
    }
  }

  static const _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل',
    'مايو', 'يونيو', 'يوليو', 'أغسطس',
    'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  void _applyHomeData(HomeDataModel data) {
    if (!kReleaseMode) {
      // ignore: avoid_print
      print('[BADRA_TRACE] _applyHomeData created_at="${data.createdAt}"');
    }
    userName.value = data.profile.name;
    balance.value = data.profile.balance.toString();
    pendingRequests.value = data.pendingRequests;
    hasDevice.value = data.hasDevice;
    setupRequired.value = data.setupRequired;
    locked.value = data.locked;

    final dt = DateTime.tryParse(data.createdAt);
    if (dt != null) {
      joinedAt.value =
          '${dt.day} ${_arabicMonths[dt.month - 1]} ${dt.year}';
    }
    update();
  }

  Future<void> _fetchHomeData() async {
    try {
      if (SupabaseService.currentUser == null) {
        error.value = 'يرجى تسجيل الدخول مرة أخرى.';
        balance.value = '0';
        update();
        return;
      }

      final data = await SupabaseService.syncHomeData();

      _applyHomeData(data);

      // Build wallet id locally from phone digits; phone is already known
      // because it was saved during login.
      if (userPhone.value.isNotEmpty) {
        walletId.value = userPhone.value.toWalletId();
      }

      // Persist non-sensitive display data only.
      await CacheService.setHomeData(data.toMap());

      error.value = '';
      update();
    } catch (error) {
      final message = error.toString();
      if (message.contains('400')) {
        this.error.value = 'انتهت الجلسة. الرجاء تسجيل الدخول مرة أخرى.';
        await SecurityService.instance.clearPhone();
      } else {
        this.error.value = 'فشل في تحميل بيانات المستخدم. حاول مرة أخرى.';
      }
      balance.value = '0';
      update();
    }
  }

  Future<void> retry() async {
    await _loadHomeData();
  }

  Future<void> clearLocalData() async {
    await SecurityService.instance.clearPhone();
    await CacheService.clear();
  }
}

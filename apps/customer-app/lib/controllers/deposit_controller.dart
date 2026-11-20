import 'package:get/get.dart';
import '../core/supabase_service.dart';

class DepositController extends GetxController {
  // Observables لأرقام البنوك الأربعة
  final RxString bank1 = ''.obs;
  final RxString bank2 = ''.obs;
  final RxString bank3 = ''.obs;
  final RxString bank4 = ''.obs;

  // Observable لاسم المستخدم
  final RxString userName = ''.obs;

  // حالة التحميل
  final RxBool isLoading = false.obs;

  // خطأ إذا حدث
  final RxString error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchDepositData();
  }

  Future<void> fetchDepositData() async {
    try {
      isLoading.value = true;
      error.value = '';
      update();

      final rawData = await SupabaseService.getDepositData();
      final safeData = rawData.trim().isEmpty
          ? '0#0#0#0#Unknown'
          : rawData.trim();
      final parts = safeData.split('#');

      if (parts.length >= 5) {
        bank1.value = parts[0].trim();
        bank2.value = parts[1].trim();
        bank3.value = parts[2].trim();
        bank4.value = parts[3].trim();
        userName.value = parts[4].trim();
      } else {
        error.value =
            'البيانات غير مكتملة، يجب أن تحتوي على 5 أجزاء على الأقل.';
        bank1.value = '0';
        bank2.value = '0';
        bank3.value = '0';
        bank4.value = '0';
        userName.value = 'Unknown';
      }

      update();
    } catch (e) {
      error.value = 'فشل في تحميل بيانات الشحن: $e';
      bank1.value = '0';
      bank2.value = '0';
      bank3.value = '0';
      bank4.value = '0';
      userName.value = 'Unknown';
      update();
    } finally {
      isLoading.value = false;
      update();
    }
  }

  // دالة لإعادة المحاولة
  void retry() {
    fetchDepositData();
  }
}

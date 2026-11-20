import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة حفظ تفضيل الإشعارات — تضمن أمان الحالة ومنع التلاعب
class NotificationPreferenceService {
  NotificationPreferenceService._();
  static final NotificationPreferenceService instance =
      NotificationPreferenceService._();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _key = 'notification_preference_enabled';

  // ── Unified read/write ──

  Future<bool> isEnabled() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool('badra_$_key') ?? true;
      }
      final value = await _secureStorage.read(key: _key);
      return value == null ? true : value == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('badra_$_key', value);
        return;
      }
      await _secureStorage.write(key: _key, value: value.toString());
    } catch (_) {
      debugPrint('[NotificationPref] Failed to save preference');
    }
  }
}

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceBindingService {
  static final _supabase = Supabase.instance.client;
  static final _secureStorage = const FlutterSecureStorage();
  static final _deviceInfo = DeviceInfoPlugin();

  static const _storageKey = 'device_id';

  static Future<String> getDeviceId() async {
    final stored = await _secureStorage.read(key: _storageKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }

    String deviceId;
    try {
      if (kIsWeb) {
        deviceId = 'web_${DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceId = 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = 'ios_${iosInfo.identifierForVendor ?? iosInfo.name}';
      } else {
        deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      deviceId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }

    await _secureStorage.write(key: _storageKey, value: deviceId);
    return deviceId;
  }

  static Future<String> getDeviceName() async {
    try {
      if (kIsWeb) {
        return 'Web Browser';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return '${iosInfo.model} iOS ${iosInfo.systemVersion}';
      } else {
        return 'Unknown Device';
      }
    } catch (e) {
      return 'Unknown Device';
    }
  }

  static Future<void> clearDeviceId() async {
    await _secureStorage.delete(key: _storageKey);
  }

  /// Verifies the bound device against the server.
  ///
  /// Returns `success: true` when verified.
  /// Returns `success: false` with `transient: true` when verification could
  /// not complete due to a network/timeout error — callers may retry instead
  /// of treating it as a security rejection.
  /// Returns `success: false` without `transient` when the server explicitly
  /// rejects (fail-closed).
  static Future<Map<String, dynamic>> verifyDevice() async {
    try {
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();

      debugPrint('[DEVICE] Binding device: id=$deviceId name=$deviceName');

      final result = await _supabase
          .schema('badra_core')
          .rpc('admin_verify_device', params: {
        'p_device_id': deviceId,
        'p_device_name': deviceName,
      });

      debugPrint('[DEVICE] RPC result: $result');
      return result as Map<String, dynamic>;
    } catch (e, stack) {
      debugPrint('[DEVICE] Transient error: $e\n$stack');
      return {
        'success': false,
        'transient': true,
        'error': 'تعذر الاتصال بالخادم للتحقق من الجهاز',
      };
    }
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Hardware-backed ECDSA signing only.
///
/// SECURITY: There is deliberately NO software fallback. The private key
/// must never be stored on the device in plaintext (previously it was
/// saved to SharedPreferences, which meant the whole "device binding"
/// could be bypassed by anyone who could read app storage). If the
/// hardware keystore is unavailable (web, desktop, or channel failure),
/// signing fails and the operation is rejected — never downgraded.
class HardwareKeyStore {
  static const _channel = MethodChannel('com.badra.keystore');

  static Future<Map<String, dynamic>> setup() async {
    if (kIsWeb) {
      return {
        'success': false,
        'error': 'التوقيع الآمن غير مدعوم على المتصفح',
      };
    }

    try {
      final result = await _channel.invokeMethod('setup');
      if (result is Map && result['success'] == true) {
        return {
          'x': result['x'],
          'y': result['y'],
          'keySource': 'hardware',
        };
      }
      return {
        'success': false,
        'error': (result is Map && result['error'] is String)
            ? result['error'] as String
            : 'فشل تجهيز مفتاح الجهاز الآمن',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'مفتاح الأمان غير متاح على هذا الجهاز: $e',
      };
    }
  }

  static Future<String> sign(String payload) async {
    if (kIsWeb) return '';

    try {
      final result = await _channel.invokeMethod('sign', {'payload': payload});
      if (result is String && result.isNotEmpty) return result;
      return '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> deleteKey() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('deleteKey');
    } catch (_) {}
  }
}
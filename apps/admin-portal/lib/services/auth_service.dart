import 'package:flutter/foundation.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;
  static final _localAuth = LocalAuthentication();
  static const _secureStorage = FlutterSecureStorage();

  static Future<AuthResponse> signIn(String email, String password) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// تسجيل الدخول باستخدام رقم الهاتف وكلمة المرور
  /// يعيد AuthResponse كما في signIn
  static Future<AuthResponse> signInWithPhone(
      String phone, String password) async {
    final trimmed = phone.trim();
    final normalized = trimmed.startsWith('+')
        ? trimmed
        : trimmed.startsWith('967')
            ? '+$trimmed'
            : '+967$trimmed';
    debugPrint('[AUTH] signInWithPhone: original=$phone → normalized=$normalized');
    return await _supabase.auth.signInWithPassword(
      phone: normalized,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static Future<void> saveCredentials(String phone, String password) async {
    await _secureStorage.write(key: 'phone', value: phone);
    await _secureStorage.write(key: 'password', value: password);
  }

  static Future<void> clearCredentials() async {
    await _secureStorage.delete(key: 'phone');
    await _secureStorage.delete(key: 'password');
  }

  static Future<bool> hasSavedCredentials() async {
    final phone = await _secureStorage.read(key: 'phone');
    final password = await _secureStorage.read(key: 'password');
    return phone != null && phone.isNotEmpty && password != null && password.isNotEmpty;
  }

  static Future<bool> loginWithBiometrics() async {
    try {
      debugPrint('=== [BIO] Starting biometric login ===');

      final canCheck = await _localAuth.canCheckBiometrics;
      debugPrint('[BIO] canCheckBiometrics = $canCheck');

      final isDeviceSupported = await _localAuth.isDeviceSupported();
      debugPrint('[BIO] isDeviceSupported = $isDeviceSupported');

      if (!canCheck && !isDeviceSupported) {
        debugPrint('[BIO] BLOCKED: !canCheck && !isDeviceSupported');
        return false;
      }

      final available = await _localAuth.getAvailableBiometrics();
      debugPrint('[BIO] availableBiometrics = $available');

      if (available.isEmpty) {
        debugPrint('[BIO] BLOCKED: available biometrics is empty');
        return false;
      }

      debugPrint('[BIO] Calling authenticate()...');
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'سجّل دخولك بالبصمة',
        authMessages: const [
          AndroidAuthMessages(signInTitle: 'تسجيل الدخول بالبصمة'),
        ],
      );
      debugPrint('[BIO] authenticate() returned = $authenticated');

      if (!authenticated) {
        debugPrint('[BIO] BLOCKED: authenticate returned false');
        return false;
      }

      final phone = await _secureStorage.read(key: 'phone');
      final password = await _secureStorage.read(key: 'password');
      debugPrint('[BIO] Stored phone = ${phone != null ? " EXISTS (${phone.length} chars)" : "NULL"}');
      debugPrint('[BIO] Stored password = ${password != null ? " EXISTS (${password.length} chars)" : "NULL"}');

      if (phone == null || password == null) {
        debugPrint('[BIO] BLOCKED: credentials not saved');
        return false;
      }

      debugPrint('[BIO] Calling signInWithPhone...');
      await signInWithPhone(phone, password);
      debugPrint('[BIO] signInWithPhone SUCCESS');
      return true;
    } catch (e, stack) {
      debugPrint('[BIO] EXCEPTION: $e');
      debugPrint('[BIO] STACK: $stack');
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics(String reason) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!canCheck || !isDeviceSupported) return false;

      final available = await _localAuth.getAvailableBiometrics();
      if (available.isEmpty) return false;

      return await _localAuth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'تأكيد الهوية',
          ),
        ],
      );
    } catch (e) {
      debugPrint('[AUTH] Biometric auth failed: $e');
      return false; // fail-closed
    }
  }

  static User? get currentUser => _supabase.auth.currentUser;
}

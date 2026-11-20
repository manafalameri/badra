import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/security_service.dart';
import '../core/supabase_service.dart';
import '../routes/app_routes.dart';

class AuthController extends GetxController {
  final SecurityService _security = SecurityService.instance;

  final RxBool isLoading = false.obs;
  final RxBool biometricAvailable = false.obs;
  final RxBool biometricEnabled = false.obs;
  final RxBool pinEnabled = false.obs;
  final RxString errorMessage = ''.obs;
  // Set to true once loadSecurityState() has successfully populated values
  // (regardless of whether the device actually supports biometrics).
  // Used by SignUpLoginScreen to decide whether it needs a re-load.
  final RxBool securityStateReady = false.obs;

  Future<void> loadSecurityState() async {
    try {
      biometricAvailable.value = await _security.isDeviceSupported();
      biometricEnabled.value = await _security.isBiometricEnabled();
      pinEnabled.value = await _security.isPinEnabled();
      securityStateReady.value = true;
      debugPrint('[AUTH] Security state: '
          'available=$biometricAvailable, '
          'enabled=$biometricEnabled, '
          'pin=$pinEnabled');
    } catch (e, stack) {
      debugPrint('[AUTH] ERROR loading security state: $e');
      debugPrint('[AUTH] Stack: $stack');
    }
  }

  /// Keeps the tokens in secure storage in sync with the live Supabase
  /// session. GoTrue rotates the refresh token on every refresh, so the
  /// stored token must be re-saved whenever the session changes or the
  /// biometric quick-login will restore with a revoked (stale) token.
  void setupSessionSync() {
    Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      try {
        final session = state.session;
        switch (state.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
          case AuthChangeEvent.initialSession:
            if (session == null) return;
            // Only the refresh token is persisted (smaller attack surface);
            // the access token never leaves the in-memory session.
            if (session.refreshToken != null && session.refreshToken!.isNotEmpty) {
              await _security.saveRefreshToken(session.refreshToken!);
            }
            break;
          default:
            break;
        }
      } catch (e) {
        debugPrint('[AUTH] ERROR syncing tokens to secure storage: $e');
      }
    });
  }

  Future<ProfileModel?> signInAuth({
    required String phone,
    required String password,
  }) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final deviceContext = await _collectDeviceContext();

      await SupabaseService.signIn(
        phone: phone,
        password: password,
        deviceId: deviceContext['deviceId'] ?? '',
        deviceName: deviceContext['deviceName'] ?? '',
        deviceModel: deviceContext['deviceModel'] ?? '',
      );

      final refreshToken = SupabaseService.currentRefreshToken;

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _security.saveRefreshToken(refreshToken);
      }
      await _security.saveLoginTimestamp(DateTime.now());

      final profile = await SupabaseService.getCurrentProfile(
        deviceId: deviceContext['deviceId'] ?? '',
      );

      if (!profile.isActive) {
        throw Exception('هذا الحساب غير نشط. يرجى التواصل مع الدعم الفني.');
      }

      return profile;
    } catch (error) {
      errorMessage.value = error.toString();
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, String>> _collectDeviceContext() async {
    String deviceName = 'Unknown Device';
    String deviceId = 'unknown_device_id';
    String ip = '0.0.0.0';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        deviceName = info.browserName.name;
        // Use browser name as a stable web device id (vendor/userAgent are too long/unstable)
        deviceId = info.browserName.name.toLowerCase();
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await deviceInfo.androidInfo;
            deviceName = '${info.brand} ${info.model}'.trim();
            deviceId = info.id;
            break;
          case TargetPlatform.iOS:
            final info = await deviceInfo.iosInfo;
            deviceName = '${info.name} ${info.model}'.trim();
            deviceId = info.identifierForVendor ?? 'ios_device';
            break;
          case TargetPlatform.windows:
            final info = await deviceInfo.windowsInfo;
            deviceName = info.computerName;
            deviceId = info.deviceId;
            break;
          case TargetPlatform.macOS:
            final info = await deviceInfo.macOsInfo;
            deviceName = info.computerName;
            deviceId = info.systemGUID ?? 'macos_device';
            break;
          case TargetPlatform.linux:
            final info = await deviceInfo.linuxInfo;
            deviceName = '${info.name} ${info.prettyName}'.trim();
            deviceId = info.machineId ?? 'linux_device';
            break;
          default:
            deviceName = 'Unknown Device';
            deviceId = 'unknown_device_id';
        }
      }
    } catch (_) {
      // Ignore device info failures and continue with defaults.
    }

    try {
      final networkInfo = NetworkInfo();
      final wifiIp = await networkInfo.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty) {
        ip = wifiIp;
      } else {
        final wifiIPv6 = await networkInfo.getWifiIPv6();
        if (wifiIPv6 != null && wifiIPv6.isNotEmpty) {
          ip = wifiIPv6;
        }
      }
    } catch (_) {
      // Ignore network info failures and continue with default ip.
    }

    return {'ip': ip, 'deviceName': deviceName, 'deviceId': deviceId};
  }

  /// بيانات الجهاز الحالي (معرّف + اسم + موديل + IP) — تُستخدم في شاشة
  /// تسجيل الدخول لرسالة الدعم الفني عند نسيان كلمة المرور.
  Future<Map<String, String>> getDeviceContext() => _collectDeviceContext();

  Future<bool> signUpWithPassword({
    required String name,
    required String phone,
    required String password,
  }) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      final deviceContext = await _collectDeviceContext();

      final response = await SupabaseService.signUp(
        name: name,
        phone: phone,
        password: password,
        ip: deviceContext['ip']!,
        deviceName: deviceContext['deviceName']!,
        deviceId: deviceContext['deviceId']!,
      );

      final success = response['success'] == true;
      final message =
          response['message']?.toString() ?? 'فشل إنشاء الحساب. حاول مرة أخرى.';
      if (!success) {
        throw Exception(message);
      }

      return true;
    } catch (error) {
      errorMessage.value = error.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      final result = await _security.authenticateBiometrics();
      debugPrint('[AUTH] Biometric result: $result');
      return result;
    } catch (e, stack) {
      debugPrint('[AUTH] ERROR in biometric: $e');
      debugPrint('[AUTH] Stack: $stack');
      return false;
    }
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final result = await _security.verifyPin(pin);
      debugPrint('[AUTH] PIN verify result: $result');
      return result;
    } catch (e, stack) {
      debugPrint('[AUTH] ERROR verifying PIN: $e');
      debugPrint('[AUTH] Stack: $stack');
      return false;
    }
  }

  Future<bool> changeBiometricEnabled(bool enable) async {
    if (enable) {
      final available = await _security.isDeviceSupported();
      if (!available) return false;
      final authenticated = await authenticateBiometric();
      if (!authenticated) return false;
      await _security.setBiometricEnabled(true);
      biometricEnabled.value = true;
      return true;
    }

    await _security.setBiometricEnabled(false);
    biometricEnabled.value = false;
    return true;
  }

  Future<void> clearBiometricState() async {
    await _security.setBiometricEnabled(false);
    biometricEnabled.value = false;
  }

  Future<void> carveCurrentDevice() async {
    try {
      final deviceContext = await _collectDeviceContext();

      final deviceInfo = DeviceInfoPlugin();
      String model = '';
      if (!kIsWeb) {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            final info = await deviceInfo.androidInfo;
            model = '${info.brand} ${info.model}'.trim();
            break;
          case TargetPlatform.iOS:
            final info = await deviceInfo.iosInfo;
            model = info.model;
            break;
          default:
            break;
        }
      }

      final keyData = await _security.setupHardwareKey();
      
      if (keyData['x'] == null || (keyData['x'] as String).isEmpty) {
        throw Exception(keyData['error']?.toString() ?? 'فشل إنشاء مفتاح الجهاز');
      }

      final keySource = await _security.getDeviceKeySource();

      final result = await SupabaseService.carveDevice(
        deviceId: deviceContext['deviceId']!,
        deviceName: deviceContext['deviceName']!,
        deviceModel: model,
        publicKeyX: keyData['x'] as String,
        publicKeyY: keyData['y'] as String,
        keySource: keySource,
      );
      
      if (result['success'] != true) {
        throw Exception(result['error']?.toString() ?? 'فشل حفر الجهاز');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> setupPin({
    required String pin,
    required bool enableBiometric,
  }) async {
    await _security.setPin(pin);
    final result = await SupabaseService.setSecurityCode(pin);
    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'فشل حفظ الرقم السري على السيرفر');
    }
    await _security.setBiometricEnabled(enableBiometric);
  }

  Future<void> setupPinAndCarve({
    required String pin,
    required bool enableBiometric,
  }) async {
    await carveCurrentDevice();

    await _security.setPin(pin);
    final result = await SupabaseService.setSecurityCode(pin);
    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'فشل حفظ الرقم السري على السيرفر');
    }

    if (enableBiometric) {
      await _security.setBiometricEnabled(true);
      biometricEnabled.value = true;
    }

    pinEnabled.value = true;
  }

  /// Regenerate device key pair and update the public key on the server.
  Future<void> refreshDeviceKeyPair() async {
    await _security.deleteDeviceKeyPair();

    final keyData = await _security.setupHardwareKey();
    if (keyData['x'] == null || (keyData['x'] as String).isEmpty) {
      throw Exception(keyData['error']?.toString() ?? 'فشل إنشاء مفتاح الجهاز');
    }

    final keySource = await _security.getDeviceKeySource();
    final deviceContext = await _collectDeviceContext();

    final result = await SupabaseService.carveDevice(
      deviceId: deviceContext['deviceId']!,
      deviceName: deviceContext['deviceName']!,
      deviceModel: '',
      publicKeyX: keyData['x'] as String,
      publicKeyY: keyData['y'] as String,
      keySource: keySource,
    );

    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'فشل تحديث مفتاح الجهاز على السيرفر');
    }
  }
}

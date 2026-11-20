import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/io_client.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'hardware_keystore.dart';

class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  // Live server SHA-256 fingerprint (hardcoded to avoid asset mismatch issues)
  static const _liveServerFingerprint =
      'E4:89:07:23:60:38:C7:FE:B0:5C:D8:62:E4:1C:D7:FC:57:28:F2:8D:A6:1B:95:E6:76:1D:9C:29:5C:5B:32:98';
  static bool isSslPinningConfigured = false;
  static String? sslPinningFailureMessage;
  static const _keyRefreshToken = 'secure_refresh_token';
  static const _keyAccessToken = 'secure_access_token';
  static const _keyPinHash = 'secure_pin_hash';
  static const _keyPinSalt = 'secure_pin_salt';
  static const _keyBiometricEnabled = 'secure_biometric_enabled';
  static const _keyPinEnabled = 'secure_pin_enabled';
  static const _keyPinFailures = 'secure_pin_failures';
  static const _keyPinLockedUntil = 'secure_pin_locked_until';
  static const _keyLoginTimestamp = 'secure_login_timestamp';
  static const _keySavedPhone = 'secure_saved_phone';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    } catch (_) {
      // On Windows the underlying storage implementation may throw
      // PathAccessException when the file is corrupted or locked by
      // another process. Treat as missing value and continue.
      return null;
    }
  }

  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'استخدم البصمة أو Face ID لتسجيل الدخول الآمن.',
        options: const AuthenticationOptions(
          // Allow device credentials fallback (PIN/Pattern/Password)
          biometricOnly: false,
          stickyAuth: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(
      key: _keyRefreshToken,
      value: token,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<String?> readRefreshToken() async {
    return _safeRead(_keyRefreshToken);
  }

  Future<void> deleteRefreshToken() async {
    await _storage.delete(
      key: _keyRefreshToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<void> clearRefreshToken() async {
    await deleteRefreshToken();
  }

  Future<String?> getRefreshToken() async {
    return readRefreshToken();
  }

  Future<void> saveAccessToken(String token) async {
    await _storage.write(
      key: _keyAccessToken,
      value: token,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<String?> getAccessToken() async {
    return _safeRead(_keyAccessToken);
  }

  Future<void> clearAccessToken() async {
    await _storage.delete(
      key: _keyAccessToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<bool> restoreSessionWithRefreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('[SECURITY] No refresh token found');
      return false;
    }
    // Access tokens are no longer stored (smaller attack surface): only the
    // refresh token is kept. Clear any legacy value from older versions.
    await clearAccessToken();
    debugPrint('[SECURITY] Refresh token found, restoring session...');

    try {
      // Always go through the `/token` refresh round-trip. The server rotates
      // the refresh token on every use, so the stored pair is always fresh and
      // we never rebuild a session from a potentially revoked token.
      final response = await Supabase.instance.client.auth.setSession(
        refreshToken,
      );
      if (response.session == null) {
        debugPrint('[SECURITY] FAIL: Session is null after setSession');
        await clearRefreshToken();
        return false;
      }
      debugPrint('[SECURITY] Session restored successfully');
      // The restore rotated the token — persist the new one immediately so
      // the next biometric login never reads a revoked token.
      final newRefresh = response.session!.refreshToken;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await saveRefreshToken(newRefresh);
      }
      // A successful restore IS a fresh authentication. Reset the session
      // bookkeeping so the timeout observer does not treat this newly
      // restored session as already expired and force a logout.
      await saveLoginTimestamp(DateTime.now());
      return true;
    } catch (e) {
      debugPrint('[SECURITY] ERROR restoring session: $e');
      await clearRefreshToken();
      return false;
    }
  }

  static String _certificateFingerprint(X509Certificate certificate) {
    final digest = sha256.convert(certificate.der);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  static String? _extractSslDiagnosticMessage(Object? error) {
    if (error == null) return null;
    final text = error.toString().toLowerCase();
    if (text.contains('handshake') ||
        text.contains('tls') ||
        text.contains('ssl') ||
        text.contains('certificate') ||
        text.contains('cert')) {
      return error.toString();
    }
    return null;
  }

  Future<Dio> createSecureDioClient() async {
    Dio dio = Dio();
    try {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final SecurityContext context = SecurityContext(
            withTrustedRoots: true,
          );
          final client = HttpClient(context: context)
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) {
                  return _certificateFingerprint(cert) ==
                      _liveServerFingerprint;
                };
          return client;
        },
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            final sslMessage = _extractSslDiagnosticMessage(error.error);
            if (sslMessage != null) {
              print('Secure Dio SSL error: $sslMessage');
            }
            handler.next(error);
          },
        ),
      );
    } catch (e, st) {
      print('Security Exception: Failed to create secure Dio client -> $e');
      print(st);
      sslPinningFailureMessage = e.toString();
    }
    return dio;
  }

  static Future<http.Client> createSecureHttpClient() async {
    if (kIsWeb) {
      return http.Client();
    }

    final secureContext = SecurityContext(withTrustedRoots: true);
    final httpClient = HttpClient(context: secureContext)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return _certificateFingerprint(cert) == _liveServerFingerprint;
      };

    return IOClient(httpClient);
  }

  static Future<void> configureGlobalHttpOverrides() async {
    if (kIsWeb) {
      return;
    }
    try {
      HttpOverrides.global = _PermissiveHttpOverrides();
      isSslPinningConfigured = true;
      sslPinningFailureMessage = null;
    } catch (e, st) {
      isSslPinningConfigured = false;
      sslPinningFailureMessage = e.toString();
      print('Security Exception: Failed to configure HTTP override -> $e');
      print(st);
    }
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _safeRead(_keyBiometricEnabled);
    return value == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _keyBiometricEnabled,
      value: enabled ? 'true' : 'false',
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<bool> isPinEnabled() async {
    final value = await _safeRead(_keyPinEnabled);
    return value == 'true';
  }

  Future<bool> isPinSet() async {
    final hash = await _safeRead(_keyPinHash);
    final salt = await _safeRead(_keyPinSalt);
    return hash != null && hash.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    if (pin.length != 6 || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly six digits.');
    }

    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);

    await _storage.write(
      key: _keyPinHash,
      value: hash,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.write(
      key: _keyPinSalt,
      value: salt,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.write(
      key: _keyPinEnabled,
      value: 'true',
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await resetPinFailures();
  }

  Future<bool> verifyPin(String pin) async {
    if (!await canAttemptPin()) {
      return false;
    }

    final storedHash = await _safeRead(_keyPinHash);
    final storedSalt = await _safeRead(_keyPinSalt);

    if (storedHash == null || storedSalt == null) {
      return false;
    }

    final incomingHash = _hashPin(pin, storedSalt);
    if (incomingHash == storedHash) {
      await resetPinFailures();
      return true;
    }

    await _registerFailedPinAttempt();
    return false;
  }

  Future<bool> canAttemptPin() async {
    final lockedUntilString = await _safeRead(_keyPinLockedUntil);

    if (lockedUntilString == null || lockedUntilString.isEmpty) {
      return true;
    }

    final lockedUntil = DateTime.tryParse(lockedUntilString);
    if (lockedUntil == null) {
      await _storage.delete(
        key: _keyPinLockedUntil,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
      return true;
    }

    if (DateTime.now().isAfter(lockedUntil)) {
      await resetPinFailures();
      await _storage.delete(
        key: _keyPinLockedUntil,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
      return true;
    }

    return false;
  }

  Future<int> getFailedPinAttempts() async {
    final value = await _safeRead(_keyPinFailures);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<void> resetPinFailures() async {
    await _storage.delete(
      key: _keyPinFailures,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.delete(
      key: _keyPinLockedUntil,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<void> _registerFailedPinAttempt() async {
    final attempts = await getFailedPinAttempts() + 1;
    await _storage.write(
      key: _keyPinFailures,
      value: attempts.toString(),
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );

    if (attempts >= 5) {
      final lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      await _storage.write(
        key: _keyPinLockedUntil,
        value: lockedUntil.toIso8601String(),
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    }
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final input = utf8.encode('$pin|$salt');
    final digest = sha256.convert(input);
    return base64UrlEncode(digest.bytes);
  }

  // ── Device Key Management ──

  static const _keyDevicePublicKeyX = 'secure_device_public_key_x';
  static const _keyDevicePublicKeyY = 'secure_device_public_key_y';
  static const _keyDeviceKeySource = 'secure_device_key_source';

  // ── Web-specific storage (SharedPreferences) ──

  Future<void> _webWrite(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('badra_$key', value);
  }

  Future<String?> _webRead(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('badra_$key');
  }

  Future<void> _webDelete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('badra_$key');
  }

  /// Unified read: web uses SharedPreferences, mobile uses flutter_secure_storage.
  Future<String?> _readKey(String key) async {
    if (kIsWeb) return _webRead(key);
    return _safeRead(key);
  }

  /// Unified write: web uses SharedPreferences, mobile uses flutter_secure_storage.
  Future<void> _writeKey(String key, String value) async {
    if (kIsWeb) {
      await _webWrite(key, value);
      return;
    }
    await _storage.write(
      key: key,
      value: value,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  /// Unified delete: web uses SharedPreferences, mobile uses flutter_secure_storage.
  Future<void> _deleteKey(String key) async {
    if (kIsWeb) {
      await _webDelete(key);
      return;
    }
    await _storage.delete(
      key: key,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  /// Ensure a hardware-backed key exists. Returns {x, y, keySource}.
  /// SECURITY: No software fallback — a failure result is returned as-is
  /// and nothing is persisted.
  Future<Map<String, dynamic>> setupHardwareKey() async {
    final result = await HardwareKeyStore.setup();
    if (result['success'] != true || result['x'] == null) {
      return result;
    }
    await _writeKey(_keyDevicePublicKeyX, result['x'] as String);
    await _writeKey(_keyDevicePublicKeyY, result['y'] as String);
    await _writeKey(_keyDeviceKeySource, 'hardware');
    return result;
  }

  /// Get the stored public key {x, y}.
  Future<Map<String, String>?> getDevicePublicKey() async {
    final x = await _readKey(_keyDevicePublicKeyX);
    final y = await _readKey(_keyDevicePublicKeyY);
    if (x == null || x.isEmpty) return null;
    return {'x': x, 'y': y ?? ''};
  }

  /// Get the stored key source.
  Future<String> getDeviceKeySource() async {
    return (await _readKey(_keyDeviceKeySource)) ?? 'software';
  }

  /// Sign a payload using the device key (hardware or software fallback).
  /// Returns base64url-encoded signature, or empty string on failure.
  Future<String> signApprovalPayload(String payload) async {
    try {
      return await HardwareKeyStore.sign(payload);
    } catch (_) {
      return '';
    }
  }

  /// Delete the device key from backing store + secure storage.
  Future<void> deleteDeviceKeyPair() async {
    await HardwareKeyStore.deleteKey();
    await _deleteKey(_keyDevicePublicKeyX);
    await _deleteKey(_keyDevicePublicKeyY);
    await _deleteKey(_keyDeviceKeySource);
  }

  /// Clear all session-related stored tokens (access + refresh).
  Future<void> clearAllSession() async {
    await clearAccessToken();
    await clearRefreshToken();
  }

  Future<void> saveLoginTimestamp(DateTime time) async {
    await _storage.write(
      key: _keyLoginTimestamp,
      value: time.toIso8601String(),
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<DateTime?> readLoginTimestamp() async {
    final s = await _safeRead(_keyLoginTimestamp);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Future<void> clearLoginTimestamp() async {
    await _storage.delete(
      key: _keyLoginTimestamp,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<bool> isLoginExpired(Duration maxAge) async {
    final ts = await readLoginTimestamp();
    if (ts == null) return true;
    return DateTime.now().difference(ts) > maxAge;
  }

  // ── Saved phone (secure, no plaintext SharedPreferences) ──

  Future<void> savePhone(String phone) async {
    await _storage.write(
      key: _keySavedPhone,
      value: phone,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<String?> readPhone() async {
    return _safeRead(_keySavedPhone);
  }

  Future<void> clearPhone() async {
    await _storage.delete(
      key: _keySavedPhone,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  /// Generates an anti-tamper security seal for recovery messages.
  /// Combines deviceId, formatted timestamp, and a static secret salt.
  String generateRecoverySecuritySeal(String deviceId, String timestamp) {
    final input = '$deviceId|$timestamp|badra_recovery_seal_salt_v1';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    final hex = digest.toString().toUpperCase();
    return 'BDR-${hex.substring(0, 4)}-${hex.substring(4, 8)}';
  }
}

class _PermissiveHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          return SecurityService._certificateFingerprint(cert) ==
              SecurityService._liveServerFingerprint;
        };
    return client;
  }
}

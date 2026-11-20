import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint, kIsWeb, kReleaseMode;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mock_transactions.dart';

void _trace(dynamic msg) {
  // SECURITY: never leak request details (phones, tokens, payloads) in release.
  if (kReleaseMode) return;
  debugPrint('[BADRA_TRACE] $msg');
}

class ProfileModel {
  final String name;
  final num balance;
  final bool isActive;

  ProfileModel({
    required this.name,
    required this.balance,
    required this.isActive,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    final rawBalance = map['balance'];
    return ProfileModel(
      name: map['name'] is String ? map['name'] as String : '',
      balance: rawBalance is num
          ? rawBalance
          : double.tryParse('${rawBalance ?? ''}') ?? 0,
      isActive: map['is_active'] == true,
    );
  }
}

class HomeDataModel {
  final ProfileModel profile;
  final List<Map<String, dynamic>> pendingRequests;
  final bool hasDevice;
  final bool setupRequired;
  final bool locked;
  final String createdAt;

  HomeDataModel({
    required this.profile,
    required this.pendingRequests,
    required this.hasDevice,
    required this.setupRequired,
    required this.locked,
    this.createdAt = '',
  });

  factory HomeDataModel.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profile'];
    final requests = map['pending_requests'];

    return HomeDataModel(
      profile: profileMap is Map<String, dynamic>
          ? ProfileModel.fromMap(profileMap)
          : ProfileModel(name: '', balance: 0, isActive: true),
      pendingRequests: requests is List
          ? requests
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [],
      hasDevice: map['has_device'] == true,
      setupRequired: map['setup_required'] == true,
      locked: map['locked'] == true,
      createdAt: (map['created_at'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'profile': {
        'name': profile.name,
        'balance': profile.balance,
        'is_active': profile.isActive,
      },
      'pending_requests': pendingRequests,
      'has_device': hasDevice,
      'setup_required': setupRequired,
      'locked': locked,
      'created_at': createdAt,
    };
  }
}

class BankAccountModel {
  final String id;
  final String bankName;
  final String accountNumberEncrypted;
  final String accountHolderName;
  final bool isDefault;

  BankAccountModel({
    required this.id,
    required this.bankName,
    required this.accountNumberEncrypted,
    required this.accountHolderName,
    required this.isDefault,
  });

  factory BankAccountModel.fromMap(Map<String, dynamic> map) {
    return BankAccountModel(
      id: map['id'] as String,
      bankName: map['bank_name'] as String,
      accountNumberEncrypted: map['account_number_encrypted'] as String,
      accountHolderName: map['account_holder_name'] as String? ?? '',
      isDefault: map['is_default'] as bool? ?? false,
    );
  }
}

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  static String? get currentUserId => _client.auth.currentUser?.id;
  static User? get currentUser => _client.auth.currentUser;
  static String? get currentAccessToken =>
      _client.auth.currentSession?.accessToken;
  static String? get currentRefreshToken =>
      _client.auth.currentSession?.refreshToken;

  static dynamic _parseRpc(dynamic response) {
    if (response is String) return jsonDecode(response);
    if (response is List && response.length == 1) return response.first;
    return response;
  }

  static String _translateAuthError(Object error) {
    _trace('_translateAuthError called with: $error');

    final lower = error.toString().toLowerCase();
    _trace('error type: ${error.runtimeType}, lower case: $lower');

    if (error is AuthApiException) {
      _trace('AuthApiException: status=${error.statusCode}, message=${error.message}');
      final message = error.message.toLowerCase();
      if (message.contains('phone') && message.contains('already')) {
        return 'رقم الهاتف مستخدم بالفعل. حاول تسجيل الدخول أو استخدم رقم آخر.';
      }
      if (message.contains('password') && message.contains('weak')) {
        return 'كلمة المرور ضعيفة. استخدم ستة أحرف أو أكثر.';
      }
      if (message.contains('invalid login credentials') ||
          message.contains('invalid login') ||
          message.contains('invalid password')) {
        return 'البيانات غير صحيحة. تأكد من رقم الهاتف وكلمة المرور.';
      }
      final statusCode = error.statusCode?.toString();
      if (statusCode == '400') {
        return 'البيانات المدخلة غير صحيحة. تحقق من رقم الهاتف وكلمة المرور.';
      }
      if (statusCode == '429') {
        return 'تم تجاوز عدد المحاولات. حاول مرة أخرى بعد لحظة.';
      }
    }

    if (lower.contains('phone') && lower.contains('already')) {
      return 'رقم الهاتف مستخدم بالفعل. حاول تسجيل الدخول أو استخدم رقم آخر.';
    }
    if (lower.contains('password') && lower.contains('weak')) {
      return 'كلمة المرور ضعيفة. استخدم ستة أحرف أو أكثر.';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid login') ||
        lower.contains('invalid password')) {
      return 'البيانات غير صحيحة. تأكد من رقم الهاتف وكلمة المرور.';
    }

    if (lower.contains('الحساب مقفل')) {
      return 'الحساب مقفل مؤقتاً بسبب محاولات فاشلة كثيرة. حاول مرة أخرى لاحقاً.';
    }

    if (error is HandshakeException ||
        lower.contains('handshake') ||
        lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('certificate') ||
        lower.contains('cert')) {
      return 'فشل التحقق الآمن من شهادة الخادم. تحقق من إعدادات SSL والشهادة المضمّنة.';
    }

    _trace('No specific match, returning generic error');
    return 'حدث خطأ أثناء التواصل مع الخادم. حاول مرة أخرى لاحقاً.';
  }

  static String _normalizePhoneForAuth(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) {
      return trimmed;
    }
    if (trimmed.startsWith('967')) {
      return '+$trimmed';
    }
    if (trimmed.length == 9 && trimmed.startsWith('7')) {
      return '+967$trimmed';
    }
    return trimmed;
  }

  static String _normalizePhoneForActivation(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  // ── Secure Login (Edge Function) ──

  static String _friendlyIfNeeded(Object error) {
    final msg = error.toString();
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(msg);
    return hasArabic ? msg : _translateAuthError(error);
  }

  /// الدالة الآمنة الوحيدة لتسجيل الدخول: تستدعي Edge Function `login`.
  /// القفل الخادمي + تحقق كلمة المرور + ربط الجهاز — كلها تحدث في الخادم،
  /// والعميل يمرر الرقم وكلمة المرور فقط.
  static Future<Map<String, dynamic>> loginViaFunction({
    required String phone,
    required String password,
    required String deviceId,
    String deviceName = '',
    String deviceModel = '',
  }) async {
    final normalizedPhone = _normalizePhoneForAuth(phone);
    _trace('=== loginViaFunction START === (${password.length} chars)');

    try {
      final response = await _client.functions.invoke(
        'login',
        body: {
          'phone': normalizedPhone,
          'password': password,
          'device_id': deviceId,
          'device_name': deviceName,
          'device_model': deviceModel,
        },
      ).timeout(const Duration(seconds: 25));

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      throw Exception('استجابة غير متوقعة من الخادم');
    } on FunctionException catch (e) {
      _trace('loginViaFunction http error: ${e.status}');
      Object? serverError;
      final details = e.details;
      if (details is Map) {
        serverError = details['error'];
      }
      if (serverError is String && serverError.isNotEmpty) {
        throw Exception(serverError);
      }
      throw Exception('حدث خطأ أثناء التواصل مع الخادم. حاول مرة أخرى لاحقاً.');
    } catch (error) {
      _trace('loginViaFunction network error: $error');
      throw Exception(_friendlyIfNeeded(error));
    }
  }

  static Future<Map<String, dynamic>> signUpAuth({
    required String name,
    required String phone,
    required String password,
    required String ip,
    required String deviceName,
    required String deviceId,
  }) async {
    return createPendingUser(
      name: name,
      phone: phone,
      password: password,
      ip: ip,
      deviceName: deviceName,
      deviceId: deviceId,
    );
  }

  static Future<Map<String, dynamic>> createPendingUser({
    required String name,
    required String phone,
    required String password,
    required String ip,
    required String deviceName,
    required String deviceId,
  }) async {
    _trace('=== createPendingUser START ===');
    _trace('name=$name, phone=$phone, password=${password.length} chars');

    try {
      final normalizedPhone = _normalizePhoneForAuth(phone);
      _trace('normalizedPhone=$normalizedPhone');

      _trace('>>> Calling RPC create_pending_user (schema=badra_core)...');
      final response = await _client
          .schema('badra_core')
          .rpc(
            'create_pending_user',
            params: {
              'p_name': name,
              'p_phone': normalizedPhone,
              'p_password': password,
              'p_ip': ip,
              'p_device_name': deviceName,
              'p_device_id': deviceId,
            },
          );
      _trace('<<< RPC returned, type=${response.runtimeType}');

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) {
        _trace('Parsed Map: ${parsed['success']} / ${parsed['message']}');
        return parsed;
      }

      _trace('Unhandled response format, returning fallback error');
      return {
        'success': false,
        'message': 'فشل إنشاء الطلب. حاول مرة أخرى لاحقاً.',
      };
    } catch (error) {
      _trace('EXCEPTION in createPendingUser: $error');
      throw Exception(_translateAuthError(error));
    }
  }

  static Future<bool> activateUser({
    required String phone,
    required String code,
  }) async {
    _trace('=== activateUser START ===');
    _trace('phone=$phone, code=$code');

    try {
      final normalizedPhone = _normalizePhoneForActivation(phone);
      _trace('normalizedPhone=$normalizedPhone');

      _trace('>>> Calling RPC activate_user...');
      final response = await _client
          .schema('badra_core')
          .rpc(
            'activate_user',
            params: {'p_phone': normalizedPhone, 'p_code': code},
          );
      _trace('<<< RPC returned, type=${response.runtimeType}');

      final parsed = _parseRpc(response);
      if (parsed is! Map<String, dynamic>) {
        _trace('UNSUPPORTED response format!');
        throw Exception('فشل تفعيل الحساب. تنسيق الاستجابة غير مدعوم.');
      }

      final success = parsed['success'] == true;
      final message =
          parsed['message'] as String? ??
          'فشل تفعيل الحساب. حاول مرة أخرى.';

      _trace('activateUser result: success=$success, message=$message');

      if (success) {
        return true;
      }

      throw Exception(message);
    } catch (error) {
      _trace('EXCEPTION in activateUser: $error');
      throw Exception(_translateAuthError(error));
    }
  }

  static Future<String> signInAuth({
    required String phone,
    required String password,
    required String deviceId,
    String deviceName = '',
    String deviceModel = '',
  }) async {
    _trace('=== signInAuth START ===');
    _trace('phone=$phone, password=${password.length} chars');

    final normalizedPhone = _normalizePhoneForAuth(phone);

    try {
      // ── الخطوة 1: تسجيل الدخول عبر الدالة الآمنة ──
      // القفل الخادمي (user/device/ip/global) + تحقق GoTrue + ربط الجهاز:
      // كلها في الخادم — لا يمكن تجاوزها من العميل المعدّل.
      _trace('>>> Calling secure login function...');
      final result = await loginViaFunction(
        phone: normalizedPhone,
        password: password,
        deviceId: deviceId,
        deviceName: deviceName,
        deviceModel: deviceModel,
      );
      _trace('<<< Secure login response: success=${result['success']}');

      if (result['success'] != true) {
        throw Exception(
          result['error']?.toString() ?? 'فشل في تسجيل الدخول.',
        );
      }

      final accessToken = result['access_token'] as String?;
      final refreshToken = result['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('فشل في تسجيل الدخول.');
      }

      // ── الخطوة 2: تثبيت الجلسة محلياً ──
      _trace('>>> Setting session locally...');
      final authResponse = await _client.auth.setSession(
        refreshToken,
        accessToken: accessToken,
      );

      if (authResponse.session == null || authResponse.user == null) {
        _trace('FAIL: session or user is null after setSession');
        throw Exception('فشل في تسجيل الدخول.');
      }

      final userId = authResponse.user!.id;
      _trace('SUCCESS: userId=$userId');
      return userId;
    } on Exception catch (error) {
      _trace('EXCEPTION in signInAuth: $error');
      throw Exception(_friendlyIfNeeded(error));
    }
  }

  static Future<void> _waitForValidSession(String userId) async {
    int attempts = 0;
    const maxAttempts = 3; // تقليل من 5 إلى 3
    const delayMs = 100; // تقليل من 250 إلى 100

    while (attempts < maxAttempts) {
      final currentUser = _client.auth.currentUser;
      if (currentUser != null && currentUser.id == userId) {
        return;
      }
      attempts++;
      await Future.delayed(const Duration(milliseconds: delayMs));
    }

    throw Exception('الجلسة غير جاهزة بعد. حاول مرة أخرى.');
  }

  static Future<Map<String, dynamic>> signUp({
    required String name,
    required String phone,
    required String password,
    required String ip,
    required String deviceName,
    required String deviceId,
  }) async {
    return signUpAuth(
      name: name,
      phone: phone,
      password: password,
      ip: ip,
      deviceName: deviceName,
      deviceId: deviceId,
    );
  }

  static Future<String> signIn({
    required String phone,
    required String password,
    required String deviceId,
    String deviceName = '',
    String deviceModel = '',
  }) async {
    return signInAuth(
      phone: phone,
      password: password,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceModel: deviceModel,
    );
  }

  // ── Payment Requests ──

  static Future<List<Map<String, dynamic>>> getMyPendingRequests() async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('get_my_pending_requests')
          .timeout(const Duration(seconds: 15));

      final parsed = _parseRpc(response);
      if (parsed is List) return parsed.cast<Map<String, dynamic>>();
      if (parsed is Map<String, dynamic>) return [parsed];
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Approve payment using PIN + ECDSA signature via Edge Function.
  static Future<Map<String, dynamic>> approvePaymentWithSignature({
    required String requestId,
    required String securityCode,
    required String signature,
    required String timestamp,
    required String deviceId,
    String? couponCode,
  }) async {
    try {
      final url = dotenv.env['BADRA_APPROVE_SIGNATURE_URL'] ??
          'https://pqjdmyibeeifoshrlkkg.supabase.co/functions/v1/approve-payment-signature';

      final token = _client.auth.currentSession?.accessToken ?? '';

      final requestBody = <String, dynamic>{
        'request_id': requestId,
        'device_id': deviceId,
        'security_code': securityCode,
        'signature': signature,
        'timestamp': timestamp,
        // الكوبون يُرسل فقط إذا كان مدخلاً بالكامل (6 أرقام)
        if (couponCode != null && couponCode.trim().length == 6)
          'coupon_code': couponCode.trim(),
      };

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }

      final body = response.body;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}

      return {
        'success': false,
        'error': 'خطأ في الاتصال بالخادم (${response.statusCode})',
      };
    } catch (_) {
      return {'success': false, 'error': 'خطأ في الاتصال بالخادم'};
    }
  }

  static Future<Map<String, dynamic>> setSecurityCode(
    String newCode, {
    String currentCode = '',
  }) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('set_security_code', params: {
        'p_new_code': newCode,
        'p_current_code': currentCode,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'error': 'تنسيق استجابة غير متوقع'};
    } catch (e) {
      return {'success': false, 'error': 'خطأ في الاتصال بالخادم'};
    }
  }

  static Future<Map<String, dynamic>> rejectPaymentRequest(
    String requestId,
  ) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('reject_payment_request', params: {
        'p_request_id': requestId,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'error': 'تنسيق استجابة غير متوقع'};
    } catch (e) {
      return {'success': false, 'error': 'خطأ في الاتصال بالخادم'};
    }
  }

  static Future<Map<String, dynamic>> registerFcmToken(String fcmToken) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('register_fcm_token', params: {
        'p_fcm_token': fcmToken,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> carveDevice({
    required String deviceId,
    required String deviceName,
    required String deviceModel,
    String publicKeyN = '',
    String publicKeyE = '',
    String publicKeyX = '',
    String publicKeyY = '',
    String keySource = '',
  }) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('carve_device', params: {
        'p_device_id': deviceId,
        'p_device_name': deviceName,
        'p_device_model': deviceModel,
        if (publicKeyN.isNotEmpty) 'p_public_key_n': publicKeyN,
        if (publicKeyE.isNotEmpty) 'p_public_key_e': publicKeyE,
        if (publicKeyX.isNotEmpty) 'p_public_key_x': publicKeyX,
        if (publicKeyY.isNotEmpty) 'p_public_key_y': publicKeyY,
        if (keySource.isNotEmpty) 'p_key_source': keySource,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'error': 'تنسيق استجابة غير متوقع'};
    } catch (e) {
      return {'success': false, 'error': 'خطأ في حفر الجهاز'};
    }
  }

  static Future<Map<String, dynamic>> hasCarvedDevice() async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('has_carved_device');

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'has_device': false};
    } catch (e) {
      return {'success': false, 'has_device': false};
    }
  }



  static Future<Map<String, dynamic>> checkLockout(String attemptType) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('check_lockout', params: {
        'p_attempt_type': attemptType,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'locked': false};
    } catch (e) {
      return {'success': false, 'locked': false};
    }
  }

  static Future<Map<String, dynamic>> reportSecurityEvent(
    String eventType,
  ) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('report_security_event', params: {
        'p_event_type': eventType,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> checkSecuritySetup() async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('check_security_setup');

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'setup_required': false};
    } catch (e) {
      return {'success': false, 'setup_required': true};
    }
  }

  static Future<Map<String, dynamic>> verifyDevice(String deviceId) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('verify_device', params: {
        'p_device_id': deviceId,
      });

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'carved': false};
    } catch (e) {
      return {'success': false, 'carved': false};
    }
  }

  static RealtimeChannel createPaymentRequestsChannel({
    required String userId,
    required void Function(Map<String, dynamic> payload) onInsert,
  }) {
    return _client
        .channel('payment-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'badra_core',
          table: 'payment_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => onInsert(payload.newRecord),
        )
        .subscribe();
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// إغلاق الحساب نهائياً: يتطلب كود الأمان، ولا يُسمح إلا برصيد صفر.
  /// تُحذف البيانات الشخصية، مع الاحتفاظ بالسجلات المالية (إفصاح قانوني).
  static Future<Map<String, dynamic>> closeMyAccount(String securityCode) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('close_my_account', params: {
        'p_security_code': securityCode,
      }).timeout(const Duration(seconds: 20));

      final parsed = _parseRpc(response);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'success': false, 'error': 'تنسيق استجابة غير متوقع'};
    } on PostgrestException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'خطأ في الخادم',
      };
    } catch (e) {
      return {'success': false, 'error': 'خطأ في الاتصال بالخادم'};
    }
  }

  static Future<Map<String, String>> collectDeviceContext() async {
    String deviceName = 'Unknown Device';
    String deviceId = 'unknown_device_id';
    String ip = '0.0.0.0';

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        deviceName = info.browserName.name;
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

  /// Re-verify the device binding before biometric quick-login, mirroring the
  /// check performed during password login. Fail-closed: any error (network,
  /// timeout, server rejection) returns false so the user falls back to the
  /// password login which performs the full verification.
  static Future<bool> checkBiometricDeviceBinding() async {
    try {
      final ctx = await collectDeviceContext();
      final response = await _client
          .schema('badra_core')
          .rpc('check_login_device', params: {
        'p_device_id': ctx['deviceId'] ?? '',
        'p_device_name': ctx['deviceName'] ?? '',
        'p_device_model': '',
      }).timeout(const Duration(seconds: 10));
      final parsed = _parseRpc(response);
      return parsed is Map<String, dynamic> && parsed['success'] == true;
    } catch (e) {
      _trace('checkBiometricDeviceBinding ERROR: $e');
      return false;
    }
  }

  static Future<ProfileModel> getCurrentProfile({String? deviceId}) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return getProfile(userId, deviceId: deviceId);
  }

  static Future<ProfileModel> getProfile(
    String userId, {
    String? deviceId,
  }) async {
    _trace('=== getProfile START ===');
    _trace('userId=$userId');

    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      _trace('FAIL: currentUser is null');
      throw Exception('الجلسة غير صالحة أو غير جاهزة بعد.');
    }
    if (currentUser.id != userId) {
      _trace('FAIL: currentUser.id (${currentUser.id}) != userId ($userId)');
      throw Exception('الجلسة غير صالحة أو غير جاهزة بعد.');
    }
    _trace('currentUser OK, id=${currentUser.id}');

    _trace('>>> Calling RPC get_my_profile...');
    final resolvedDeviceId =
        deviceId ?? (await collectDeviceContext())['deviceId'] ?? '';
    final rawResponse = await _client
        .schema('badra_core')
        .rpc('get_my_profile', params: {'p_device_id': resolvedDeviceId})
        .timeout(const Duration(seconds: 10));
    _trace('<<< get_my_profile returned, type=${rawResponse.runtimeType}');

    final parsed = _parseRpc(rawResponse);

    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey('error')) {
        _trace('ERROR in response: ${parsed['error']}');
        throw Exception(parsed['error'] as String? ?? 'خطأ في جلب البيانات');
      }
      _trace('parsed is Map, keys=${parsed.keys}');
      return ProfileModel.fromMap(parsed);
    }

    _trace('UNEXPECTED parsed type: ${parsed.runtimeType}');
    throw Exception(
      'توقعنا بيانات البروفايل كصف واحد، لكن حصلنا على هيكل غير معروف.',
    );
  }

  static Future<HomeDataModel> syncHomeData({String? deviceId}) async {
    _trace('=== syncHomeData START ===');

    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw Exception('الجلسة غير صالحة أو غير جاهزة بعد.');
    }

    _trace('>>> Calling RPC sync_home_data...');
    final resolvedDeviceId =
        deviceId ?? (await collectDeviceContext())['deviceId'] ?? '';
    final rawResponse = await _client
        .schema('badra_core')
        .rpc('sync_home_data', params: {'p_device_id': resolvedDeviceId})
        .timeout(const Duration(seconds: 15));
    _trace('<<< sync_home_data returned, type=${rawResponse.runtimeType}');

    final parsed = _parseRpc(rawResponse);

    if (parsed is Map<String, dynamic>) {
      if (parsed.containsKey('error')) {
        _trace('ERROR in response: ${parsed['error']}');
        throw Exception(parsed['error'] as String? ?? 'خطأ في جلب البيانات');
      }
      return HomeDataModel.fromMap(parsed);
    }

    _trace('UNEXPECTED parsed type: ${parsed.runtimeType}');
    throw Exception(
      'توقعنا بيانات الشاشة الرئيسية ككائن، لكن حصلنا على هيكل غير معروف.',
    );
  }



  static Future<List<BankAccountModel>> getBankAccounts() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final response = await _client
        .schema('badra_core')
        .from('bank_accounts')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false);

    return (response as List)
        .map((json) => BankAccountModel.fromMap(json as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getMyTransactionsFast() async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('get_my_transactions_fast')
          .timeout(const Duration(seconds: 15));
      final parsed = _parseRpc(response);
      if (parsed is List) return parsed.cast<Map<String, dynamic>>();
      if (parsed is Map<String, dynamic>) return [parsed];
      return [];
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMyTransactionsPaginated({
    required int limit,
    required int offset,
  }) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc(
            'get_my_transactions_paginated',
            params: {'p_limit': limit, 'p_offset': offset},
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _parseRpc(response);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response format from getMyTransactionsPaginated');
      }

      if (decoded.containsKey('error')) {
        throw Exception('Supabase error: ${decoded['error']}');
      }

      final totalCount = decoded['total_count'];
      final transactions = decoded['transactions'];

      if (totalCount is! int) {
        throw Exception(
          'Invalid total_count format in getMyTransactionsPaginated',
        );
      }
      if (transactions is! List) {
        throw Exception(
          'Invalid transactions format in getMyTransactionsPaginated',
        );
      }

      return {
        'total_count': totalCount,
        'transactions': transactions.cast<Map<String, dynamic>>(),
      };
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getMyTransactionsByDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .schema('badra_core')
          .from('transactions_v2')
          .select()
          .eq('user_id', userId)
          .gte('date', from.toIso8601String())
          .lte('date', to.toIso8601String())
          .order('date', ascending: false)
          .timeout(const Duration(seconds: 15));

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<TransactionModel>> getTransactions({
    int limit = 10,
    int offset = 0,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // انتظار جلسة صالحة
    await _waitForValidSession(userId);

    try {
      final response = await _client
          .schema('badra_core')
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit)
          .range(offset, offset + limit - 1);

      return (response as List).map<TransactionModel>((json) {
        return TransactionModel(
          id: json['id'] as String,
          ref: json['id'] as String,
          title: json['description'] ?? 'Transaction',
          amount: (json['amount'] as num).toDouble(),
          date: DateTime.parse(json['created_at'] as String),
          type: _mapType(json['type'] as String),
          status: _mapStatus(json['status'] as String? ?? 'completed'),
          debtor: json['sender_phone'] ?? '',
          creditor: json['recipient_phone'] ?? '',
          notes: json['description'] ?? '',
        );
      }).toList();
    } catch (e) {
      // Propagate errors instead of falling back to mock data
      rethrow;
    }
  }

  static Future<String> getDepositData() async {
    final userId = currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // انتظار جلسة صالحة
    await _waitForValidSession(userId);

    final rawResponse = await _client
        .schema('badra_core')
        .rpc('get_deposit_data')
        .timeout(const Duration(seconds: 10));

    final result = _extractDepositResponse(rawResponse);
    if (result.isNotEmpty) {
      return result;
    }

    throw Exception(
      'لم نتمكن من استخراج نص بيانات الشحن من get_deposit_data.',
    );
  }

  static String _extractDepositResponse(Object? rawResponse) {
    if (rawResponse is String) {
      return rawResponse;
    }

    if (rawResponse is List) {
      if (rawResponse.isEmpty) return '';
      final first = rawResponse.first;
      if (first is String) {
        return first;
      }
      if (first is Map) {
        for (final value in first.values) {
          if (value is String) {
            return value;
          }
        }
      }
    }

    if (rawResponse is Map) {
      for (final value in rawResponse.values) {
        if (value is String) {
          return value;
        }
      }
    }

    return '';
  }

  static TransactionType _mapType(String type) {
    switch (type) {
      case 'incoming':
        return TransactionType.incoming;
      case 'outgoing':
        return TransactionType.outgoing;
      case 'service':
        return TransactionType.service;
      default:
        return TransactionType.outgoing;
    }
  }

  static TxStatus _mapStatus(String status) {
    switch (status) {
      case 'completed':
        return TxStatus.completed;
      case 'pending':
        return TxStatus.pending;
      case 'failed':
        return TxStatus.failed;
      default:
        return TxStatus.completed;
    }
  }
}

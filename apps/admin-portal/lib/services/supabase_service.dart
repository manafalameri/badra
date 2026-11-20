import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void _trace(dynamic msg) {
  if (kDebugMode) {
    debugPrint('[BADRA_TRACE][ADMIN] $msg');
  }
}



class SupabaseService {
  static final _client = Supabase.instance.client;

  // ══════════════════════════════════════════════════════════════
  // قائمة الانتظار (waiting_list)
  // ══════════════════════════════════════════════════════════════

  /// جلب قائمة الانتظار
  static Future<List<Map<String, dynamic>>> getWaitingList() async {
    _trace('=== getWaitingList START ===');
    _trace('>>> Calling RPC get_pending_users...');
    final response =
        await _client.schema('badra_core').rpc('get_pending_users');
    _trace('<<< RPC returned, type=${response.runtimeType}');

    dynamic decodedResponse = response;
    if (response is String) {
      _trace('response is String (${response.length} chars)');
      decodedResponse = jsonDecode(response);
    }

    if (decodedResponse is List) {
      _trace('decoded is List (${decodedResponse.length} items)');
      return List<Map<String, dynamic>>.from(
        decodedResponse.map((item) => Map<String, dynamic>.from(item as Map)),
      );
    }

    if (decodedResponse is Map && decodedResponse['data'] is List) {
      _trace('decoded is Map with data list (${decodedResponse['data'].length} items)');
      return List<Map<String, dynamic>>.from(
        (decodedResponse['data'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
    }

    _trace('No recognizable data, returning empty list');
    return <Map<String, dynamic>>[];
  }

  /// Alias to maintain compatibility with older code.
  static Future<List<Map<String, dynamic>>> getPendingUsers() async {
    return getWaitingList();
  }

  /// حذف عنصر من قائمة الانتظار
  static Future<void> deleteFromWaitingList(String id) async {
    _trace('=== deleteFromWaitingList ===');
    _trace('id=$id');
    _trace('>>> Calling RPC admin_delete_pending_user...');
    await _client.schema('badra_core').rpc('admin_delete_pending_user', params: {
      'p_id': id,
    });
    _trace('<<< delete done');
  }

  /// Alias to maintain compatibility with older code.
  static Future<void> deletePendingUser(String id) async {
    return deleteFromWaitingList(id);
  }

  /// إنشاء حساب جديد عبر Auth باستخدام signUp.
  /// يُفترض أن هناك Trigger في قاعدة البيانات ينشئ profiles + wallet + security_code + activation_codes.
  static Future<Map<String, dynamic>> createAccount({
    required String name,
    required String phone,
    required String password,
    required String ipAddress,
    required String deviceName,
    required String deviceId,
  }) async {
    _trace('=== createAccount START ===');
    _trace('name=$name, phone=$phone, password=${password.length} chars');

    try {
      final String signupPhone;
      if (phone.startsWith('+')) {
        signupPhone = phone;
      } else if (phone.startsWith('967')) {
        signupPhone = '+$phone';
      } else {
        signupPhone = '+967$phone';
      }
      _trace('signupPhone=$signupPhone');

      // ================================================================
      // RAW HTTP signup — admin session NEVER touched
      // ================================================================
      final url = dotenv.env['SUPABASE_URL']!;
      final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

      _trace('>>> POST $url/auth/v1/signup ...');
      final signupResponse = await http.post(
        Uri.parse('$url/auth/v1/signup'),
        headers: {
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'phone': signupPhone,
          'password': password,
          'data': {
            'name': name,
            'phone': signupPhone,
            'ip': ipAddress,
            'device_name': deviceName,
            'device_id': deviceId,
            'status': 'pending',
          },
        }),
      );
      _trace('<<< signup status=${signupResponse.statusCode}');

      if (signupResponse.statusCode != 200) {
        _trace('Signup failed: ${signupResponse.body}');
        final errBody = jsonDecode(signupResponse.body);
        final msg = errBody['msg'] ??
            errBody['message'] ??
            errBody['error'] ??
            'فشل إنشاء الحساب';
        return {'success': false, 'message': msg};
      }

      final signupBody = jsonDecode(signupResponse.body);
      final userId = signupBody['id']?.toString() ??
          signupBody['user']?['id']?.toString();
      if (userId == null || userId.isEmpty) {
        _trace('No user id in signup response');
        return {
          'success': false,
          'message':
              'تعذر الحصول على معرف المستخدم من استجابة التسجيل. حاول مرة أخرى.',
          'user': null,
          'activation_code': null,
        };
      }
      _trace('SUCCESS: userId=$userId');

      // ================================================================
      // Mark pending user as approved
      // ================================================================
      _trace('>>> Updating pending_users status to approved...');
      try {
        await _client
            .schema('badra_core')
            .rpc('admin_approve_pending_user', params: {
          'p_phone': signupPhone,
          'p_user_id': userId,
          'p_device_id': deviceId,
          'p_device_name': deviceName,
        });
        _trace('pending_users updated');
      } catch (e) {
        _trace('Warning: failed to update pending_users: $e');
      }

      // ================================================================
      // Get activation code — admin JWT still intact!
      // ================================================================
      _trace('>>> Calling admin_fetch_activation_code...');
      String? activationCode;
      try {
        final codeResp = await _client
            .schema('badra_core')
            .rpc('admin_fetch_activation_code', params: {
          'p_phone': signupPhone,
        });
        _trace('<<< code response: $codeResp');
        if (codeResp is Map<String, dynamic> &&
            codeResp['success'] == true) {
          activationCode = codeResp['code']?.toString();
        }
      } catch (e) {
        _trace('Failed to get activation code: $e');
      }
      _trace('activationCode=$activationCode');

      return {
        'success': true,
        'message': 'تم إنشاء الحساب بنجاح',
        'user': userId,
        'activation_code': activationCode,
      };
    } catch (e) {
      _trace('EXCEPTION in createAccount: $e');
      return {
        'success': false,
        'message': e.toString(),
        'user': null,
      };
    }
  }

  /// عدد الطلبات المعلقة
  static Future<int> getPendingRequestsCount() async {
    _trace('=== getPendingRequestsCount ===');
    _trace('>>> Calling RPC admin_count_pending_users...');
    final response =
        await _client.schema('badra_core').rpc('admin_count_pending_users');
    _trace('<<< response: $response (${response.runtimeType})');
    if (response is int) return response;
    _trace('Unexpected type, returning 0');
    return 0;
  }

  // ══════════════════════════════════════════════════════════════
  // الموافقة والرفض (approve / reject)
  // ══════════════════════════════════════════════════════════════

  /// الموافقة على طلب → إنشاء حساب Auth + بروفايل + كود تفعيل
  /// يُرجع Map يحتوي: success, message, activation_code
  static Future<Map<String, dynamic>> approvePendingUser(String phone) async {
    _trace('=== approvePendingUser START ===');
    _trace('phone=$phone');

    try {
      _trace('>>> Fetching pending user by phone=$phone...');
      final rawResp = await _client
          .schema('badra_core')
          .rpc('admin_get_pending_user_by_phone', params: {'p_phone': phone});

      final Map<String, dynamic> parsed;
      if (rawResp is String) {
        parsed = jsonDecode(rawResp) as Map<String, dynamic>;
      } else if (rawResp is Map<String, dynamic>) {
        parsed = rawResp;
      } else {
        return {'success': false, 'message': 'استجابة غير متوقعة من الخادم'};
      }

      if (parsed['success'] != true) {
        _trace('FAIL: pending user not found for phone=$phone');
        return {'success': false, 'message': parsed['message'] ?? 'المستخدم المعلق غير موجود'};
      }
      _trace('pending user found');

      final Map<String, dynamic> userRow = Map<String, dynamic>.from(parsed);

      final String name = (userRow['name'] ?? '') as String;
      final dynamic rawPassword = userRow['password'] ?? userRow['password_hash'];
      final String customerPassword = (rawPassword is String) ? rawPassword : '';
      final bool serverSaysValid = userRow['password_valid'] == true;
      final String ipAddress =
          (userRow['ip'] ?? userRow['ip_address'] ?? '') as String;
      final String deviceName =
          (userRow['device_name'] ?? userRow['device'] ?? '') as String;
      final String deviceId = (userRow['device_id'] ?? '') as String;
      _trace('user data: name=$name, ip=$ipAddress, device=$deviceName');

      // الحد الأدنى لكلمة المرور: 6 خانات (أرقام أو أحرف) — تحقق مزدوج مع الخادم
      if (!serverSaysValid || customerPassword.length < 6) {
        _trace('FAIL: invalid/missing password for phone=$phone');
        return {
          'success': false,
          'message':
              'لا يمكن الموافقة على الطلب: كلمة مرور الزبون غير صالحة ويجب ألا تقل عن 6 خانات.'
        };
      }

      // Normalize phone: ensure it has + prefix for E.164
      final String signupPhone;
      if (phone.startsWith('+')) {
        signupPhone = phone;
      } else if (phone.startsWith('967')) {
        signupPhone = '+$phone';
      } else {
        signupPhone = '+967$phone';
      }

      // Use raw HTTP signup to preserve admin session (same as createAccount)
      _trace('>>> POST signup for approved user (raw HTTP)...');
      final url = dotenv.env['SUPABASE_URL']!;
      final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

      final signupResponse = await http.post(
        Uri.parse('$url/auth/v1/signup'),
        headers: {
          'apikey': anonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'phone': signupPhone,
          'password': customerPassword,
          'data': {
            'name': name,
            'phone': signupPhone,
            'ip': ipAddress,
            'device_name': deviceName,
            'device_id': deviceId,
            'status': 'pending',
          },
        }),
      );
      _trace('<<< signup status=${signupResponse.statusCode}');

      String? userId;
      if (signupResponse.statusCode == 200) {
        final signupBody = jsonDecode(signupResponse.body);
        userId = signupBody['id']?.toString() ??
            signupBody['user']?['id']?.toString();
        _trace('SUCCESS: userId=$userId');
      } else {
        _trace('Signup failed: ${signupResponse.body}');
        final errBody = jsonDecode(signupResponse.body);
        final msg = errBody['msg'] ??
            errBody['message'] ??
            errBody['error'] ??
            'فشل إنشاء الحساب';
        return {'success': false, 'message': msg};
      }

      _trace('>>> Updating pending_users status to approved...');
      try {
        await _client
            .schema('badra_core')
            .rpc('admin_approve_pending_user', params: {
          'p_phone': signupPhone,
          'p_user_id': userId,
          'p_device_id': deviceId,
          'p_device_name': deviceName,
        });
        _trace('pending_users updated');
      } catch (e) {
        _trace('Warning: failed to update pending_users: $e');
      }

      // ================================================================
      // Get activation code
      // ================================================================
      _trace('>>> Calling admin_fetch_activation_code...');
      String? activationCode;
      try {
        final codeResp = await _client
            .schema('badra_core')
            .rpc('admin_fetch_activation_code', params: {
          'p_phone': signupPhone,
        });
        _trace('<<< code response: $codeResp');
        if (codeResp is Map<String, dynamic> &&
            codeResp['success'] == true) {
          activationCode = codeResp['code']?.toString();
        }
      } catch (e) {
        _trace('Failed to get activation code: $e');
      }
      _trace('activationCode=$activationCode');

      if (userId != null) {
        return {
          'success': true,
          'message': 'تم الموافقة وإنشاء الحساب بنجاح',
          'user': userId,
          'activation_code': activationCode,
        };
      }

      return {
        'success': true,
        'message': 'تمت الموافقة، قد تكون هناك حاجة للتحقق عبر رسالة'
      };
    } catch (e) {
      _trace('EXCEPTION in approvePendingUser: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// رفض طلب مع سبب الرفض
  static Future<Map<String, dynamic>> rejectPendingUser(
      String phone, String reason) async {
    _trace('=== rejectPendingUser ===');
    _trace('phone=$phone, reason=$reason');
    _trace('>>> Calling RPC reject_pending_user...');
    final response =
        await _client.schema('badra_core').rpc('reject_pending_user', params: {
      'p_phone': phone,
      'p_reason': reason,
    });
    _trace('<<< RPC returned, type=${response.runtimeType}');

    if (response is String) {
      _trace('response is String');
      return Map<String, dynamic>.from(jsonDecode(response));
    }
    if (response is Map) {
      _trace('response is Map');
      return Map<String, dynamic>.from(response);
    }
    _trace('Unexpected response type');
    return {'success': false, 'message': 'استجابة غير متوقعة من الخادم'};
  }

  // ══════════════════════════════════════════════════════════════
  // الحسابات (accounts)
  // ══════════════════════════════════════════════════════════════

  /// جلب جميع الحسابات المنشأة (بحد أقصى للحماية المستقبلية)
  static Future<List<Map<String, dynamic>>> getAccounts(
      {int limit = 500}) async {
    _trace('=== getAccounts START (limit=$limit) ===');
    try {
      _trace('>>> Selecting from profiles...');
      final response = await _client
          .schema('badra_core')
          .from('profiles')
          .select()
          .limit(limit)
          .order('created_at', ascending: false);
      _trace('<<< profiles returned ${(response as List).length} rows');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      _trace('getAccounts failed: $e');
      return [];
    }
  }

  /// عدد المستخدمين النشطين
  static Future<int> getActiveUsersCount() async {
    _trace('=== getActiveUsersCount (via admin_count_active_users) ===');
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_count_active_users');
      final count = (response as int);
      _trace('<<< active users: $count');
      return count;
    } on PostgrestException catch (e) {
      _trace('getActiveUsersCount failed: $e');
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // المحافظ (wallets)
  // ══════════════════════════════════════════════════════════════

  /// إجمالي أرصدة كل المحافظ
  static Future<double> getTotalWalletBalance() async {
    _trace('=== getTotalWalletBalance (via admin_get_total_balance) ===');
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_get_total_balance');
      final value = (response as num).toDouble();
      _trace('<<< total wallet balance: $value');
      return value;
    } on PostgrestException catch (e) {
      _trace('getTotalWalletBalance failed: $e');
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // العمليات المالية (transactions)
  // ══════════════════════════════════════════════════════════════

  /// آخر العمليات
  static Future<List<Map<String, dynamic>>> getLastTransactions(
      {int limit = 5}) async {
    _trace('=== getLastTransactions (via admin_get_last_transactions) === limit=$limit');
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_get_last_transactions', params: {'p_limit': limit});
      _trace('<<< returned $response');
      if (response is String) {
        return List<Map<String, dynamic>>.from(jsonDecode(response));
      }
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      _trace('getLastTransactions failed: $e');
      return [];
    }
  }

  /// حجم التداول الكلي (مجموع كل العمليات)
  static Future<double> getTradingVolume() async {
    _trace('=== getTradingVolume (via admin_get_trading_volume) ===');
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_get_trading_volume');
      final value = (response as num).toDouble();
      _trace('<<< trading volume: $value');
      return value;
    } on PostgrestException catch (e) {
      _trace('getTradingVolume failed: $e');
      return 0;
    }
  }

  /// إجمالي المستلم والموزع من transactions_v2 (النداءان بالتوازي)
  static Future<Map<String, dynamic>> getBalanceSummary() async {
    _trace('=== getBalanceSummary (parallel admin_get_sum) ===');
    try {
      final results = await Future.wait([
        _client.schema('badra_core').rpc('admin_get_sum', params: {'p_is_in': 1}),
        _client.schema('badra_core').rpc('admin_get_sum', params: {'p_is_in': 0}),
      ]);
      final received = results[0];
      final distributed = results[1];
      _trace('received=$received, distributed=$distributed');
      return {
        'total_received': received ?? 0,
        'total_distributed': distributed ?? 0,
      };
    } on PostgrestException catch (e) {
      _trace('getBalanceSummary failed: $e');
      return {'total_received': 0, 'total_distributed': 0};
    }
  }

  // ══════════════════════════════════════════════════════════════
  // الإيداعات (deposits)
  // ══════════════════════════════════════════════════════════════

  /// البحث عن حساب مستخدم في سوبابيز بواسطة رقم الهاتف أو رقم المحفظة
  static Future<Map<String, dynamic>?> findProfileByPhoneOrWallet(
      String input) async {
    _trace('=== findProfileByPhoneOrWallet: $input ===');
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    final local9 =
        digits.length >= 9 ? digits.substring(digits.length - 9) : digits;

    try {
      final response = await _client
          .schema('badra_core')
          .from('profiles')
          .select('id, user_id, name, phone, wallet_id, balance')
          .or('phone.eq.$local9,phone.eq.967$local9,phone.eq.+967$local9,wallet_id.eq.101$local9,wallet_id.eq.101967$local9')
          .limit(1);

      if (response.isNotEmpty) {
        final profile = Map<String, dynamic>.from(response.first);
        _trace('Found profile via direct query: $profile');
        await _attachCooldownInfo(profile);
        return profile;
      }
    } catch (e) {
      _trace('findProfileByPhoneOrWallet or error: $e');
    }

    // محاولة ثانية: البحث الجزئي
    try {
      final response = await _client
          .schema('badra_core')
          .from('profiles')
          .select('id, user_id, name, phone, wallet_id, balance')
          .filter('phone', 'ilike', '%$local9%')
          .limit(1);

      if (response.isNotEmpty) {
        final profile = Map<String, dynamic>.from(response.first);
        _trace('Found profile via ilike: $profile');
        await _attachCooldownInfo(profile);
        return profile;
      }
    } catch (e) {
      _trace('findProfileByPhoneOrWallet ilike error: $e');
    }

    return null;
  }

  /// إرفاق بيانات فترة التهدئة (12 ساعة) للمستخدم
  static Future<void> _attachCooldownInfo(Map<String, dynamic> profile) async {
    try {
      final userId = profile['user_id'];
      if (userId == null) {
        profile['is_in_cooldown'] = false;
        return;
      }

      final lastDepositRes = await _client
          .schema('badra_core')
          .from('deposit_requests')
          .select('created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);

      if (lastDepositRes.isNotEmpty) {
        final createdAtStr = lastDepositRes.first['created_at']?.toString();
        if (createdAtStr != null) {
          final lastDepositTime = DateTime.parse(createdAtStr);
          final diff =
              DateTime.now().toUtc().difference(lastDepositTime.toUtc());
          if (diff.inSeconds < 12 * 3600 && diff.inSeconds >= 0) {
            final remainingSeconds = (12 * 3600) - diff.inSeconds;
            final remHours = remainingSeconds ~/ 3600;
            final remMinutes = (remainingSeconds % 3600) ~/ 60;
            profile['is_in_cooldown'] = true;
            profile['cooldown_remaining_hours'] = remHours;
            profile['cooldown_remaining_minutes'] = remMinutes;
            profile['last_deposit_time'] = lastDepositTime.toIso8601String();
            profile['cooldown_text'] =
                'متبقي $remHours ساعة و $remMinutes دقيقة';
            return;
          }
        }
      }
      profile['is_in_cooldown'] = false;
    } catch (e) {
      _trace('attachCooldownInfo error: $e');
      profile['is_in_cooldown'] = false;
    }
  }

  /// إيداع يدوي لمستخدم (الأدمن فقط) مع دعم التوافق الذكي التلقائي للصيغ
  static Future<Map<String, dynamic>> manualDeposit({
    required double amount,
    required String bankName,
    required String walletId,
    required String phone,
    required String name,
    String receiptNumber = '',
    String notes = '',
  }) async {
    _trace('=== manualDeposit ===');
    _trace('walletId=$walletId, phone=$phone, name=$name, amount=$amount, bank=$bankName');

    Future<Map<String, dynamic>> callRpc(
        String wId, String ph, String nm) async {
      final response = await _client.schema('badra_core').rpc(
        'admin_manual_deposit',
        params: {
          'p_amount': amount,
          'p_bank_name': bankName,
          'p_wallet_id': wId,
          'p_phone': ph,
          'p_name': nm,
          'p_receipt_number': receiptNumber,
          'p_notes': notes,
        },
      );
      if (response is String) {
        return Map<String, dynamic>.from(jsonDecode(response));
      }
      return Map<String, dynamic>.from(response);
    }

    try {
      return await callRpc(walletId, phone, name);
    } on PostgrestException catch (e) {
      // إذا كان الخطأ "المستخدم غير موجود"، نجرب التوافق الذكي للصيغ
      if (e.message.contains('المستخدم غير موجود')) {
        _trace('Deposit failed with user not found, attempting smart permutation fallback...');

        final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
        final last9 = cleanDigits.length >= 9
            ? cleanDigits.substring(cleanDigits.length - 9)
            : cleanDigits;

        // الاحتمالات لصيغة الهاتف
        final phoneCandidates = <String>{
          phone,
          '+967$last9',
          '967$last9',
          last9,
        }.toList();

        // الاحتمالات لصيغة المحفظة
        final walletCandidates = <String>{
          walletId,
          '101967$last9',
          '101$last9',
        }.toList();

        // الاحتمالات لصيغة الاسم (تطابق الهمزة والمحاذاة)
        final trimmedName = name.trim();
        final nameCandidates = <String>{
          trimmedName,
          trimmedName.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا'),
          trimmedName.replaceAll(' الاخير', ' الأخير').replaceAll('اخير', 'أخير'),
          trimmedName.replaceAll(' الأخير', ' الاخير').replaceAll('أخير', 'اخير'),
        }.toList();

        for (final candPhone in phoneCandidates) {
          for (final candWallet in walletCandidates) {
            for (final candName in nameCandidates) {
              if (candPhone == phone &&
                  candWallet == walletId &&
                  candName == name) {
                continue; // تم تجربتها بالفعل
              }
              try {
                _trace('Retrying deposit with: wallet=$candWallet, phone=$candPhone, name=$candName');
                final retryRes = await callRpc(candWallet, candPhone, candName);
                _trace('Permutation success!');
                return retryRes;
              } catch (_) {
                // استمر للمحاولة التالية
              }
            }
          }
        }
      }
      rethrow;
    }
  }

  /// جلب سجل الإيداعات مع ترقيم الصفحات (الأدمن فقط)
  static Future<List<Map<String, dynamic>>> getDepositRecords({
    int limit = 50,
    int offset = 0,
  }) async {
    _trace('=== getDepositRecords limit=$limit offset=$offset ===');
    final response = await _client
        .schema('badra_core')
        .rpc('admin_get_deposit_records', params: {'p_limit': limit, 'p_offset': offset});
    _trace('<<< getDepositRecords returned ${response.runtimeType}');
    if (response is String) {
      final decoded = jsonDecode(response);
      return List<Map<String, dynamic>>.from(decoded);
    }
    return List<Map<String, dynamic>>.from(response);
  }

  /// جلب أكواد الحملة اليومية للوحة الأدمن (أكواد فقط بدون أي نسب مئوية)
  static Future<List<Map<String, dynamic>>> getTodayCampaignCodes() async {
    _trace('=== getTodayCampaignCodes ===');
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_get_today_campaign');
      _trace('<<< getTodayCampaignCodes returned: $response');
      if (response is String) {
        final decoded = jsonDecode(response);
        return List<Map<String, dynamic>>.from(decoded);
      }
      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return <Map<String, dynamic>>[];
    } catch (e) {
      _trace('Error in getTodayCampaignCodes: $e');
      return <Map<String, dynamic>>[];
    }
  }

}

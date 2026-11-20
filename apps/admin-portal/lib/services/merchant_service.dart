import 'package:supabase_flutter/supabase_flutter.dart';

class MerchantService {
  static final _client = Supabase.instance.client;

  static Future<Map<String, dynamic>> createMerchant({
    required String name,
    String webhookUrl = '',
  }) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_create_merchant', params: {
        'p_name': name,
        'p_webhook_url': webhookUrl,
      });

      if (response is Map<String, dynamic>) return response;
      if (response is String) {
        return Map<String, dynamic>.from({'success': false, 'error': response});
      }
      return {'success': false, 'error': 'استجابة غير متوقعة'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<List<Map<String, dynamic>>> listMerchants() async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_list_merchants');

      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> toggleMerchant({
    required String merchantId,
    required bool isActive,
  }) async {
    try {
      final response = await _client
          .schema('badra_core')
          .rpc('admin_toggle_merchant', params: {
        'p_merchant_id': merchantId,
        'p_is_active': isActive,
      });

      if (response is Map<String, dynamic>) return response;
      return {'success': false, 'error': 'استجابة غير متوقعة'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}

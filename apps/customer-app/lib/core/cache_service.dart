import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight encrypted cache for non-sensitive display data.
///
/// Does NOT store passwords, PINs, security codes, or refresh tokens.
/// Use [flutter_secure_storage] or [SecurityService] for secrets.
class CacheService {
  static const _secureKeyName = 'badra_hive_cache_key_v1';
  static const _boxName = 'badra_cache';
  static const _homeDataKey = 'home_data';

  static final _secureStorage = const FlutterSecureStorage();
  static Box<Map<dynamic, dynamic>>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();

    final encryptionKey = await _getOrCreateKey();
    _box = await Hive.openBox<Map<dynamic, dynamic>>(
      _boxName,
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Future<Uint8List> _getOrCreateKey() async {
    String? base64Key = await _secureStorage.read(key: _secureKeyName);
    if (base64Key == null) {
      final key = Hive.generateSecureKey();
      base64Key = base64Url.encode(key);
      await _secureStorage.write(key: _secureKeyName, value: base64Key);
    }
    return base64Url.decode(base64Key);
  }

  static Box<Map<dynamic, dynamic>> _requireBox() {
    final box = _box;
    if (box == null) {
      throw StateError('CacheService has not been initialized. Call init() first.');
    }
    if (!box.isOpen) {
      throw StateError('Cache box is closed.');
    }
    return box;
  }

  static Future<void> setHomeData(Map<String, dynamic> data) async {
    try {
      final box = _requireBox();
      await box.put(_homeDataKey, data);
    } catch (_) {
      // Fail silently — cache is best-effort.
    }
  }

  static Map<String, dynamic>? getHomeData() {
    try {
      final box = _requireBox();
      final raw = box.get(_homeDataKey);
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final box = _requireBox();
      await box.clear();
    } catch (_) {
      // Best-effort.
    }
  }
}

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../routes/app_routes.dart';
import 'notification_preference_service.dart';

class FcmService {
  static FirebaseMessaging? _messaging;

  static FirebaseMessaging? get _messagingNullable {
    if (_messaging != null) return _messaging;
    try {
      _messaging = FirebaseMessaging.instance;
    } on Exception {
      return null;
    }
    return _messaging;
  }

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static int _notificationId = 0;

  static Future<void> initialize() async {
    final messaging = _messagingNullable;
    if (messaging == null) return;

    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _setupLocalNotifications();
        _listenToMessages();
      }
    } catch (e) {
      print('[FcmService] Initialize failed: $e');
    }
  }

  static Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      'payment_requests',
      'طلبات الدفع',
      description: 'إشعارات طلبات الدفع الجديدة',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<void> registerTokenIfNeeded() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final messaging = _messagingNullable;
      if (messaging == null) return;

      final token = await messaging.getToken();
      if (token != null) {
        await client.schema('badra_core').rpc('register_fcm_token', params: {
          'p_fcm_token': token,
        });
      }

      messaging.onTokenRefresh.listen((newToken) async {
        try {
          final u = Supabase.instance.client.auth.currentUser;
          if (u == null) return;
          await Supabase.instance.client.schema('badra_core').rpc(
            'register_fcm_token',
            params: {'p_fcm_token': newToken},
          );
        } catch (e) {
          print('[FcmService] Token refresh failed: $e');
        }
      });
    } catch (e) {
      print('[FcmService] Token registration failed: $e');
    }
  }

  static void _listenToMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });
  }

  static Future<void> handleInitialMessage() async {
    final messaging = _messagingNullable;
    if (messaging == null) return;

    final message = await messaging.getInitialMessage();
    if (message != null) {
      _handleNotificationTap(message);
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final enabled = await NotificationPreferenceService.instance.isEnabled();
    if (!enabled) return;

    // Deduplicate: the in-app Realtime toast already covers foreground alerts.
    // Skip the system notification for the same request shown recently.
    final requestId = message.data['request_id'] as String?;
    if (requestId != null && _isRealtimeToastRecent(requestId)) return;

    final androidDetails = AndroidNotificationDetails(
      'payment_requests',
      'طلبات الدفع',
      channelDescription: 'إشعارات طلبات الدفع الجديدة',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(android: androidDetails);

    _localNotifications.show(
      _notificationId++,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  static String? _lastRealtimeToastId;
  static DateTime? _lastRealtimeToastAt;

  /// Called by the Realtime payment-request listener right before showing the
  /// in-app toast, so a redundant FCM system notification is suppressed.
  static void markRealtimeToastShown(String requestId) {
    _lastRealtimeToastId = requestId;
    _lastRealtimeToastAt = DateTime.now();
  }

  static bool _isRealtimeToastRecent(String requestId) {
    final at = _lastRealtimeToastAt;
    if (at == null) return false;
    if (_lastRealtimeToastId != requestId) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 10);
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'payment_request') {
      // Never push the authenticated shell when no session exists — it would
      // build an unauthenticated home and force a pointless redirect.
      if (Supabase.instance.client.auth.currentUser == null) return;
      Get.toNamed(
        AppRoutes.mainNavigation,
        arguments: {'initialIndex': 2},
      );
    }
  }

  static Future<bool> requestPermissionAgain() async {
    final messaging = _messagingNullable;
    if (messaging == null) return false;

    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _setupLocalNotifications();
        _listenToMessages();
        return true;
      }
      return false;
    } catch (e) {
      print('[FcmService] Re-request permission failed: $e');
      return false;
    }
  }
}

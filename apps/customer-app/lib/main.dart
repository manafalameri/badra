import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:freerasp/freerasp.dart';
import 'core/cache_service.dart';
import 'core/security_service.dart';
import 'core/session_timeout_observer.dart';
import 'core/fcm_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_export.dart';
import 'controllers/auth_controller.dart';
import 'controllers/home_controller.dart';
import 'core/supabase_service.dart';
import 'widgets/custom_error_widget.dart';
import 'widgets/animated_background.dart';

// ── Security threat handler ──
Future<void> _onSecurityThreat(String type) async {
  debugPrint('[SECURITY] Threat detected: $type');

  // Report to server (best-effort, non-blocking).
  try {
    await SupabaseService.reportSecurityEvent(type);
  } catch (_) {}

  // Terminate the session so a tampered/rooted environment gains nothing.
  try {
    await SupabaseService.signOut();
  } catch (_) {}
  try {
    await SecurityService.instance.clearAllSession();
    await SecurityService.instance.clearLoginTimestamp();
    await SecurityService.instance.clearPhone();
  } catch (_) {}

  if (Get.isRegistered<HomeController>()) {
    Get.delete<HomeController>(force: true);
  }

  if (Get.key != null && Get.currentRoute != AppRoutes.signUpLogin) {
    Get.offAllNamed(AppRoutes.signUpLogin);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) {
    return;
  }
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();

  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']!;

  FirebaseOptions? firebaseOptions;
  if (kIsWeb) {
    final apiKey = dotenv.env['FIREBASE_API_KEY'];
    final authDomain = dotenv.env['FIREBASE_AUTH_DOMAIN'];
    final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
    final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
    final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'];
    final appId = dotenv.env['FIREBASE_APP_ID'];
    final measurementId = dotenv.env['FIREBASE_MEASUREMENT_ID'];

    if (apiKey != null &&
        authDomain != null &&
        projectId != null &&
        storageBucket != null &&
        messagingSenderId != null &&
        appId != null) {
      firebaseOptions = FirebaseOptions(
        apiKey: apiKey,
        authDomain: authDomain,
        projectId: projectId,
        storageBucket: storageBucket,
        messagingSenderId: messagingSenderId,
        appId: appId,
        measurementId: measurementId,
      );
    }
  }

  final shouldUseFirebase = !kIsWeb || firebaseOptions != null;
  if (shouldUseFirebase) {
    await Firebase.initializeApp(options: firebaseOptions);
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    }
  } else {
    print(
      'Firebase web configuration missing; skipping Firebase initialization on web.',
    );
  }

  await SecurityService.configureGlobalHttpOverrides();
  final secureHttpClient = await SecurityService.createSecureHttpClient();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    httpClient: secureHttpClient,
    postgrestOptions: const PostgrestClientOptions(schema: 'badra_core'),
  );

  // ── Pre-register AuthController + load security state BEFORE first frame ──
  // This eliminates the async race that produced the temporary
  // "Something went wrong" screen on first login.
  final authController = Get.put(AuthController(), permanent: true);
  // Keep the tokens in secure storage in sync with the rotating Supabase
  // session so biometric quick-login always restores with a valid token.
  authController.setupSessionSync();
  try {
    await authController.loadSecurityState();
    debugPrint('[BOOT] Security state pre-loaded successfully');
  } catch (e, stack) {
    debugPrint('[BOOT] Security state pre-load failed: $e');
    debugPrint('[BOOT] Stack: $stack');
    // Continue anyway — SignUpLoginScreen reloads it locally as a safety net.
  }

  // ── Initialize encrypted local cache (best-effort) ──
  try {
    await CacheService.init();
  } catch (e) {
    debugPrint('[CACHE] Initialization failed: $e');
  }

  // ── freeRASP initialization (Android/iOS only) ──
  if (!kIsWeb) {
    final signingHash = dotenv.env['SIGNING_CERT_HASH'] ?? '';
    final watcherMail = dotenv.env['WATCHER_MAIL'] ?? '';

    if (signingHash.isNotEmpty) {
      debugPrint('[SECURITY] Initializing freeRASP...');
      final config = TalsecConfig(
        androidConfig: AndroidConfig(
          packageName: 'com.badra.wallet',
          signingCertHashes: [signingHash],
          supportedStores: ['com.android.vending'],
        ),
        watcherMail: watcherMail,
        isProd: true, // PRODUCTION — real reactions enabled
      );

      Talsec.instance.attachListener(ThreatCallback(
        onPrivilegedAccess: () => _onSecurityThreat('privileged_access'), // Root/Jailbreak
        onHooks: () => _onSecurityThreat('hooks'),
        onDebug: () => _onSecurityThreat('debug'),
        onAppIntegrity: () => _onSecurityThreat('app_integrity'), // Tampering
        onSimulator: () => _onSecurityThreat('simulator'),
        onUnofficialStore: () => _onSecurityThreat('unofficial_store'),
        onScreenshot: () => _onSecurityThreat('screenshot'),
        onScreenRecording: () => _onSecurityThreat('screen_recording'),
        onDeviceBinding: () => _onSecurityThreat('device_binding'),
        onObfuscationIssues: () => _onSecurityThreat('obfuscation'),
        onPasscode: () => _onSecurityThreat('passcode'),
        onDevMode: () => _onSecurityThreat('dev_mode'),
        onADBEnabled: () => _onSecurityThreat('adb_enabled'),
        onSystemVPN: () => _onSecurityThreat('system_vpn'),
        onTimeSpoofing: () => _onSecurityThreat('time_spoofing'),
        onLocationSpoofing: () => _onSecurityThreat('location_spoofing'),
        onAutomation: () => _onSecurityThreat('automation'),
        onMalware: (packages) => _onSecurityThreat('malware: $packages'),
      ));

      await Talsec.instance.start(config);
      debugPrint('[SECURITY] freeRASP started successfully');
    } else {
      debugPrint('[SECURITY] SIGNING_CERT_HASH not set, skipping freeRASP');
    }
  }

  if (shouldUseFirebase) {
    await FcmService.initialize();
  }

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]).then((value) {
    runApp(MyApp());
    FcmService.handleInitialMessage();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return GetMaterialApp(
          title: 'badra',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            return AnimatedBackground(
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.0)),
                child: child!,
              ),
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          navigatorObservers: [
            SessionTimeoutObserver(maxAge: const Duration(minutes: 10)),
          ],
          routes: AppRoutes.routes,
          initialRoute: AppRoutes.signUpLogin,
        );
      },
    );
  }
}

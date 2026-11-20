import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/device_binding_service.dart';
import 'services/security_service.dart';
import 'screens/auth/lock_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']!;

  final secureHttpClient = await SecurityService.createSecureHttpClient();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    httpClient: secureHttpClient,
    postgrestOptions: const PostgrestClientOptions(schema: 'badra_core'),
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لوحة التحكم',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1a237e),
          primary: const Color(0xFF1a237e),
          secondary: const Color(0xFF283593),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Cairo',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a237e),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1a237e),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F7FF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E4F0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1a237e), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// الحالات الممكنة للبوابة:
/// - checking   : جاري التحقق من الجلسة والجهاز مع الخادم عند الفتح البارد.
/// - locked     : جلسة صالحة لكن مطلوب تأكيد الهوية محليًا (بصمة/بيانات الدخول).
/// - showLoginForm : نموذج الدخول الكامل داخل سياق القفل.
/// - unlocked   : تم التأكيد — عرض اللوحة.
/// - loggedOut  : لا جلسة أو رفض أمني — شاشة الدخول الكاملة.
enum _GateState { checking, locked, showLoginForm, unlocked, loggedOut }

class _AuthGateState extends State<AuthGate> {
  _GateState _state = _GateState.checking;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _listenToAuthChanges();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      // tokenRefreshed is a NORMAL event that happens periodically and must
      // never log the admin out. Only react to real sign-outs.
      if (event == AuthChangeEvent.signedOut || session == null) {
        if (!mounted) return;
        setState(() => _state = _GateState.loggedOut);
      }
    });
  }

  static const _checkTimeout = Duration(seconds: 15);

  Future<void> _checkAccess() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      debugPrint('[AUTH_GATE] No session -> LOGIN');
      if (mounted) setState(() => _state = _GateState.loggedOut);
      return;
    }
    try {
      final isAdmin = await Supabase.instance.client
          .schema('badra_core')
          .rpc('is_admin')
          .timeout(_checkTimeout);
      if (isAdmin != true) {
        debugPrint('[AUTH_GATE] Not admin -> LOGIN');
        if (mounted) setState(() => _state = _GateState.loggedOut);
        return;
      }

      final deviceResult =
          await DeviceBindingService.verifyDevice().timeout(_checkTimeout);
      if (deviceResult['success'] != true) {
        debugPrint('[AUTH_GATE] Device binding failed, signing out...');
        await AuthService.signOut();
        await AuthService.clearCredentials();
        DeviceBindingService.clearDeviceId();
        if (mounted) setState(() => _state = _GateState.loggedOut);
        return;
      }

      debugPrint('[AUTH_GATE] Server checks passed -> LOCK SCREEN');
      if (mounted) setState(() => _state = _GateState.locked);
    } catch (_) {
      debugPrint('[AUTH_GATE] Check error/timeout -> LOGIN (fail-closed)');
      if (mounted) setState(() => _state = _GateState.loggedOut);
    }
  }

  /// خروج كامل إجباري: يمحو الجلسة وبيانات البصمة المحفوظة ثم يعرض
  /// شاشة الدخول الكاملة. يُستخدم لزر الخروج، الخمول، والرفض الأمني.
  Future<void> _forceSignOut({bool wipeDeviceBinding = false}) async {
    try {
      await AuthService.signOut();
    } catch (_) {}
    await AuthService.clearCredentials();
    if (wipeDeviceBinding) DeviceBindingService.clearDeviceId();
    debugPrint('[AUTH_GATE] Force sign-out complete -> LOGIN');
    if (!mounted) return;
    setState(() => _state = _GateState.loggedOut);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.checking:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case _GateState.locked:
        return LockScreen(
          onUnlocked: () {
            debugPrint('[LOCK] Unlocked -> DASHBOARD');
            if (mounted) setState(() => _state = _GateState.unlocked);
          },
          onRequestCredentials:
              () => setState(() => _state = _GateState.showLoginForm),
          onSecurityReject: () => _forceSignOut(wipeDeviceBinding: true),
        );
      case _GateState.showLoginForm:
        return LoginScreen(
          onSuccess: () =>
              setState(() => _state = _GateState.unlocked),
          onCancel: () => setState(() => _state = _GateState.locked),
        );
      case _GateState.unlocked:
        return MainScreen(onForceSignOut: () => _forceSignOut());
      case _GateState.loggedOut:
        return LoginScreen(
          onSuccess: () => setState(() => _state = _GateState.unlocked),
        );
    }
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../home_screen/home_screen.dart';
import '../history_screen/history_screen.dart';
import '../payment_requests/payment_requests_screen.dart';
import '../profile_screen/profile_screen.dart';
import '../../controllers/home_controller.dart';
import '../../widgets/app_navigation.dart';
import '../../theme/app_theme.dart';
import '../../core/security_service.dart';
import '../../core/supabase_service.dart';
import '../../core/fcm_service.dart';
import '../../routes/app_routes.dart';
import '../../widgets/exit_toast_widget.dart';
import '../../widgets/badra_luxury_toast.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  final String userName;
  final String userPhone;
  final String balance;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.userName = 'المستخدم',
    this.userPhone = '',
    this.balance = '0',
  });

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  // TODO: Replace with Riverpod/Bloc for production
  late int _currentIndex;
  Timer? _inactivityTimer;
  static const Duration _inactivityDuration = Duration(minutes: 10);
  DateTime? _lastBackPressed;
  // Throttle for recording touch activity into secure storage: one write at
  // most every 45s of active use keeps the IO cost negligible while still
  // making the resume lock activity-aware.
  static const Duration _activityRecordThrottle = Duration(seconds: 45);
  DateTime? _lastActivityRecorded;
  dynamic _paymentChannel;
  final _paymentRequestsKey = GlobalKey<PaymentRequestsScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    if (!Get.isRegistered<HomeController>()) {
      Get.put(
        HomeController(
          initialName: widget.userName,
          initialPhone: widget.userPhone,
          initialBalance: widget.balance,
        ),
      );
    }
    _resetInactivityTimer();
    _initRealtime();
    FcmService.registerTokenIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtime() {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    _paymentChannel = SupabaseService.createPaymentRequestsChannel(
      userId: userId,
      onInsert: (record) {
        if (!mounted) return;
        _refreshPendingCount();
        if (_currentIndex != 2) {
          final merchantName = record['merchant_name'] as String? ??
              (record['merchant_id'] as String? ?? '');
          final amount = record['amount'] ?? 0;
          final requestId = record['id'] as String?;
          if (requestId != null) {
            FcmService.markRealtimeToastShown(requestId);
          }
          BadraLuxuryToast.show(
            context,
            'طلب دفع جديد من $merchantName بقيمة $amount ريال',
            type: BadraToastType.info,
            duration: const Duration(seconds: 5),
            action: BadraToastAction(
              label: 'عرض',
              onTap: () => switchToTab(2),
            ),
          );
        }
      },
    );
  }

  int get _pendingRequestsCount {
    try {
      return Get.find<HomeController>().pendingRequests.length;
    } catch (_) {
      return 0;
    }
  }

  void _refreshPendingCount() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // App went to background
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // App came to foreground — lock first if the inactivity window elapsed
      // while in the background, then reset the inactivity timer.
      _checkResumeLock();
      _resetInactivityTimer();
    }
  }

  Future<void> _checkResumeLock() async {
    final expired = await SecurityService.instance
        .isLoginExpired(_inactivityDuration);
    if (!expired || !mounted) return;
    debugPrint('Resume lock: inactivity window elapsed, locking...');
    if (Get.isRegistered<HomeController>()) {
      Get.delete<HomeController>(force: true);
    }
    if (!mounted) return;
    // Soft lock: tokens are kept so the biometric shortcut instantly
    // re-admits the user on the login screen.
    Get.offAllNamed(AppRoutes.signUpLogin);
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, _handleInactivityTimeout);
  }

  /// Persist touch activity (throttled) so the resume lock and the session
  /// observer see a rolling "last activity" instead of only the last login.
  void _recordActivityThrottled() {
    final now = DateTime.now();
    if (_lastActivityRecorded != null &&
        now.difference(_lastActivityRecorded!) < _activityRecordThrottle) {
      return;
    }
    _lastActivityRecorded = now;
    SecurityService.instance.saveLoginTimestamp(now);
  }

  Future<void> _handleInactivityTimeout() async {
    debugPrint('Inactivity timeout! Locking...');
    // Soft lock: navigate back to login without revoking the session or
    // clearing the stored tokens — the biometric shortcut re-admits the
    // user instantly and the tokens are only used after local auth.
    if (Get.isRegistered<HomeController>()) {
      Get.delete<HomeController>(force: true);
    }
    if (!mounted) return;
    Get.offAllNamed(AppRoutes.signUpLogin);
  }

  void switchToTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _onBackInvoked() {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      ExitToastWidget.show(context);
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackInvoked();
      },
      child: GetBuilder<HomeController>(
        builder: (controller) {
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              _resetInactivityTimer();
              _recordActivityThrottled();
            },
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                backgroundColor: AppTheme.backgroundDeep,
                extendBody: true,
                body: IndexedStack(
                  index: _currentIndex,
                  children: [
                    HomeScreen(
                      userName: controller.userName.value,
                      userPhone: controller.userPhone.value,
                      walletId: controller.walletId.value,
                      balance: controller.balance.value,
                      onNavigateToHistory: () => switchToTab(1),
                      onNavigateToProfile: () => switchToTab(3),
                      onNavigateToPaymentRequests: () => switchToTab(2),
                    ),
                    HistoryScreen(),
                    PaymentRequestsScreen(
                      key: _paymentRequestsKey,
                      onRequestsChanged: _refreshPendingCount,
                    ),
                    ProfileScreen(
                      userName: controller.userName.value,
                      userPhone: controller.userPhone.value,
                      balance: controller.balance.value,
                      joinedAt: controller.joinedAt.value,
                    ),
                  ],
                ),
                bottomNavigationBar: AppNavigation(
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                  badgeCount: _pendingRequestsCount,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dashboard/dashboard_screen.dart';
import '../accounts/accounts_screen.dart';
import '../balance/balance_screen.dart';
import '../deposits/deposits_screen.dart';
import '../merchants/merchants_screen.dart';
import '../../services/device_binding_service.dart';
import '../../widgets/app_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onForceSignOut});

  /// يُستدعى عند الخروج الكامل الإجباري: زر الخروج، الخمول 5 دقائق،
  /// أو الرفض الأمني من الخادم. البوابة تمحو الجلسة وبيانات البصمة.
  final VoidCallback onForceSignOut;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  Timer? _inactivityTimer;
  Timer? _deviceVerifyTimer;
  int _consecutiveTransientFailures = 0;
  final Duration _inactivityTimeout = const Duration(minutes: 5);
  final Duration _deviceVerifyInterval = const Duration(minutes: 5);
  static const int _maxConsecutiveTransientFailures = 3;

  // Lazy-loaded screens - only created when first accessed
  final List<Widget?> _screens = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    _startInactivityTimer();
    _startDeviceVerifyTimer();
    // Enable FLAG_SECURE to prevent screenshots/recording on all screens
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  Widget _getScreen(int index) {
    if (_screens[index] == null) {
      switch (index) {
        case 0:
          _screens[index] = const DashboardScreen();
          break;
        case 1:
          _screens[index] = const AccountsScreen();
          break;
        case 2:
          _screens[index] = const BalanceScreen();
          break;
        case 3:
          _screens[index] = const DepositsScreen();
          break;
        case 4:
          _screens[index] = const MerchantsScreen();
          break;
      }
    }
    return _screens[index]!;
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تسجيل الخروج',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: const Text('هل تريد تسجيل الخروج من لوحة التحكم؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(
                    fontFamily: 'Cairo', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('خروج',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.onForceSignOut();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _handleInactivityLogout);
  }

  void _startDeviceVerifyTimer() {
    _deviceVerifyTimer?.cancel();
    _deviceVerifyTimer = Timer.periodic(_deviceVerifyInterval, (_) => _verifyDevicePeriodically());
  }

  void _resetInactivityTimer(PointerEvent _) {
    if (!mounted) return;
    _startInactivityTimer();
  }

  Future<void> _handleInactivityLogout() async {
    // خروج كامل إجباري بسبب الخمول (مثل زر الخروج تمامًا)
    widget.onForceSignOut();
  }

  Future<void> _verifyDevicePeriodically() async {
    if (!mounted) return;
    try {
      final result = await DeviceBindingService.verifyDevice();

      if (result['success'] == true) {
        _consecutiveTransientFailures = 0;
        return;
      }

      final isTransient = result['transient'] == true;

      // Server explicitly rejected this device -> security violation, sign
      // out immediately (fail-closed, unchanged behavior).
      if (!isTransient) {
        debugPrint(
            '[MAIN] Device rejected by server: ${result['error']}');
        widget.onForceSignOut();
        return;
      }

      // Transient failure (network blip / timeout): do NOT log out on the
      // first miss. Retry on the next cycles; only give up after several
      // consecutive failures.
      _consecutiveTransientFailures++;
      debugPrint('[MAIN] Transient verify failure '
          '#$_consecutiveTransientFailures/$_maxConsecutiveTransientFailures');
      if (_consecutiveTransientFailures >=
          _maxConsecutiveTransientFailures) {
        debugPrint('[MAIN] Too many consecutive failures, signing out');
        _consecutiveTransientFailures = 0;
        widget.onForceSignOut();
      }
    } catch (e) {
      debugPrint('[MAIN] Periodic device verification error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _resetInactivityTimer,
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: List.generate(5, (i) => _getScreen(i)),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              if (index == 5) {
                _logout();
              } else {
                setState(() => _selectedIndex = index);
              }
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            selectedLabelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'الرئيسية',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_add_outlined),
                activeIcon: Icon(Icons.person_add_rounded),
                label: 'الحسابات',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'الرصيد',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_rounded),
                activeIcon: Icon(Icons.payments_outlined),
                label: 'الإيداعات',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.store_outlined),
                activeIcon: Icon(Icons.store_rounded),
                label: 'المتاجر',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.logout_rounded),
                activeIcon: Icon(Icons.logout_rounded),
                label: 'خروج',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _deviceVerifyTimer?.cancel();
    super.dispose();
  }
}

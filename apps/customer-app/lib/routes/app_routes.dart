import 'package:flutter/material.dart';

import '../presentation/history_screen/history_screen.dart';
import '../presentation/home_screen/home_screen.dart';
import '../presentation/main_navigation/main_navigation_screen.dart';
import '../presentation/pin_setup_screen/pin_setup_screen.dart';
import '../presentation/sign_up_login_screen/sign_up_login_screen.dart';
import '../presentation/waiting_approval_screen/waiting_approval_screen.dart';
import '../presentation/close_account_screen/close_account_screen.dart';
class AppRoutes {
  static const String signUpLogin = '/sign-up-login-screen';
  static const String waitingApproval = '/waiting-approval';
  static const String activation = '/activation';
  static const String pinSetup = '/pin-setup';
  static const String mainNavigation = '/main-navigation';
  static const String homeScreen = '/home-screen';
  static const String historyScreen = '/history-screen';
  static const String closeAccount = '/close-account';

  static Map<String, WidgetBuilder> routes = {
    signUpLogin: (context) => const SignUpLoginScreen(),
    waitingApproval: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      return WaitingApprovalScreen(
        userName: args?['name'] as String?,
        userPhone: args?['phone'] as String?,
      );
    },
    activation: (context) => const SignUpLoginScreen(),
    pinSetup: (context) => const PinSetupScreen(),
    mainNavigation: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      return MainNavigationScreen(
        initialIndex: args?['initialIndex'] as int? ?? 0,
        userName: args?['name'] as String? ?? 'المستخدم',
        userPhone: args?['phone'] as String? ?? '',
        balance: args?['balance'] as String? ?? '0',
      );
    },
    homeScreen: (context) => const HomeScreen(),
    historyScreen: (context) => const HistoryScreen(),
    closeAccount: (context) => const CloseAccountScreen(),
  };
}

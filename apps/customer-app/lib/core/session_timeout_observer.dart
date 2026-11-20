import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'security_service.dart';
import 'supabase_service.dart';
import '../routes/app_routes.dart';

class SessionTimeoutObserver extends NavigatorObserver {
  final Duration maxAge;

  SessionTimeoutObserver({required this.maxAge});

  // Prevent re-entrant handling when navigation triggers further observer events
  bool _isHandling = false;

  // Cooldown window: right after a forced redirect the route stack is being
  // rebuilt, which fires additional observer events. Skipping them prevents
  // the login screen from being re-created over and over (the flicker loop).
  static const Duration _redirectCooldown = Duration(seconds: 2);
  DateTime? _lastForcedRedirectAt;

  Future<void> _checkSessionExpired(Route<dynamic>? route) async {
    if (_isHandling) return;

    // 1) No active session → nothing to expire. This is the key guard that
    //    breaks the startup loop: an anonymous user on the login screen is
    //    never bounced back to the login screen.
    if (SupabaseService.currentUserId == null) return;

    // 2) Pre-auth screens (login + signup approval) never expire: a redirect
    //    there is a no-op and only recreates the whole login UI (flicker) or
    //    breaks the signup flow when a stale session lingers in memory.
    final routeName = route?.settings.name;
    if (routeName == AppRoutes.signUpLogin ||
        routeName == AppRoutes.waitingApproval) {
      return;
    }

    // 3) Debounce: skip if we just forced a redirect a moment ago.
    final last = _lastForcedRedirectAt;
    if (last != null &&
        DateTime.now().difference(last) < _redirectCooldown) {
      return;
    }

    final expired = await SecurityService.instance.isLoginExpired(maxAge);
    if (!expired) {
      // The user is active — roll the inactivity window forward so an active
      // session is never killed mid-use.
      await SecurityService.instance.saveLoginTimestamp(DateTime.now());
      return;
    }

    _isHandling = true;
    _lastForcedRedirectAt = DateTime.now();
    try {
      // Soft lock: the stored tokens are KEPT so the biometric/PIN shortcut
      // can instantly re-admit the user on the login screen. The tokens are
      // only ever consumed after a successful local authentication, so the
      // security gate stays in place.
      await SecurityService.instance.clearLoginTimestamp();
    } finally {
      // Schedule navigation after the current frame to avoid re-entrancy.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed(AppRoutes.signUpLogin);
        // allow future checks after navigation completes
        _isHandling = false;
      });
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _checkSessionExpired(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _checkSessionExpired(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _checkSessionExpired(previousRoute ?? route);
  }
}

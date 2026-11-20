import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/friendly_error.dart';
import '../theme/app_theme.dart';

enum BadraToastType { success, error, warning, info }

class BadraToastAction {
  final String label;
  final VoidCallback onTap;

  const BadraToastAction({required this.label, required this.onTap});
}

/// إشعار فاخر موحّد — كبسولة عائمة في منتصف الشاشة
/// يعمل عبر OverlayEntry (غير حاجب للمس) على نمط ExitToastWidget.
class BadraLuxuryToast {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    Object? message, {
    BadraToastType type = BadraToastType.info,
    Duration? duration,
    BadraToastAction? action,
  }) {
    final cleanText = friendlyError(message);
    if (cleanText.isEmpty) return;

    _currentEntry?.remove();
    _currentEntry = null;

    final resolvedDuration =
        duration ?? Duration(seconds: type == BadraToastType.error ? 4 : 3);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _BadraLuxuryToastContent(
        message: cleanText,
        type: type,
        duration: resolvedDuration,
        action: action,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _BadraLuxuryToastContent extends StatefulWidget {
  final String message;
  final BadraToastType type;
  final Duration duration;
  final BadraToastAction? action;
  final VoidCallback onDismissed;

  const _BadraLuxuryToastContent({
    required this.message,
    required this.type,
    required this.duration,
    required this.action,
    required this.onDismissed,
  });

  @override
  State<_BadraLuxuryToastContent> createState() =>
      _BadraLuxuryToastContentState();
}

class _BadraLuxuryToastContentState extends State<_BadraLuxuryToastContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }

    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _timer?.cancel();

    if (MediaQuery.of(context).disableAnimations) {
      widget.onDismissed();
      return;
    }

    _controller
        .animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInCubic,
        )
        .then((_) {
          if (mounted) widget.onDismissed();
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.type) {
    BadraToastType.success => Icons.check_circle_outline_rounded,
    BadraToastType.error => Icons.error_outline_rounded,
    BadraToastType.warning => Icons.warning_amber_rounded,
    BadraToastType.info => Icons.info_outline_rounded,
  };

  Color get _accentColor => switch (widget.type) {
    BadraToastType.success => AppTheme.emeraldPrimary,
    BadraToastType.error => AppTheme.error,
    BadraToastType.warning => AppTheme.goldAccent,
    BadraToastType.info => AppTheme.silverAccent,
  };

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
              ),
              child: GestureDetector(
                onTap: _dismiss,
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  label: widget.message,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final t = _controller.value;
                      return Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.8 + (0.2 * t),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDeep.withAlpha(250),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _accentColor.withAlpha(90),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withAlpha(30),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withAlpha(128),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _accentColor.withAlpha(30),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_icon, color: _accentColor, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: GoogleFonts.sora(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                decoration: TextDecoration.none,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          if (widget.action != null) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                widget.action!.onTap();
                                _dismiss();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  widget.action!.label,
                                  style: GoogleFonts.sora(
                                    color: AppTheme.goldAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

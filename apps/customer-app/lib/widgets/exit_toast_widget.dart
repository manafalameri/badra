import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class ExitToastWidget {
  static OverlayEntry? _currentEntry;

  static void show(BuildContext context) {
    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ExitToastContent(
        onDismiss: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    Overlay.of(context).insert(entry);
  }

  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _ExitToastContent extends StatefulWidget {
  final VoidCallback onDismiss;
  const _ExitToastContent({required this.onDismiss});

  @override
  State<_ExitToastContent> createState() => _ExitToastContentState();
}

class _ExitToastContentState extends State<_ExitToastContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _controller.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Positioned(
      bottom: 100 + bottomPadding,
      left: 24,
      right: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _controller.value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - _controller.value)),
              child: child,
            ),
          );
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xE6112318),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(40),
              ),
            ),
            child: Center(
              child: Text(
                'اضغط مرة أخرى للخروج',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

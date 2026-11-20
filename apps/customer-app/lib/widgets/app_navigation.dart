import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AppNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int badgeCount;

  const AppNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard.withAlpha(217),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(46),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(102),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppTheme.emeraldPrimary.withAlpha(15),
                  blurRadius: 12,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Flexible(
                  fit: FlexFit.tight,
                  child: _NavItem(
                    icon: Icons.home_rounded,
                    label: 'الرئيسية',
                    isActive: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                ),
                Flexible(
                  fit: FlexFit.tight,
                  child: _NavItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'السجل',
                    isActive: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                ),
                Flexible(
                  fit: FlexFit.tight,
                  child: _NavItem(
                    icon: Icons.payments_rounded,
                    label: 'الطلبات',
                    isActive: currentIndex == 2,
                    badgeCount: badgeCount,
                    onTap: () => onTap(2),
                  ),
                ),
                Flexible(
                  fit: FlexFit.tight,
                  child: _NavItem(
                    icon: Icons.person_rounded,
                    label: 'الحساب',
                    isActive: currentIndex == 3,
                    onTap: () => onTap(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.emeraldPrimary.withAlpha(38)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            widget.icon,
                            size: 22,
                            color: widget.isActive
                                ? AppTheme.emeraldPrimary
                                : AppTheme.textMuted,
                          ),
                          if (widget.badgeCount > 0)
                            Positioned(
                              right: -8,
                              top: -6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  widget.badgeCount > 99
                                      ? '99+'
                                      : widget.badgeCount.toString(),
                                  style: GoogleFonts.sora(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.label,
                        style: GoogleFonts.sora(
                          fontSize: 10,
                          fontWeight: widget.isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.isActive
                              ? AppTheme.emeraldPrimary
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

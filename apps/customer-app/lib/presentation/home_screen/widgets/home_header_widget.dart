import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/badra_brand_logo.dart';

class HomeHeaderWidget extends StatelessWidget {
  final String userName;
  final VoidCallback? onProfileTap;

  const HomeHeaderWidget({
    super.key,
    required this.userName,
    this.onProfileTap,
  });

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'مساء الخير';
    return 'مساء النور';
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return parts[0].isNotEmpty ? parts[0][0] : '?';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D2A1A), Colors.transparent],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const BadraBrandLogo(size: 28),
                            const SizedBox(width: 10),
                            Text(
                              'بذرة',
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _getGreeting(),
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.sora(
                            fontSize: 20,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildNotificationButton(),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onProfileTap,
                        child: _buildAvatar(_getInitials(userName)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return Stack(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(153),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.emeraldMuted.withAlpha(77),
              width: 1,
            ),
          ),
          child: const Icon(
            Icons.notifications_outlined,
            color: AppTheme.textSecondary,
            size: 20,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.emeraldPrimary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.emeraldPrimary.withAlpha(128),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(String initials) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.emeraldPrimary, AppTheme.emeraldDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.emeraldPrimary.withAlpha(77),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.backgroundDeep,
          ),
        ),
      ),
    );
  }
}

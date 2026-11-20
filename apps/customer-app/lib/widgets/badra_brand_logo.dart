import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class BadraBrandLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final Color? color;

  const BadraBrandLogo({
    super.key,
    this.size = 32,
    this.showText = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final primary = color ?? AppTheme.emeraldPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: showText
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            'assets/images/img_app_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _fallbackLogo(primary);
            },
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Text(
            'بذرة',
            style: GoogleFonts.sora(
              fontSize: size * 0.8,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _fallbackLogo(Color primary) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'ب',
            style: GoogleFonts.sora(
              fontSize: size * 0.6,
              fontWeight: FontWeight.w800,
              color: AppTheme.backgroundDeep,
            ),
          ),
          Positioned(
            top: size * 0.18,
            right: size * 0.18,
            child: Container(
              width: size * 0.14,
              height: size * 0.14,
              decoration: BoxDecoration(
                color: AppTheme.backgroundDeep,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

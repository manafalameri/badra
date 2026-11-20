import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/badra_brand_logo.dart';

class LuxuryCardWidget extends StatefulWidget {
  final String holderName;
  final String cardNumber;
  final String balance;

  const LuxuryCardWidget({
    super.key,
    required this.holderName,
    required this.cardNumber,
    required this.balance,
  });

  @override
  State<LuxuryCardWidget> createState() => _LuxuryCardWidgetState();
}

class _LuxuryCardWidgetState extends State<LuxuryCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = (size.width - 40).clamp(0.0, 420.0);
    final cardHeight = cardWidth * 0.58;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: const [
                  Color(0xFF0A2018),
                  Color(0xFF0D2E1E),
                  Color(0xFF071510),
                  Color(0xFF0A2018),
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.emeraldPrimary.withAlpha(51),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(128),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: AppTheme.emeraldPrimary.withAlpha(51),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  top: -cardHeight * 0.3,
                  right: -cardWidth * 0.2,
                  child: Container(
                    width: cardWidth * 0.7,
                    height: cardWidth * 0.7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.emeraldPrimary.withAlpha(18),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -cardHeight * 0.4,
                  left: -cardWidth * 0.15,
                  child: Container(
                    width: cardWidth * 0.6,
                    height: cardWidth * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.goldAccent.withAlpha(13),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // Shimmer overlay
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomPaint(
                      painter: _ShimmerPainter(
                        progress: _shimmerController.value,
                      ),
                    ),
                  ),
                ),
                // Card content
                Padding(
                  padding: EdgeInsets.all(cardWidth * 0.07),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [BadraBrandLogo(size: 28)]),
                      const Spacer(),
                      Text(
                        'الرصيد المتاح',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: cardWidth * 0.028,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              widget.balance,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: GoogleFonts.sora(
                                fontSize: cardWidth * 0.072,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                fontFeatures: [
                                  const FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ر.ي',
                            style: GoogleFonts.sora(
                              fontSize: cardWidth * 0.032,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.goldAccent,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.cardNumber.split(' ').take(3).map((group) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Text(
                                group,
                                style: GoogleFonts.sora(
                                  fontSize: cardWidth * 0.038,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary.withAlpha(217),
                                  fontFeatures: [
                                    const FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.holderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(
                          fontSize: cardWidth * 0.038,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  _ShimmerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * (progress * 1.6 - 0.3);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withAlpha(10),
          Colors.white.withAlpha(15),
          Colors.white.withAlpha(10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(x - 80, 0, 160, size.height));

    canvas.save();
    canvas.rotate(math.pi / 8);
    canvas.drawRect(
      Rect.fromLTWH(x - 80, -size.height, 160, size.height * 3),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}

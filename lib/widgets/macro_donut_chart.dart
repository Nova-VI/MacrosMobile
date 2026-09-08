import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MacroDonutChart extends StatelessWidget {
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double totalCalories;

  const MacroDonutChart({
    super.key,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.totalCalories,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      height: 108,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, animValue, _) {
          return CustomPaint(
            painter: _DonutChartPainter(
              proteinG: proteinG * animValue,
              carbsG: carbsG * animValue,
              fatG: fatG * animValue,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rolling Count-Up Number Ticker
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: totalCalories),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, val, _) {
                      return Text(
                        val.round().toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textMain,
                          letterSpacing: -0.5,
                        ),
                      );
                    },
                  ),
                  const Text(
                    'kcal',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double proteinG;
  final double carbsG;
  final double fatG;

  _DonutChartPainter({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;
    const strokeWidth = 8.5;

    // Track Background Circle
    final bgPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final totalEnergy = (proteinG * 4) + (carbsG * 4) + (fatG * 9);
    if (totalEnergy <= 0) return;

    double startAngle = -math.pi / 2;

    void drawSegment(double energyValue, Color color) {
      if (energyValue <= 0) return;
      final sweepAngle = (energyValue / totalEnergy) * 2 * math.pi;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle > 0.08 ? sweepAngle - 0.04 : sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }

    drawSegment(proteinG * 4, AppColors.primary);
    drawSegment(carbsG * 4, AppColors.secondary);
    drawSegment(fatG * 9, AppColors.warning);
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.proteinG != proteinG ||
        oldDelegate.carbsG != carbsG ||
        oldDelegate.fatG != fatG;
  }
}
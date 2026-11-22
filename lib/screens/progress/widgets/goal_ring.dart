import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';

/// Days practised this week as a ring that fills toward the weekly goal
/// (or toward all seven days when there is no goal). Green once the goal is met.
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.days, required this.goal});

  final int days;
  final int? goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = goal ?? DateTime.daysPerWeek;
    final met = goal != null && days >= goal!;
    final text = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (days / target).clamp(0.0, 1.0)),
      duration: AppDurations.of(context, AppDurations.celebrate),
      curve: AppCurves.standard,
      builder: (context, fill, _) => CustomPaint(
        size: const Size.square(AppSizes.goalRing),
        painter: _RingPainter(
          fill,
          track: colors.cardMuted,
          color: met ? colors.correct : colors.primary,
        ),
        child: SizedBox.square(
          dimension: AppSizes.goalRing,
          // Large text shrinks to fit inside the ring.
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.goalRingStroke * 2),
            child: FittedBox(
              child: Column(
                children: [
                  Text(
                    '$days',
                    key: const Key('progress-days'),
                    style: text.headlineMedium,
                  ),
                  Text('of $target days', style: text.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fill, {required this.track, required this.color});
  final double fill;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(AppSizes.goalRingStroke / 2);
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppSizes.goalRingStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke(track));
    if (fill > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fill,
        false,
        stroke(color),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill || old.color != color || old.track != track;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/enter_in.dart';
import '../../../domain/models/practice_card.dart';
import '../practice_provider.dart';

/// After an answer: right or wrong in its color, a small burst when right,
/// the explanation and whether the answer was saved.
class PracticeResult extends StatelessWidget {
  const PracticeResult({super.key, required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PracticeProvider>();
    final e = entry;
    final result = e.answer!.result;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final wrong = result == 'wrong' || result == 'again';
    final color = wrong ? colors.wrong : colors.correct;
    return EnterIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.m,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.tint(color),
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (!wrong && !MediaQuery.disableAnimationsOf(context))
                        const Celebration(),
                      Icon(
                        wrong ? Icons.refresh_rounded : Icons.check_circle,
                        color: color,
                        size: AppSizes.badge,
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${result[0].toUpperCase()}${result.substring(1)}',
                        style: text.titleLarge!.copyWith(color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (e.test.explanation != null)
            Text(e.test.explanation!, style: text.bodyLarge),
          if (e.saved) Text('Answer saved', style: text.bodyMedium),
          if (e.saving) Text('Saving answer…', style: text.bodyMedium),
          if (e.error != null) ...[
            Text(e.error!),
            TextButton(
              onPressed: e.unavailable ? p.refresh : () => p.retry(e),
              child: Text(e.unavailable ? 'Refresh Practice' : 'Retry answer'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A one-time burst of colored dots around a right answer.
class Celebration extends StatelessWidget {
  const Celebration({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppDurations.celebrate,
        curve: AppCurves.standard,
        builder: (context, t, _) => CustomPaint(
          size: const Size.square(AppSizes.badge),
          painter: _BurstPainter(t, [
            c.correct,
            c.later,
            c.like,
            c.concept,
            c.primary,
          ]),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.colors);
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final center = size.center(Offset.zero);
    const dots = 12;
    for (var i = 0; i < dots; i++) {
      final angle = i * 2 * math.pi / dots;
      final reach = size.width * (0.5 + 0.9 * t) * (i.isEven ? 1 : 0.75);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 1 - t);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * reach,
        size.width * 0.07 * (1 - t * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

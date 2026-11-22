import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';
import '../theme/theme_extensions.dart';

/// Which picture an empty state shows.
enum EmptyArtKind { cards, practice, library, search }

/// A small picture drawn in code from the theme's colors, so it suits light
/// and dark mode and needs no image files. Decorative: screen readers skip it.
class EmptyArt extends StatelessWidget {
  const EmptyArt({super.key, required this.kind});

  final EmptyArtKind kind;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size.square(AppSizes.emptyArt),
      painter: _ArtPainter(kind, context.colors),
    ),
  );
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.c);

  final EmptyArtKind kind;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    canvas.drawCircle(center, w * 0.46, Paint()..color = c.tint(c.primary));
    switch (kind) {
      case EmptyArtKind.cards:
        _card(canvas, w, center.translate(-w * 0.12, w * 0.02), -0.26, c.quote);
        _card(canvas, w, center.translate(w * 0.12, w * 0.02), 0.26, c.news);
        _card(canvas, w, center, 0, c.concept);
        _sparkle(canvas, Offset(w * 0.8, w * 0.2), w * 0.08, c.later);
        _sparkle(canvas, Offset(w * 0.18, w * 0.78), w * 0.05, c.like);
      case EmptyArtKind.practice:
        _card(canvas, w, center.translate(0, -w * 0.02), -0.08, c.due);
        final at = Offset(w * 0.7, w * 0.7);
        canvas.drawCircle(at, w * 0.15, Paint()..color = c.correct);
        final tick = Path()
          ..moveTo(at.dx - w * 0.065, at.dy)
          ..lineTo(at.dx - w * 0.015, at.dy + w * 0.05)
          ..lineTo(at.dx + w * 0.07, at.dy - w * 0.05);
        canvas.drawPath(tick, _line(c.card, AppSizes.stroke * 2));
        _sparkle(canvas, Offset(w * 0.22, w * 0.24), w * 0.06, c.later);
      case EmptyArtKind.library:
        _card(canvas, w, center.translate(-w * 0.06, 0), -0.12, c.research);
        _card(canvas, w, center.translate(w * 0.06, w * 0.02), 0.1, c.like);
        // A bookmark ribbon hanging off the front card.
        final top = w * 0.3, x = w * 0.6;
        final ribbon = Path()
          ..moveTo(x, top)
          ..lineTo(x + w * 0.1, top)
          ..lineTo(x + w * 0.1, top + w * 0.24)
          ..lineTo(x + w * 0.05, top + w * 0.19)
          ..lineTo(x, top + w * 0.24)
          ..close();
        canvas.drawPath(ribbon, Paint()..color = c.like);
        _sparkle(canvas, Offset(w * 0.2, w * 0.22), w * 0.06, c.later);
      case EmptyArtKind.search:
        _card(canvas, w, center.translate(-w * 0.06, 0), -0.1, c.concept);
        final lens = Offset(w * 0.6, w * 0.56);
        canvas.drawCircle(lens, w * 0.14, Paint()..color = c.card);
        canvas.drawCircle(
          lens,
          w * 0.14,
          _line(c.primary, AppSizes.stroke * 3),
        );
        canvas.drawLine(
          lens.translate(w * 0.1, w * 0.1),
          lens.translate(w * 0.2, w * 0.2),
          _line(c.primary, AppSizes.stroke * 4),
        );
        _sparkle(canvas, Offset(w * 0.8, w * 0.2), w * 0.06, c.later);
    }
  }

  Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// A small learning card: white body, a colored band and three text lines.
  void _card(Canvas canvas, double w, Offset at, double turn, Color band) {
    final width = w * 0.42, height = w * 0.54, corner = w * 0.06;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(turn);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      Radius.circular(corner),
    );
    canvas.drawRRect(
      body.shift(Offset(0, w * 0.02)),
      Paint()..color = c.text.withValues(alpha: 0.08),
    );
    canvas.drawRRect(body, Paint()..color = c.card);
    canvas.drawRRect(body, _line(c.divider, AppSizes.stroke / 2));
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(
      Rect.fromLTWH(-width / 2, -height / 2, width, height * 0.16),
      Paint()..color = band,
    );
    canvas.restore();
    for (var i = 0; i < 3; i++) {
      final y = -height * 0.08 + i * height * 0.16;
      final end = width * (i == 2 ? 0.05 : 0.3);
      canvas.drawLine(
        Offset(-width * 0.3, y),
        Offset(end, y),
        _line(c.cardMuted, AppSizes.stroke * 2),
      );
    }
    canvas.restore();
  }

  /// A four-pointed sparkle.
  void _sparkle(Canvas canvas, Offset at, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final d = i.isEven ? r : r * 0.32;
      final p = at + Offset(math.cos(angle) * d, math.sin(angle) * d);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.c != c;
}

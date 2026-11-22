import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';

/// Light or dark as one icon, after toggles.dev's "Around": the sun's six
/// dots slide into it while it grows into a moon. Tap to switch.
class ThemeToggle extends StatefulWidget {
  const ThemeToggle({super.key, required this.dark, required this.onChanged});

  final bool dark;
  final ValueChanged<bool> onChanged;

  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle>
    with SingleTickerProviderStateMixin {
  // Time since the last switch, as a share of AppDurations.themeToggle.
  late final _time = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(ThemeToggle old) {
    super.didUpdateWidget(old);
    if (old.dark == widget.dark) return;
    _time.duration = AppDurations.of(context, AppDurations.themeToggle);
    _time.forward(from: 0);
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.dark ? 'Switch to light theme' : 'Switch to dark theme',
    onPressed: () => widget.onChanged(!widget.dark),
    icon: SizedBox.square(
      dimension: AppSizes.themeToggle,
      child: CustomPaint(
        painter: AroundPainter(
          _time,
          dark: widget.dark,
          color: context.colors.text,
        ),
      ),
    ),
  );
}

/// The "Around" drawing, in its original 32×32 units and timings.
class AroundPainter extends CustomPainter {
  AroundPainter(this.time, {required this.dark, required this.color})
    : super(repaint: time);

  final Animation<double> time;
  final bool dark;
  final Color color;

  static const _box = 32.0, _sun = 8.4, _dot = 2.3;
  static const _mid = Offset(16, 16);
  static const _dots = [
    Offset(16, 3.3),
    Offset(27, 9.7),
    Offset(27, 22.3),
    Offset(16, 28.7),
    Offset(5, 22.3),
    Offset(5, 9.7),
  ];

  /// When each dot starts growing back, on the way to the sun.
  static const _delays = [0.253, 0.348, 0.443, 0.538, 0.633, 0.728];

  /// The round bite that turns the grown sun into a moon: half the distance
  /// between the arc's two ends in the original path.
  static final _bite = math.sqrt(16 * 16 + 13 * 13) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    double ease(double from, double length) =>
        Curves.ease.transform(((t - from) / length).clamp(0.0, 1.0));
    // How far into the moon: going dark takes the whole time, light 60%.
    final moon = dark ? ease(0, 1) : 1 - ease(0, 0.6);
    final turn = -math.pi / 2 * moon;

    canvas.scale(size.width / _box);
    // The bite moves in and turns a quarter round the centre, as in the CSS.
    final cut = Path()
      ..moveTo(0, 0)
      ..lineTo(42, 0)
      ..lineTo(42, 30)
      ..arcToPoint(
        const Offset(26, 43),
        radius: Radius.circular(_bite),
        clockwise: false,
      )
      ..lineTo(0, 43)
      ..close();
    canvas
      ..translate(_mid.dx, _mid.dy)
      ..rotate(turn)
      ..translate(-_mid.dx, -_mid.dy)
      ..clipPath(cut.shift(Offset(-12 * moon, -14 * moon)))
      ..translate(_mid.dx, _mid.dy)
      ..rotate(-turn)
      ..translate(-_mid.dx, -_mid.dy);

    final paint = Paint()..color = color;
    canvas.drawCircle(_mid, _sun * (1 + 0.4 * moon), paint);
    // Dots shrink toward the centre (SVG scales around the whole drawing).
    for (final (i, d) in _dots.indexed) {
      final s = dark ? 1 - ease(0, 0.4) : ease(_delays[i], 0.2);
      if (s > 0) canvas.drawCircle(_mid + (d - _mid) * s, _dot * s, paint);
    }
  }

  @override
  bool shouldRepaint(AroundPainter old) =>
      old.dark != dark || old.color != color;
}

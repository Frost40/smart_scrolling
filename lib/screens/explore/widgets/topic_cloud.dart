import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';

/// Paints one soft shape behind the open area's chip and its sub-topic
/// strip, joined by curved corners, so they read as a single piece. It reads
/// where [chip] and [strip] are inside [box] at paint time and repaints when
/// the area row scrolls ([repaint]).
class TopicCloudPainter extends CustomPainter {
  TopicCloudPainter({
    required this.box,
    required this.chip,
    required this.strip,
    required this.color,
    super.repaint,
  });

  final GlobalKey box, chip, strip;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = box.currentContext?.findRenderObject();
    if (origin is! RenderBox) return;
    Rect? rectOf(GlobalKey key) {
      final r = key.currentContext?.findRenderObject();
      if (r is! RenderBox || !r.hasSize) return null;
      return MatrixUtils.transformRect(
        r.getTransformTo(origin),
        Offset.zero & r.size,
      );
    }

    final s = rectOf(strip);
    if (s == null) return;
    // The chip can scroll past the sides; the shape stops at the row's edges.
    canvas.clipRect(Rect.fromLTRB(0, -AppSpacing.l, size.width, size.height));
    canvas.drawPath(cloudPath(rectOf(chip), s), Paint()..color = color);
  }

  @override
  bool shouldRepaint(TopicCloudPainter old) => true;
}

/// The shape: the [strip] with rounded corners, the [chip] area rising from
/// its top edge, and concave curves where the two meet. Where the chip is too
/// close to a side for a curve, that top corner of the strip turns square.
Path cloudPath(Rect? chip, Rect strip) {
  const round = Radius.circular(AppRadius.field);
  var path = Path();
  if (chip == null) {
    return path..addRRect(RRect.fromRectAndRadius(strip, round));
  }
  final c = Rect.fromLTRB(
    chip.left - AppSpacing.xs,
    chip.top,
    chip.right + AppSpacing.xs,
    strip.top + AppRadius.field,
  );
  final leftRoom = c.left - strip.left, rightRoom = strip.right - c.right;
  final lf = leftRoom.clamp(0.0, AppSpacing.s);
  final rf = rightRoom.clamp(0.0, AppSpacing.s);
  final top = Radius.circular(chip.height / 2);
  void add(Path other) => path = Path.combine(PathOperation.union, path, other);
  path.addRRect(
    RRect.fromRectAndCorners(
      strip,
      topLeft: Radius.circular((leftRoom - lf).clamp(0.0, AppRadius.field)),
      topRight: Radius.circular((rightRoom - rf).clamp(0.0, AppRadius.field)),
      bottomLeft: round,
      bottomRight: round,
    ),
  );
  add(
    Path()..addRRect(RRect.fromRectAndCorners(c, topLeft: top, topRight: top)),
  );
  // A curve is a square at the meeting corner minus a circle of its size.
  void curve(double x, double size) {
    if (size <= 0) return;
    final square = Rect.fromLTWH(x, strip.top - size, size, size);
    final centre = Offset(x == c.right ? x + size : x, strip.top - size);
    add(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(square),
        Path()..addOval(Rect.fromCircle(center: centre, radius: size)),
      ),
    );
  }

  curve(c.left - lf, lf);
  curve(c.right, rf);
  return path;
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/explore/widgets/topic_cloud.dart';

void main() {
  const strip = Rect.fromLTRB(0, 48, 300, 112);

  test('one shape: chip and strip joined by curves, nothing beside it', () {
    final path = cloudPath(const Rect.fromLTRB(100, 0, 200, 48), strip);
    expect(path.contains(const Offset(150, 24)), isTrue, reason: 'chip');
    expect(path.contains(const Offset(150, 80)), isTrue, reason: 'strip');
    expect(path.contains(const Offset(150, 48)), isTrue, reason: 'no seam');
    // Just outside the chip at the strip's top edge: inside the curve.
    expect(path.contains(const Offset(95, 47)), isTrue);
    expect(path.contains(const Offset(205, 47)), isTrue);
    expect(path.contains(const Offset(60, 20)), isFalse, reason: 'above strip');
  });

  test('a chip at the edge squares that top corner of the strip', () {
    final path = cloudPath(const Rect.fromLTRB(4, 0, 100, 48), strip);
    expect(path.contains(const Offset(1, 49)), isTrue);
    final away = cloudPath(const Rect.fromLTRB(150, 0, 200, 48), strip);
    expect(away.contains(const Offset(1, 49)), isFalse, reason: 'rounded');
  });
}

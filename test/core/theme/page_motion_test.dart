import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/core/theme/page_motion.dart';

/// A Navigator with a home page and, when [open], one AppPage on top.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.open, required this.motion});
  final bool open;
  final PageMotion motion;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Navigator(
      pages: [
        const MaterialPage(child: Text('home')),
        if (open)
          AppPage<void>(
            key: const ValueKey('top'),
            motion: motion,
            origin: const Rect.fromLTWH(100, 100, 100, 60),
            child: const ColoredBox(color: Colors.white, child: Text('top')),
          ),
      ],
      onDidRemovePage: (_) {},
    ),
  );
}

void main() {
  double x(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dx;

  Future<void> run(
    WidgetTester tester,
    PageMotion motion, {
    required bool homeDrifts,
  }) async {
    await tester.pumpWidget(Stage(open: false, motion: motion));
    final home = x(tester, 'home');
    await tester.pumpWidget(Stage(open: true, motion: motion));
    await tester.pump(AppDurations.page ~/ 2);
    expect(x(tester, 'home') < home, homeDrifts);
    await tester.pumpAndSettle();
    expect(x(tester, 'top'), 0);

    // Leaving: the screen slides out to the right, whatever the way in.
    await tester.pumpWidget(Stage(open: false, motion: motion));
    await tester.pump(AppDurations.pageBack ~/ 2);
    expect(x(tester, 'top'), greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('top'), findsNothing);
    expect(x(tester, 'home'), home);
  }

  testWidgets('a side screen slides in while the screen below drifts back', (
    tester,
  ) async {
    await run(tester, PageMotion.side, homeDrifts: true);
  });

  testWidgets('a grow screen opens from its spot; the one below stays put', (
    tester,
  ) async {
    await tester.pumpWidget(const Stage(open: false, motion: PageMotion.grow));
    await tester.pumpWidget(const Stage(open: true, motion: PageMotion.grow));
    await tester.pump(const Duration(milliseconds: 1));
    final clip = tester.widget<ClipPath>(find.byType(ClipPath));
    final shape = (clip.clipper! as RRectClipper).shape.outerRect;
    expect(shape.left, closeTo(100, 2));
    expect(shape.width, closeTo(100, 4));
    expect(x(tester, 'top'), 0, reason: 'grows, does not slide');
    await run(tester, PageMotion.grow, homeDrifts: false);
  });
}

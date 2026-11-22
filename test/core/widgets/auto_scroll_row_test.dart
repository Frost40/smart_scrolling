import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/core/widgets/auto_scroll_row.dart';

Widget row({bool still = false, bool fromEnd = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(
      body: SizedBox(
        width: 300,
        child: AutoScrollRow(
          fromEnd: fromEnd,
          children: [
            for (var i = 0; i < 5; i++)
              SizedBox(key: Key('$i'), width: 150, height: 40),
          ],
        ),
      ),
    ),
  ),
);

double offset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .controller!
    .offset;

void main() {
  testWidgets('glides by itself, stops on touch, glides again when idle', (
    tester,
  ) async {
    await tester.pumpWidget(row());
    await tester.pump(AppDurations.carouselPause);
    await tester.pump(const Duration(seconds: 2));
    final moved = offset(tester);
    expect(moved, greaterThan(0));

    final touch = await tester.startGesture(const Offset(100, 20));
    await tester.pump(const Duration(seconds: 2));
    expect(offset(tester), moved, reason: 'a touch stops it');
    await touch.up();
    await tester.pump(const Duration(seconds: 1));
    expect(offset(tester), moved, reason: 'waits while idle');
    await tester.pump(AppDurations.carouselIdle);
    await tester.pump(const Duration(seconds: 2));
    expect(offset(tester), isNot(moved));
  });

  testWidgets('a row from the end starts there; reduce motion keeps still', (
    tester,
  ) async {
    await tester.pumpWidget(row(fromEnd: true, still: true));
    await tester.pump();
    final end = offset(tester);
    expect(end, greaterThan(0));
    await tester.pump(AppDurations.carouselPause);
    await tester.pump(const Duration(seconds: 3));
    expect(offset(tester), end);
  });
}

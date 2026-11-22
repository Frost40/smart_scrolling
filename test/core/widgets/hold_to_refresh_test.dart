import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/core/widgets/hold_to_refresh.dart';

void main() {
  late int refreshes;
  late ScrollController scroll;

  Future<void> mount(WidgetTester tester) async {
    refreshes = 0;
    scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: HoldToRefresh(
          onRefresh: () async => refreshes++,
          child: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 100, child: Text('Item $i')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('pull down and hold on the top card refreshes once', (
    tester,
  ) async {
    await mount(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Item 1')));
    await g.moveBy(const Offset(0, 40));
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(find.byKey(const Key('refresh-ring')), findsOneWidget);
    await tester.pump(AppDurations.refreshHold ~/ 2);
    expect(refreshes, 0);
    await tester.pump(AppDurations.refreshHold);
    expect(refreshes, 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets('letting go early does nothing', (tester) async {
    await mount(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Item 1')));
    await g.moveBy(const Offset(0, 100));
    await tester.pump(AppDurations.refreshHold ~/ 2);
    await g.up();
    await tester.pump(AppDurations.refreshHold * 2);
    expect(refreshes, 0);
    expect(find.byKey(const Key('refresh-ring')), findsNothing);
  });

  testWidgets('a hard pull refreshes at once, without holding', (tester) async {
    await mount(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Item 1')));
    await g.moveBy(const Offset(0, 60));
    await g.moveBy(const Offset(0, AppSizes.refreshHardPull));
    await tester.pump();
    expect(refreshes, 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets('a small tug, however long, does nothing', (tester) async {
    await mount(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Item 1')));
    await g.moveBy(const Offset(0, AppSizes.refreshPull / 2));
    await tester.pump(AppDurations.refreshHold * 3);
    await g.up();
    await tester.pumpAndSettle();
    expect(refreshes, 0);
  });

  testWidgets('away from the top card, pulling down only scrolls', (
    tester,
  ) async {
    await mount(tester);
    scroll.jumpTo(500);
    await tester.pump();
    final g = await tester.startGesture(tester.getCenter(find.text('Item 6')));
    await g.moveBy(const Offset(0, 100));
    await tester.pump(AppDurations.refreshHold * 2);
    await g.up();
    await tester.pumpAndSettle();
    expect(refreshes, 0);
  });
}

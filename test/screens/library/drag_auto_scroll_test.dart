import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/screens/library/widgets/drag_auto_scroll.dart';

void main() {
  testWidgets('a card held at the top edge scrolls the list up, one hand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DragAutoScroll(
            child: ListView(
              primary: true,
              children: [
                for (var i = 0; i < 40; i++)
                  Builder(
                    builder: (context) => LongPressDraggable<int>(
                      data: i,
                      onDragStarted: DragAutoScroll.of(context)?.start,
                      feedback: const SizedBox.square(dimension: 10),
                      child: SizedBox(height: 100, child: Text('card $i')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    final start = offset();
    final card = find.textContaining('card ').last;
    final finger = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout);
    await finger.moveTo(const Offset(200, 5));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // It kept scrolling after the held card left the screen.
    expect(offset(), lessThan(start - 500));
    await finger.up();
    await tester.pump();
    final stopped = offset();
    await tester.pump(const Duration(milliseconds: 200));
    expect(offset(), stopped, reason: 'lifting the finger stops it');
  });
}

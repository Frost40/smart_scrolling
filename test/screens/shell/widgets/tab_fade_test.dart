import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/screens/shell/widgets/tab_fade.dart';

Widget tabs(int index) => MaterialApp(
  home: TabFade(index: index, children: const [Text('one'), Text('two')]),
);

void main() {
  testWidgets('tabs cross-fade, then the old one goes offstage', (
    tester,
  ) async {
    await tester.pumpWidget(tabs(0));
    expect(find.text('two'), findsNothing);
    await tester.pumpWidget(tabs(1));
    await tester.pump(AppDurations.tabFade ~/ 2);
    expect(find.text('one'), findsOneWidget, reason: 'still fading out');
    expect(find.text('two'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two', skipOffstage: false), findsOneWidget);
  });
}

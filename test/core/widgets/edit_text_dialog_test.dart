import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/theme/dark_mode.dart';
import 'package:smart_scrolling/core/widgets/edit_text_dialog.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'editor validates names and keeps failed drafts (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(400, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = true;
        var saved = '';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? darkMode(highContrast: false)
                : lightMode(highContrast: false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditTextDialog(
                      title: 'Collection',
                      label: 'Name',
                      initialValue: '',
                      collectionName: true,
                      onSave: (text) async {
                        saved = text;
                        return fail ? 'Could not save' : null;
                      },
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Use 1–60 characters.'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), 'Samples');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Could not save'), findsOneWidget);
        expect(find.text('Samples'), findsOneWidget);
        fail = false;
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(saved, 'Samples');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

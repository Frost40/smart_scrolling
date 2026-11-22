import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/domain/models/practice_card.dart';
import 'package:smart_scrolling/domain/test_picker.dart';

// The same cases run on Supabase: supabase/tests/pick_test_cases.sql.
void main() {
  final sql = File('supabase/tests/pick_test_cases.sql').readAsStringSync();
  final cases = jsonDecode(
    RegExp(r'\$cases\$(.*?)\$cases\$', dotAll: true).firstMatch(sql)!.group(1)!,
  ) as List;

  test('the shared file has cases', () => expect(cases.length, 18));

  for (final c in cases.cast<Map<String, dynamic>>()) {
    test(c['name'], () {
      final tests = [
        for (final t in c['tests'] as List)
          PracticeCard(id: t['id'], type: t['type'], prompt: 'Prompt'),
      ];
      final last = <String, DateTime>{};
      for (final a in c['answers'] as List) {
        final at = DateTime.parse(a['at'] as String);
        if (last[a['test']]?.isBefore(at) ?? true) last[a['test']] = at;
      }
      expect(pickTest(tests, last, filter: c['filter'])?.id, c['pick']);
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/services/local_store.dart';

void main() {
  test('installation ids are random UUID v4', () {
    expect(
      uuid(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(uuid(), isNot(uuid()));
  });
}

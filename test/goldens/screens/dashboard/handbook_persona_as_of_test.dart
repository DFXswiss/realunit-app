import 'package:flutter_test/flutter_test.dart';

import 'handbook_persona_fixtures.dart';

void main() {
  test('handbook persona timestamps stay on 2026-08-28', () {
    expect(personaDcaHistory().last.time, DateTime(2026, 8, 28));
    expect(personaDcaHistory()[11].time, DateTime(2026, 8, 23));
  });
}

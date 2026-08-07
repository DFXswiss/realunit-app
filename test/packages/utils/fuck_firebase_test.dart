import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/utils/fuck_firebase.dart';

void main() {
  group('fuckFirebase', () {
    test('is a no-op off Android and never touches the filesystem', () async {
      // The host test runner reports Platform.isAndroid == false, so the whole
      // Android side effect is skipped. This pins the early-return contract:
      // fuckFirebase must do nothing (and must not throw) off Android.
      await expectLater(fuckFirebase(), completes);
    });
  });

  group('writeFirebaseTelemetryStub', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('fuck_firebase_test_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('writes the SQLITE_NOTADB sentinel into <root>/databases/', () async {
      await writeFirebaseTelemetryStub(root.path);

      final file = File('${root.path}/databases/com.google.android.datatransport.events');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'Fake');
    });

    test('creates the databases/ directory when it does not exist yet', () async {
      // A fresh install has no databases/ dir — recursive: true must materialise
      // the parent chain rather than throwing.
      expect(Directory('${root.path}/databases').existsSync(), isFalse);

      await writeFirebaseTelemetryStub(root.path);

      expect(Directory('${root.path}/databases').existsSync(), isTrue);
    });

    test('overwrites an existing sentinel file idempotently', () async {
      // fuckFirebase runs on every boot; a second write must not throw on an
      // already-present file and must leave the same sentinel content.
      await writeFirebaseTelemetryStub(root.path);
      await writeFirebaseTelemetryStub(root.path);

      final file = File('${root.path}/databases/com.google.android.datatransport.events');
      expect(file.readAsStringSync(), 'Fake');
    });
  });
}

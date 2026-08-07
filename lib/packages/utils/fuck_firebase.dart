import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:realunit_wallet/packages/io/documents_directory_port.dart';
import 'package:realunit_wallet/packages/io/path_provider_adapter.dart';

// https://github.com/juliansteenbakker/mobile_scanner/issues/553
// Basically we got a fucking telemetry because google
// This breaks firebase reporting, so we won't send any requests for using MLkit
// In future we will migrate somewhere else...
// Now instead of a request we get an error:
// android.database.sqlite.SQLiteDatabaseCorruptException: file is not a database (code 26 SQLITE_NOTADB)
// Which is fine, fuck google.
//
// The Android-only branch (the platform gate + the path_provider round-trip) is
// a 1:1 platform seam and carries the same `coverage:ignore` treatment as the
// DocumentsDirectoryPort adapter forwarders. The file write itself is factored
// into [writeFirebaseTelemetryStub] so it stays unit-tested on the host without
// an Android platform gate.
//
// @no-integration-test: the Android-only branch is a file-system side effect
// behind a platform gate + path_provider round-trip that cannot run in a host
// test; the covered seam is [writeFirebaseTelemetryStub].
Future<void> fuckFirebase({
  DocumentsDirectoryPort documentsDirectory = const PathProviderAdapter(),
}) async {
  if (!Platform.isAndroid) return;
  // coverage:ignore-start
  final dir = await documentsDirectory.getApplicationDocumentsDirectory();
  await writeFirebaseTelemetryStub(dir.parent.path);
  // coverage:ignore-end
}

/// Writes the sentinel "not a database" file under `<appDataRoot>/databases/`
/// that makes Android's MLKit / Firebase telemetry DB open fail with
/// `SQLITE_NOTADB` instead of phoning home (see the block comment on
/// [fuckFirebase]). Factored out of [fuckFirebase] so the file-writing logic is
/// unit-testable on the host without the Android platform gate.
@visibleForTesting
Future<void> writeFirebaseTelemetryStub(String appDataRoot) async {
  final file = File('$appDataRoot/databases/com.google.android.datatransport.events')
    ..createSync(recursive: true);
  await file.writeAsString('Fake');
}

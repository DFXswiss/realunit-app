// Verifies the tag → versionCode mapping in tool/generate_release_info.dart.
// We invoke the script as a subprocess (the same way Fastlane does) and read
// the canonical artefact back — stdout is not the authoritative output channel
// because `dart run` prepends "Running build hooks..." with no trailing
// newline. Each test writes to its own temp file via `--output=` so the
// working-tree copy at `lib/generated/release_info.dart` is never touched.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _script = 'tool/generate_release_info.dart';

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = File('$flutterRoot/bin/cache/dart-sdk/bin/dart');
    if (candidate.existsSync()) return candidate.path;
  }

  final currentExecutable = File(Platform.resolvedExecutable);
  final executableName = currentExecutable.uri.pathSegments.last;
  if (executableName == 'dart' || executableName == 'dart.exe') {
    return currentExecutable.path;
  }

  var dir = currentExecutable.parent;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/bin/cache/dart-sdk/bin/dart');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  return 'dart';
}

class _ReleaseInfo {
  _ReleaseInfo(this.tag, this.marketing, this.versionCode);
  final String tag;
  final String marketing;
  final int versionCode;
}

Future<_ReleaseInfo> _run({String? tag}) async {
  // Invoke the script directly (not via `dart run`) — the tool has no
  // package dependencies, so this skips the pub-resolve overhead and keeps
  // the suite fast. Each invocation gets its own temp output file so the
  // checked-in tree is never mutated.
  final tempDir = Directory.systemTemp.createTempSync('release_info_test_');
  final outputFile = File('${tempDir.path}/release_info.dart');
  try {
    final args = <String>[
      _script,
      if (tag != null) '--tag=$tag',
      '--output=${outputFile.path}',
    ];
    final result = await Process.run(_dartExecutable(), args);
    expect(
      result.exitCode,
      0,
      reason: 'dart run failed (exit=${result.exitCode}): ${result.stderr}',
    );
    final contents = await outputFile.readAsString();
    return _ReleaseInfo(
      RegExp(r"releaseTag = '([^']+)'").firstMatch(contents)!.group(1)!,
      RegExp(r"releaseMarketingVersion = '([^']+)'").firstMatch(contents)!.group(1)!,
      int.parse(RegExp(r'releaseVersionCode = (\d+)').firstMatch(contents)!.group(1)!),
    );
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

Future<ProcessResult> _runRaw(List<String> extraArgs) {
  // Error-path helper: we still need a temp `--output=` so a successful
  // invocation would not touch the working tree, but the tests here assert
  // a non-zero exit so the file is never written anyway.
  final tempDir = Directory.systemTemp.createTempSync('release_info_test_');
  final outputFile = File('${tempDir.path}/release_info.dart');
  return Process.run(_dartExecutable(), [
    _script,
    ...extraArgs,
    '--output=${outputFile.path}',
  ]).whenComplete(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
}

void main() {
  group('generate_release_info: stable tags', () {
    test('v1.0.0 → versionCode 10_000_999, stable suffix 999', () async {
      final info = await _run(tag: 'v1.0.0');
      expect(info.tag, '1.0.0');
      expect(info.marketing, '1.0.0');
      expect(info.versionCode, 10000999);
    });

    test('v1.0.15 → versionCode 10_015_999 (first patch after legacy beta train)',
        () async {
      final info = await _run(tag: 'v1.0.15');
      expect(info.tag, '1.0.15');
      expect(info.marketing, '1.0.15');
      expect(info.versionCode, 10015999);
    });

    test('v1.0.15 build code outranks the highest published beta (v1.0.0-beta.14)',
        () async {
      // The legacy beta train topped out at v1.0.0-beta.14 → 10_000_014.
      // v1.0.15 must come out strictly higher so Play Store / TestFlight
      // accept the upload without manual intervention.
      const legacyHighestBetaCode = 10000014;
      final firstStable = (await _run(tag: 'v1.0.15')).versionCode;
      expect(firstStable, greaterThan(legacyHighestBetaCode));
    });

    test('v2.5.7 → versionCode 20_507_999', () async {
      final info = await _run(tag: 'v2.5.7');
      expect(info.versionCode, 20507999);
    });

    test('successive patch bumps yield monotonically increasing version codes',
        () async {
      final p0 = (await _run(tag: 'v1.0.0')).versionCode;
      final p1 = (await _run(tag: 'v1.0.1')).versionCode;
      final m1 = (await _run(tag: 'v1.1.0')).versionCode;
      expect(p1, greaterThan(p0));
      expect(m1, greaterThan(p1));
    });
  });

  group('generate_release_info: dev sentinel', () {
    test('no --tag → dev sentinel, versionCode 0', () async {
      final info = await _run();
      expect(info.tag, 'dev');
      expect(info.marketing, '0.0.0');
      expect(info.versionCode, 0);
    });

    test('--tag=dev → same as no --tag', () async {
      final info = await _run(tag: 'dev');
      expect(info.tag, 'dev');
      expect(info.versionCode, 0);
    });
  });

  group('generate_release_info: error cases', () {
    test('malformed tag → non-zero exit', () async {
      final result = await _runRaw(['--tag=garbage']);
      expect(result.exitCode, isNot(0));
    });

    test('beta suffix is no longer accepted → non-zero exit', () async {
      final result = await _runRaw(['--tag=v1.0.0-beta.2']);
      expect(result.exitCode, isNot(0));
    });

    test('release-candidate suffix is not supported → non-zero exit', () async {
      final result = await _runRaw(['--tag=v1.0.0-rc.1']);
      expect(result.exitCode, isNot(0));
    });

    test('build-metadata suffix is not supported → non-zero exit', () async {
      final result = await _runRaw(['--tag=v1.0.0+build.1']);
      expect(result.exitCode, isNot(0));
    });

    test('major > 99 → non-zero exit', () async {
      final result = await _runRaw(['--tag=v100.0.0']);
      expect(result.exitCode, isNot(0));
    });

    test('patch > 99 → non-zero exit', () async {
      final result = await _runRaw(['--tag=v1.0.100']);
      expect(result.exitCode, isNot(0));
    });
  });

  group('generate_release_info: platform-prefixed tags', () {
    test('android/v1.0.15 strips the prefix and computes 10_015_999',
        () async {
      final info = await _run(tag: 'android/v1.0.15');
      expect(info.tag, '1.0.15');
      expect(info.versionCode, 10015999);
    });

    test('ios/v1.0.0 strips the prefix and computes 10_000_999', () async {
      final info = await _run(tag: 'ios/v1.0.0');
      expect(info.tag, '1.0.0');
      expect(info.versionCode, 10000999);
    });

    test('android/v1.0.0-beta.4 is rejected like every other beta suffix',
        () async {
      final result = await _runRaw(['--tag=android/v1.0.0-beta.4']);
      expect(result.exitCode, isNot(0));
    });
  });
}

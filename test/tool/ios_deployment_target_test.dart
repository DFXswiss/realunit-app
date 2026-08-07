// Guards the iOS deployment target against drift.
//
// The floor is declared in three places that Xcode, CocoaPods and the App
// Store validator each read separately — `ios/Podfile`, every build
// configuration in `ios/Runner.xcodeproj/project.pbxproj`, and
// `MinimumOSVersion` in `ios/Flutter/AppFrameworkInfo.plist`. Nothing keeps
// them in sync, and a mismatch only surfaces as an ITMS warning on an App
// Store Connect upload, long after the merge. This test reads the checked-in
// files and fails as soon as they disagree or drop below the floor Apple
// requires for uploads from Spring 2027 on (warned about as ITMS-90068).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lowest deployment target App Store Connect accepts for new uploads from
/// Spring 2027 on. Raising the app's floor further is fine; dropping below
/// this re-introduces the ITMS-90068 warning.
const appleFloorMajor = 15;
const appleFloorMinor = 0;

/// Build configurations declaring the target at project level: Debug, Release
/// and Profile. The per-target configurations (Runner, RunnerTests) inherit it
/// and deliberately carry no value of their own — so this is a count guard: a
/// new project-level configuration added without a deployment target trips it
/// instead of silently shipping an unset floor.
const projectBuildConfigurations = 3;

const podfilePath = 'ios/Podfile';
const pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const appFrameworkInfoPath = 'ios/Flutter/AppFrameworkInfo.plist';

String readRepoFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing');
  }
  return file.readAsStringSync();
}

String podfileTarget() {
  final match =
      RegExp("platform :ios, '([^']+)'").firstMatch(readRepoFile(podfilePath));
  if (match == null) {
    fail('no `platform :ios` line found in $podfilePath');
  }
  return match.group(1)!;
}

List<String> pbxprojTargets() {
  return RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);')
      .allMatches(readRepoFile(pbxprojPath))
      .map((match) => match.group(1)!.trim())
      .toList();
}

String appFrameworkInfoTarget() {
  final match =
      RegExp(r'<key>MinimumOSVersion</key>\s*<string>([^<]+)</string>')
          .firstMatch(readRepoFile(appFrameworkInfoPath));
  if (match == null) {
    fail('no MinimumOSVersion entry found in $appFrameworkInfoPath');
  }
  return match.group(1)!;
}

/// `15.0` becomes `1500`, so plain integer comparison orders the versions.
int comparable(String version, String source) {
  final match = RegExp(r'^(\d+)\.(\d+)$').firstMatch(version);
  if (match == null) {
    fail('unexpected version format "$version" in $source');
  }
  return int.parse(match.group(1)!) * 100 + int.parse(match.group(2)!);
}

void main() {
  test('every project-level build configuration declares the target', () {
    expect(
      pbxprojTargets(),
      hasLength(projectBuildConfigurations),
      reason: 'expected exactly $projectBuildConfigurations '
          'IPHONEOS_DEPLOYMENT_TARGET entries in $pbxprojPath (Debug, Release, '
          'Profile) — a build configuration was added or removed; give the new '
          'one a deployment target and update projectBuildConfigurations',
    );
  });

  test('Podfile, Xcode project and AppFrameworkInfo.plist agree', () {
    final podfile = podfileTarget();
    final pbxproj = pbxprojTargets();
    final appFrameworkInfo = appFrameworkInfoTarget();

    expect(
      <String>{podfile, ...pbxproj, appFrameworkInfo},
      hasLength(1),
      reason: 'iOS deployment target differs: $podfilePath declares '
          '$podfile, $pbxprojPath declares ${pbxproj.join(', ')}, '
          '$appFrameworkInfoPath declares $appFrameworkInfo — '
          'raise all of them together',
    );
  });

  test('the deployment target meets the App Store floor', () {
    final declared = <String, List<String>>{
      podfilePath: <String>[podfileTarget()],
      pbxprojPath: pbxprojTargets(),
      appFrameworkInfoPath: <String>[appFrameworkInfoTarget()],
    };
    final floor = appleFloorMajor * 100 + appleFloorMinor;

    declared.forEach((source, versions) {
      for (final version in versions) {
        expect(
          comparable(version, source),
          greaterThanOrEqualTo(floor),
          reason: '$source declares $version, below the App Store floor '
              '$appleFloorMajor.$appleFloorMinor (ITMS-90068)',
        );
      }
    });
  });
}

import 'package:flutter/material.dart';

/// Standard device profiles for layout / hit-test matrix tests.
///
/// Covers the supported phone range (smallest → largest) on iOS and Android
/// with realistic view padding (notch / Dynamic Island / home indicator /
/// status + nav bars). Logical sizes match common Flutter device metrics.
@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.id,
    required this.label,
    required this.size,
    required this.viewPadding,
    required this.platform,
  });

  final String id;
  final String label;
  final Size size;

  /// System insets (status bar / island / home indicator / nav bar).
  final EdgeInsets viewPadding;
  final TargetPlatform platform;

  MediaQueryData get mediaQuery => MediaQueryData(
    size: size,
    padding: viewPadding,
    viewPadding: viewPadding,
    devicePixelRatio: 3,
  );
}

/// Accessibility text scales from system "small" to extreme large accessibility.
///
/// 1.0 = default; 2.0 = common "larger accessibility"; 3.0 = stress / max
/// accessibility on many OEMs. 0.85 covers "smaller" system text.
const kTextScaleFactors = <double>[0.85, 1.0, 1.3, 2.0, 3.0];

/// Default scales used in CI matrix runs (full set). Prefer this over ad-hoc lists.
const kMatrixTextScales = kTextScaleFactors;

/// Smallest → largest phones we claim to support.
const kIosDeviceProfiles = <DeviceProfile>[
  DeviceProfile(
    id: 'iphone_se_3',
    label: 'iPhone SE (3rd gen)',
    size: Size(375, 667),
    viewPadding: EdgeInsets.only(top: 20, bottom: 0),
    platform: TargetPlatform.iOS,
  ),
  DeviceProfile(
    id: 'iphone_13_mini',
    label: 'iPhone 13 mini',
    size: Size(375, 812),
    viewPadding: EdgeInsets.only(top: 50, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
  DeviceProfile(
    id: 'iphone_15',
    label: 'iPhone 15',
    size: Size(393, 852),
    viewPadding: EdgeInsets.only(top: 59, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
  DeviceProfile(
    id: 'iphone_16_pro_max',
    label: 'iPhone 16 Pro Max',
    size: Size(440, 956),
    viewPadding: EdgeInsets.only(top: 59, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
];

const kAndroidDeviceProfiles = <DeviceProfile>[
  DeviceProfile(
    id: 'android_small',
    label: 'Android compact (≈ Pixel 4a)',
    size: Size(360, 760),
    viewPadding: EdgeInsets.only(top: 24, bottom: 48),
    platform: TargetPlatform.android,
  ),
  DeviceProfile(
    id: 'android_medium',
    label: 'Android medium (≈ Pixel 7)',
    size: Size(412, 915),
    viewPadding: EdgeInsets.only(top: 24, bottom: 48),
    platform: TargetPlatform.android,
  ),
  DeviceProfile(
    id: 'android_large',
    label: 'Android large (≈ Pixel 8 Pro)',
    size: Size(448, 998),
    viewPadding: EdgeInsets.only(top: 24, bottom: 48),
    platform: TargetPlatform.android,
  ),
];

/// Full matrix: every standard phone profile we support.
const kAllDeviceProfiles = <DeviceProfile>[
  ...kIosDeviceProfiles,
  ...kAndroidDeviceProfiles,
];

/// One cell of the responsive matrix (device × text scale).
@immutable
class MatrixCell {
  const MatrixCell(this.device, this.textScale);

  final DeviceProfile device;
  final double textScale;

  String get id => '${device.id}@${textScale}x';

  String get label => '${device.label}, textScale=$textScale';

  MediaQueryData get mediaQuery => device.mediaQuery.copyWith(
    textScaler: TextScaler.linear(textScale),
  );
}

/// Cartesian product of [devices] × [textScales].
List<MatrixCell> buildResponsiveMatrix({
  List<DeviceProfile> devices = kAllDeviceProfiles,
  List<double> textScales = kMatrixTextScales,
}) => [
  for (final device in devices)
    for (final scale in textScales) MatrixCell(device, scale),
];

/// CI-default full matrix (7 devices × 5 scales = 35 cells).
final kFullResponsiveMatrix = buildResponsiveMatrix();

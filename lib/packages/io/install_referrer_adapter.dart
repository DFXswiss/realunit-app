import 'dart:io';

import 'package:flutter/services.dart';
import 'package:realunit_wallet/packages/io/install_referrer_port.dart';

/// Production [InstallReferrerPort]. Android forwards to the native Play
/// Install Referrer client; every other platform is a no-op.
///
/// The method-channel round-trip is the platform boundary, so — like
/// [BackupExclusionAdapter] — this body cannot be exercised under
/// `flutter test` without re-introducing the native plugin. Callers are
/// covered against an in-memory fake instead.
class InstallReferrerAdapter implements InstallReferrerPort {
  const InstallReferrerAdapter();

  static const MethodChannel _channel = MethodChannel(
    'swiss.realunit.app/install_referrer',
  );

  // coverage:ignore-start
  // @no-integration-test: thin platform-channel forwarder; Play Install
  //   Referrer is only observable on a real Play-installed Android build.
  @override
  Future<String?> readInstallReferrer() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('readInstallReferrer');
  }

  // coverage:ignore-end
}

import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random per-install id plus app/build/platform, sent as headers on every
/// request (snake-classic's InstallIdentity). Contains no PII.
class InstallIdentity {
  InstallIdentity._(this.installId, this.appVersion, this.appBuild, this.platform);

  static const _key = 'install_id';

  final String installId;
  final String appVersion;
  final String appBuild;
  final String platform;

  static Future<InstallIdentity> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    final info = await PackageInfo.fromPlatform();
    final platform = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : Platform.operatingSystem;
    return InstallIdentity._(id, info.version, info.buildNumber, platform);
  }

  Map<String, String> get headers => {
        'X-Install-Id': installId,
        'X-App-Version': appVersion,
        'X-App-Build': appBuild,
        'X-Platform': platform,
      };
}

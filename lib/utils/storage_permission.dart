import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of asking for access to shared storage.
enum StorageAccess { granted, denied, permanentlyDenied, restricted }

/// Android storage permission (based on the flutibre solution).
///
/// * Android 11+ (API 30+): a user-picked library folder is read/written with
///   plain dart:io File APIs, which needs "All files access"
///   (MANAGE_EXTERNAL_STORAGE). The request opens the system settings screen.
/// * Android 10 and below: the classic READ/WRITE_EXTERNAL_STORAGE runtime
///   permission ([Permission.storage]).
/// * Other platforms: always granted.
class StoragePermission {
  const StoragePermission._();

  static int? _sdkInt;

  static Future<Permission> _permission() async {
    _sdkInt ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _sdkInt! >= 30
        ? Permission.manageExternalStorage
        : Permission.storage;
  }

  static Future<bool> get isGranted async {
    if (!Platform.isAndroid) return true;
    return (await _permission()).isGranted;
  }

  /// Requests access if needed and reports what happened.
  static Future<StorageAccess> ensure() async {
    if (!Platform.isAndroid) return StorageAccess.granted;

    final permission = await _permission();
    var status = await permission.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      status = await permission.request();
    }

    if (status.isGranted || status.isLimited) return StorageAccess.granted;
    if (status.isRestricted) return StorageAccess.restricted;
    if (status.isPermanentlyDenied) return StorageAccess.permanentlyDenied;
    return StorageAccess.denied;
  }

  /// Opens this app's system settings page so the user can grant it manually.
  static Future<bool> openSettings() => openAppSettings();
}

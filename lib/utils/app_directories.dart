import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Platform-specific application data directory utilities.
///
/// On Windows: Uses AppData/Local for all application data
/// On other platforms: Uses Documents directory (existing behavior)
class AppDirectories {
  AppDirectories._();

  /// Gets the root directory for application data storage.
  ///
  /// - Windows: AppData\Local\Kelivo
  /// - Other platforms: Documents directory
  static Future<Directory> getAppDataDirectory() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final appSupport = await getApplicationSupportDirectory();
      return appSupport;
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  /// Gets the directory for uploaded files.
  static Future<Directory> getUploadDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/upload');
  }

  /// Gets the directory for image files.
  static Future<Directory> getImagesDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/images');
  }

  /// Gets the directory for avatar files.
  static Future<Directory> getAvatarsDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/avatars');
  }

  /// Gets the directory for cache files.
  static Future<Directory> getCacheDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/cache');
  }

  /// Gets the directory for avatar cache files.
  static Future<Directory> getAvatarCacheDirectory() async {
    final root = await getAppDataDirectory();
    return Directory('${root.path}/cache/avatars');
  }
}

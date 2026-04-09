import 'package:flutter/foundation.dart';
import 'dbas_filesystem_platform_util_io.dart'
  if (dart.library.js_interop) 'dbas_filesystem_platform_util_web.dart';

class DbasFileSystemPlatformUtil {
  static bool isTest() {
    if (kIsWeb) return false;
    return isTestEnvironment();
  }
}

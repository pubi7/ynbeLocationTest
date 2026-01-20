import 'package:flutter/foundation.dart' show kIsWeb;

import 'platform_info_stub.dart'
    if (dart.library.io) 'platform_info_io.dart' as impl;

class PlatformInfo {
  static bool get isWeb => kIsWeb;
  static bool get isAndroid => impl.isAndroid;
  static bool get isIOS => impl.isIOS;
}


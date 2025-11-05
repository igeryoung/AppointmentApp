import 'package:flutter/foundation.dart';

/// Utility class for platform detection
class PlatformUtils {
  PlatformUtils._();

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// Check if running on mobile platform (iOS or Android)
  static bool get isMobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  /// Check if running on desktop platform
  static bool get isDesktop => !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows);

  /// Get platform name as string
  static String get platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Get display name for device
  static String get deviceDisplayName {
    if (kIsWeb) return 'Web Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS Device';
      case TargetPlatform.android:
        return 'Android Device';
      case TargetPlatform.macOS:
        return 'macOS Device';
      case TargetPlatform.windows:
        return 'Windows Device';
      case TargetPlatform.linux:
        return 'Linux Device';
      default:
        return 'Unknown Device';
    }
  }
}

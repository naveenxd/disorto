import 'dart:io';

import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';

/// Thin wrapper around [WallpaperManagerPlus] that applies a locally-stored
/// image as the device wallpaper.
///
/// ### Location constants (re-exported for convenience)
/// ```dart
/// WallpaperService.homeScreen   // home screen only
/// WallpaperService.lockScreen   // lock screen only
/// WallpaperService.bothScreens  // both home + lock
/// ```
///
/// ### Usage
/// ```dart
/// await WallpaperService.setWallpaper(
///   imagePath: '/data/user/0/.../distorto_export_123.png',
///   location:  WallpaperService.homeScreen,
/// );
/// ```
class WallpaperService {
  WallpaperService._(); // non-instantiable

  // ── Location constants (forwarded from WallpaperManagerPlus) ─────────────

  /// Apply to the home screen only.
  static const int homeScreen   = WallpaperManagerPlus.homeScreen;

  /// Apply to the lock screen only.
  static const int lockScreen   = WallpaperManagerPlus.lockScreen;

  /// Apply to both home and lock screens.
  static const int bothScreens  = WallpaperManagerPlus.bothScreens;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Sets the wallpaper from a local file at [imagePath].
  ///
  /// [location] must be one of [homeScreen], [lockScreen], or [bothScreens].
  ///
  /// Throws a [WallpaperException] if the platform call fails.
  static Future<void> setWallpaper({
    required String imagePath,
    required int location,
  }) async {
    assert(
      location == homeScreen ||
          location == lockScreen ||
          location == bothScreens,
      'location must be one of WallpaperService.homeScreen / lockScreen / bothScreens',
    );

    final file = File(imagePath);

    if (!file.existsSync()) {
      throw WallpaperException(
        'Image file not found at path: $imagePath',
      );
    }

    try {
      await WallpaperManagerPlus().setWallpaper(file, location);
    } catch (e, st) {
      throw WallpaperException(
        'Failed to set wallpaper: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WallpaperException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when [WallpaperService.setWallpaper] fails.
class WallpaperException implements Exception {
  const WallpaperException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'WallpaperException: $message';
}

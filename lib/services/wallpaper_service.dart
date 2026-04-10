import 'dart:io';
import 'package:flutter/services.dart';

/// Service that delegates wallpaper selection to the system OS.
class WallpaperService {
  WallpaperService._();

  static const _channel = MethodChannel('in.devh.distorto/wallpaper');

  /// Opens the system's "Set as Wallpaper" picker for the image at [imagePath].
  ///
  /// This allows the system to handle cropping, scrolling options, and
  /// target selection (Home/Lock).
  static Future<void> setWallpaper({required String imagePath}) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw WallpaperException('Image file not found at path: $imagePath');
    }

    try {
      await _channel.invokeMethod('openWallpaperPicker', {'path': imagePath});
    } catch (e, st) {
      throw WallpaperException(
        'Failed to open system wallpaper picker: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

class WallpaperException implements Exception {
  const WallpaperException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'WallpaperException: $message';
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';

/// Saves a processed image to the device gallery using the [gal] package.
///
/// ### Usage — from a file path
/// ```dart
/// await ImageExportService.saveFileToGallery(imagePath);
/// ```
///
/// ### Usage — from a [ui.Image] in memory
/// ```dart
/// await ImageExportService.saveUiImageToGallery(uiImage);
/// ```
class ImageExportService {
  ImageExportService._(); // non-instantiable

  // ── Save from file path ────────────────────────────────────────────────────

  /// Saves the image at [imagePath] to the system gallery.
  ///
  /// The file must already exist on disk (e.g. a previously exported PNG).
  ///
  /// Throws [ExportException] on failure.
  static Future<void> saveFileToGallery(String imagePath) async {
    final file = File(imagePath);

    if (!file.existsSync()) {
      throw ExportException('Image file not found at path: $imagePath');
    }

    // Check / request gallery access.  Gal handles the permission dialog
    // internally on first call; we explicitly check so we can show a friendly
    // error if the user permanently denies.
    final hasAccess = await Gal.hasAccess(toAlbum: false);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: false);
      if (!granted) {
        throw ExportException(
          'Gallery access denied. Grant permission in Settings to save images.',
        );
      }
    }

    try {
      await Gal.putImage(imagePath);
    } catch (e, st) {
      throw ExportException(
        'Failed to save image to gallery: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ── Save from ui.Image ────────────────────────────────────────────────────

  /// Encodes [image] as PNG and saves it directly to the system gallery
  /// without writing an intermediate file to disk.
  ///
  /// Uses [Gal.putImageBytes] which accepts raw PNG/JPEG bytes.
  ///
  /// Throws [ExportException] on failure.
  static Future<void> saveUiImageToGallery(
    ui.Image image, {
    String name = 'distorto',
  }) async {
    // Check / request gallery access.
    final hasAccess = await Gal.hasAccess(toAlbum: false);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: false);
      if (!granted) {
        throw ExportException(
          'Gallery access denied. Grant permission in Settings to save images.',
        );
      }
    }

    // Encode to PNG bytes.
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw ExportException('Failed to encode image to PNG bytes.');
    }

    final pngBytes = byteData.buffer.asUint8List();

    try {
      await Gal.putImageBytes(pngBytes, name: name);
    } catch (e, st) {
      throw ExportException(
        'Failed to save image bytes to gallery: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExportException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when [ImageExportService] fails to save an image.
class ExportException implements Exception {
  const ExportException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'ExportException: $message';
}

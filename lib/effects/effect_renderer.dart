import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// ════════════════════════════════════════════════════════════════════════════
// DistortionEffect enum
// ════════════════════════════════════════════════════════════════════════════

/// Enumerates every distortion effect the app can apply.
enum DistortionEffect {
  original,
  narrowReed,
  wideReed,
  lumina,
  grid,
  liquid,
  ripple,
}

/// Convenience extension providing display labels and asset paths.
extension DistortionEffectX on DistortionEffect {
  String get label => switch (this) {
        DistortionEffect.original   => 'Original',
        DistortionEffect.narrowReed => 'Narrow Reed',
        DistortionEffect.wideReed   => 'Wide Reed',
        DistortionEffect.lumina     => 'Lumina',
        DistortionEffect.grid       => 'Grid',
        DistortionEffect.liquid     => 'Liquid',
        DistortionEffect.ripple     => 'Ripple',
      };

  /// Shader asset path registered in pubspec.yaml, or null for [original].
  String? get shaderAsset => switch (this) {
        DistortionEffect.original   => null,
        DistortionEffect.narrowReed => 'effects/shaders/narrow_reed.glsl',
        DistortionEffect.wideReed   => 'effects/shaders/wide_reed.glsl',
        DistortionEffect.lumina     => 'effects/shaders/lumina.glsl',
        DistortionEffect.grid       => 'effects/shaders/grid.glsl',
        DistortionEffect.liquid     => 'effects/shaders/liquid.glsl',
        DistortionEffect.ripple     => 'effects/shaders/ripple.glsl',
      };
}

// ════════════════════════════════════════════════════════════════════════════
// _BlurParams — isolate-safe payload for compute()
// ════════════════════════════════════════════════════════════════════════════

/// Plain-data transfer object passed into the blur isolate.
/// Everything must be sendable across isolate boundaries (no ui.Image).
class _BlurParams {
  const _BlurParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.radius,
  });

  final Uint8List bytes;  // Raw RGBA bytes of the image to blur
  final int width;
  final int height;
  final int scaledWidth;
  final int scaledHeight;
  final int radius;       // Gaussian blur radius in pixels
}

/// Top-level function executed by [compute] in a background isolate.
/// Returns the blurred image as raw RGBA [Uint8List].
Uint8List _blurIsolate(_BlurParams p) {
  // Decode raw RGBA bytes into an img.Image.
  img.Image working = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  // Downsample before blurring for a softer glass-like result and better speed.
  if (p.scaledWidth != p.width || p.scaledHeight != p.height) {
    working = img.copyResize(
      working,
      width: p.scaledWidth,
      height: p.scaledHeight,
      interpolation: img.Interpolation.average,
    );
  }

  working = img.gaussianBlur(working, radius: p.radius);

  // Re-expand to the original resolution after blur.
  if (working.width != p.width || working.height != p.height) {
    working = img.copyResize(
      working,
      width: p.width,
      height: p.height,
      interpolation: img.Interpolation.cubic,
    );
  }

  // Return as raw RGBA bytes.
  return working.toUint8List();
}

// ════════════════════════════════════════════════════════════════════════════
// EffectRenderer
// ════════════════════════════════════════════════════════════════════════════

/// Applies distortion shaders and optional Gaussian blur to a [ui.Image].
///
/// ### Usage
/// ```dart
/// final renderer = EffectRenderer();
/// await renderer.init();                         // pre-warm shader cache
///
/// final result = await renderer.render(
///   source:    myUiImage,
///   effect:    DistortionEffect.narrowReed,
///   intensity: 0.8,
///   blurLevel: 2,        // 0 = no blur, 4 = heavy blur (radius 16)
/// );
/// ```
///
/// ### Pipeline
/// ```
/// source ui.Image
///     ↓  [shader]   → rendered ui.Image    (on main thread via Canvas)
///     ↓  [convert]  → img.Image / Uint8List
///     ↓  [blur]     → blurred Uint8List     (on background isolate)
///     ↓  [convert]  → ui.Image
///     ↓  returned
/// ```
///
/// Both the effect and blur are independently controlled:
/// - [DistortionEffect.original] with `blurLevel > 0` = pure blur, no distortion.
/// - Any effect with `blurLevel == 0` = distortion only, no blur.
class EffectRenderer {
  // Cache of pre-loaded FragmentPrograms keyed by shader asset path.
  final Map<String, ui.FragmentProgram> _programCache = {};

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Pre-loads all shader programs so the first render call is lag-free.
  /// Call once at app start (e.g. in a FutureBuilder or initState).
  Future<void> init() async {
    for (final effect in DistortionEffect.values) {
      final asset = effect.shaderAsset;
      if (asset != null && !_programCache.containsKey(asset)) {
        _programCache[asset] = await ui.FragmentProgram.fromAsset(asset);
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Renders [source] with [effect] at the given [intensity], then applies
  /// Gaussian blur at [blurLevel] steps (0 = none, 4 = heaviest).
  ///
  /// Always processes at the full resolution of [source].
  /// Blur is applied to the base image first, then the selected shader distorts
  /// that blurred image. This matches the app's reference behavior.
  ///
  /// Returns a new [ui.Image] that the caller owns and must [dispose].
  Future<ui.Image> render({
    required ui.Image source,
    required DistortionEffect effect,
    double intensity = 1.0,
    int blurLevel = 0,
  }) async {
    assert(intensity >= 0.0 && intensity <= 1.0,
        'intensity must be in [0.0, 1.0]');
    assert(blurLevel >= 0 && blurLevel <= 4,
        'blurLevel must be in [0, 4]');

    ui.Image working = source;

    // Step 1: Blur the base image first so the effect refracts the blurred
    // content instead of blurring the already-distorted output.
    if (blurLevel > 0) {
      working = await _applyBlur(image: source, blurLevel: blurLevel);
    }

    // Step 2: Apply shader distortion (or pass through for original).
    final distorted = await _applyShader(
      source: working,
      effect: effect,
      intensity: intensity,
    );

    if (blurLevel > 0) {
      working.dispose();
    }

    return distorted;
  }

  // ── Shader rendering ──────────────────────────────────────────────────────

  /// Renders [source] through the GLSL shader for [effect].
  /// For [DistortionEffect.original], returns a copy of [source] (no shader).
  Future<ui.Image> _applyShader({
    required ui.Image source,
    required DistortionEffect effect,
    required double intensity,
  }) async {
    final double w = source.width.toDouble();
    final double h = source.height.toDouble();

    // Record drawing commands into a Picture.
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    if (effect == DistortionEffect.original) {
      // Draw the source image unchanged.
      canvas.drawImage(source, Offset.zero, Paint());
    } else {
      final asset = effect.shaderAsset!;

      // Load (or reuse) the FragmentProgram.
      final program = _programCache[asset] ??
          await _loadAndCache(asset);

      final shader = program.fragmentShader();

      // Uniform binding order (context spec §"Shader uniform layout"):
      //   index 0 → uWidth     (float)
      //   index 1 → uHeight    (float)
      //   index 2 → uIntensity (float)
      //   sampler 0 → uTexture
      shader.setFloat(0, w);
      shader.setFloat(1, h);
      shader.setFloat(2, intensity);
      shader.setImageSampler(0, source);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..shader = shader,
      );
    }

    // Rasterise the picture into a ui.Image at the original resolution.
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(w.toInt(), h.toInt());
    picture.dispose();
    return rendered;
  }

  Future<ui.FragmentProgram> _loadAndCache(String asset) async {
    final program = await ui.FragmentProgram.fromAsset(asset);
    _programCache[asset] = program;
    return program;
  }

  // ── Gaussian blur (background isolate) ───────────────────────────────────

  /// Applies Gaussian blur to [image] using the `image` package on a
  /// background isolate via [compute], keeping the main thread unblocked.
  ///
  /// The blur is downsampled before processing to avoid the harsh, smeared
  /// look produced by full-resolution post-effect blurring.
  Future<ui.Image> _applyBlur({
    required ui.Image image,
    required int blurLevel,
  }) async {
    // Convert ui.Image → raw RGBA bytes (on main thread — must be here).
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _copyImage(image);
    }

    final scale = switch (blurLevel) {
      1 => 0.80,
      2 => 0.62,
      3 => 0.48,
      _ => 0.36,
    };
    final radius = switch (blurLevel) {
      1 => 5,
      2 => 8,
      3 => 12,
      _ => 16,
    };
    final scaledWidth = (image.width * scale).round().clamp(1, image.width);
    final scaledHeight =
        (image.height * scale).round().clamp(1, image.height);

    final params = _BlurParams(
      bytes: byteData.buffer.asUint8List(),
      width: image.width,
      height: image.height,
      scaledWidth: scaledWidth,
      scaledHeight: scaledHeight,
      radius: radius,
    );

    // Run the blur on a background isolate — never blocks the UI thread.
    final blurredBytes = await compute(_blurIsolate, params);

    // Convert blurred RGBA bytes back to ui.Image.
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      blurredBytes,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      (result) => completer.complete(result),
    );
    return completer.future;
  }

  Future<ui.Image> _copyImage(ui.Image source) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    );
    canvas.drawImage(source, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final copy = await picture.toImage(source.width, source.height);
    picture.dispose();
    return copy;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  /// Clears the shader program cache. Call when the renderer is no longer
  /// needed (e.g. in widget dispose).
  void dispose() {
    _programCache.clear();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RenderedResult — convenience wrapper returned from render()
// ════════════════════════════════════════════════════════════════════════════

/// Wraps the output of [EffectRenderer.render] together with the parameters
/// used to produce it, so callers can skip re-rendering when nothing changed.
class RenderedResult {
  RenderedResult({
    required this.image,
    required this.effect,
    required this.intensity,
    required this.blurLevel,
  });

  final ui.Image image;
  final DistortionEffect effect;
  final double intensity;
  final int blurLevel;

  /// True if re-rendering with [newEffect], [newIntensity], [newBlurLevel]
  /// would produce the same result as this one.
  bool isCurrent({
    required DistortionEffect newEffect,
    required double newIntensity,
    required int newBlurLevel,
  }) =>
      newEffect == effect &&
      newIntensity == intensity &&
      newBlurLevel == blurLevel;

  void dispose() => image.dispose();
}

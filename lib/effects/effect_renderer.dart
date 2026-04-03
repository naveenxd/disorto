import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum DistortionEffect {
  original,
  narrowReed,
  wideReed,
  lumina,
  grid,
  liquid,
  ripple,
}

extension DistortionEffectX on DistortionEffect {
  String get label => switch (this) {
    DistortionEffect.original => 'Original',
    DistortionEffect.narrowReed => 'Narrow Reed',
    DistortionEffect.wideReed => 'Wide Reed',
    DistortionEffect.lumina => 'Lumina',
    DistortionEffect.grid => 'Grid',
    DistortionEffect.liquid => 'Liquid',
    DistortionEffect.ripple => 'Ripple',
  };
}

class _BlurParams {
  const _BlurParams({
    required this.bytes,
    required this.width,
    required this.height,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.radius,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int scaledWidth;
  final int scaledHeight;
  final int radius;
}

class _BlendParams {
  const _BlendParams({
    required this.lowBytes,
    required this.highBytes,
    required this.mix,
  });

  final Uint8List lowBytes;
  final Uint8List highBytes;
  final double mix;
}

class BlurPreset {
  const BlurPreset({required this.scale, required this.radius});

  final double scale;
  final int radius;
}

const List<BlurPreset> kBlurPresets = [
  BlurPreset(scale: 1.0, radius: 0),
  BlurPreset(scale: 0.92, radius: 6),
  BlurPreset(scale: 0.75, radius: 16),
  BlurPreset(scale: 0.58, radius: 32),
  BlurPreset(scale: 0.42, radius: 52),
];

Uint8List _blurIsolate(_BlurParams p) {
  img.Image working = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  if (p.scaledWidth != p.width || p.scaledHeight != p.height) {
    working = img.copyResize(
      working,
      width: p.scaledWidth,
      height: p.scaledHeight,
      interpolation: img.Interpolation.average,
    );
  }

  if (p.radius > 0) {
    working = img.gaussianBlur(working, radius: p.radius);
  }

  if (working.width != p.width || working.height != p.height) {
    working = img.copyResize(
      working,
      width: p.width,
      height: p.height,
      interpolation: img.Interpolation.cubic,
    );
  }

  return working.toUint8List();
}

Uint8List _blendIsolate(_BlendParams p) {
  final output = Uint8List(p.lowBytes.length);
  final mix = p.mix.clamp(0.0, 1.0);
  final inv = 1.0 - mix;
  for (var i = 0; i < output.length; i++) {
    output[i] = (p.lowBytes[i] * inv + p.highBytes[i] * mix).round().clamp(
      0,
      255,
    );
  }
  return output;
}

int _noopIsolate(int value) => value;

class EffectRenderer {
  final Map<DistortionEffect, Future<ui.FragmentProgram>> _shaderPrograms = {};

  Future<void> init() async {
    await Future.wait(
      DistortionEffect.values
          .where((effect) => effect != DistortionEffect.original)
          .map(_shaderProgramFor),
    );
  }

  Future<void> prewarmIsolate() async {
    await compute(_noopIsolate, 1);
  }

  Future<void> prewarmEffectMaps(Iterable<DistortionEffect> effects) async {
    await Future.wait(
      effects
          .where((effect) => effect != DistortionEffect.original)
          .map(_shaderProgramFor),
    );
  }

  Future<ui.Image> render({
    required ui.Image source,
    required ui.Image blurredBase,
    ui.Image? blurredBaseSecondary,
    double blurMix = 0.0,
    double originalDetailWeight = 0.08,
    required DistortionEffect effect,
    double intensity = 1.0,
  }) async {
    assert(
      intensity >= 0.0 && intensity <= 1.0,
      'intensity must be in [0.0, 1.0]',
    );

    try {
      final blend = await _blendImages(
        low: blurredBase,
        high: blurredBaseSecondary ?? blurredBase,
        mix: blurMix,
      );

      if (effect == DistortionEffect.original) {
        return blend;
      }

      try {
        return await _renderWithShader(
          source: source,
          blurImage: blend,
          effect: effect,
          intensity: intensity,
          originalDetailWeight: originalDetailWeight,
        );
      } finally {
        blend.dispose();
      }
    } catch (_) {
      return _copyImage(blurredBase);
    }
  }

  Future<ui.Image> prepareBlurredBase({
    required ui.Image source,
    required int presetLevel,
  }) async {
    final level = presetLevel.clamp(0, kBlurPresets.length - 1);
    final preset = kBlurPresets[level];
    if (preset.radius <= 0 && preset.scale >= 1.0) {
      return _copyImage(source);
    }
    return _applyBlur(
      image: source,
      scale: preset.scale,
      radius: preset.radius,
    );
  }

  Future<ui.Image> _applyBlur({
    required ui.Image image,
    required double scale,
    required int radius,
  }) async {
    final byteData = await _rgbaByteData(image);
    if (byteData == null) {
      return _copyImage(image);
    }

    final normalizedScale = scale.clamp(0.1, 1.0);
    final bytes = await compute(
      _blurIsolate,
      _BlurParams(
        bytes: byteData.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        scaledWidth: (image.width * normalizedScale).round().clamp(
          1,
          image.width,
        ),
        scaledHeight: (image.height * normalizedScale).round().clamp(
          1,
          image.height,
        ),
        radius: radius.clamp(0, 128),
      ),
    );

    return _decodeRgba(bytes, image.width, image.height);
  }

  Future<ui.Image> _blendImages({
    required ui.Image low,
    required ui.Image high,
    required double mix,
  }) async {
    final normalizedMix = mix.clamp(0.0, 1.0);
    if (identical(low, high) || normalizedMix <= 0.0001) {
      return _copyImage(low);
    }
    if (normalizedMix >= 0.9999) {
      return _copyImage(high);
    }

    final lowData = await _rgbaByteData(low);
    final highData = await _rgbaByteData(high);
    if (lowData == null || highData == null) {
      return _rasterize(
        width: low.width,
        height: low.height,
        painter: (canvas, size) {
          canvas.drawImage(low, ui.Offset.zero, ui.Paint());
          canvas.drawImage(
            high,
            ui.Offset.zero,
            ui.Paint()
              ..color = ui.Color.fromRGBO(255, 255, 255, normalizedMix),
          );
        },
      );
    }

    final blended = await compute(
      _blendIsolate,
      _BlendParams(
        lowBytes: lowData.buffer.asUint8List(),
        highBytes: highData.buffer.asUint8List(),
        mix: normalizedMix,
      ),
    );
    return _decodeRgba(blended, low.width, low.height);
  }

  Future<ui.Image> _renderWithShader({
    required ui.Image source,
    required ui.Image blurImage,
    required DistortionEffect effect,
    required double intensity,
    required double originalDetailWeight,
  }) async {
    final program = await _shaderProgramFor(effect);
    final shader = program.fragmentShader();
    shader
      ..setFloat(0, source.width.toDouble())
      ..setFloat(1, source.height.toDouble())
      ..setFloat(2, intensity.clamp(0.0, 1.0))
      ..setFloat(3, 0.0)
      ..setFloat(4, originalDetailWeight.clamp(0.0, 1.0))
      ..setImageSampler(0, source)
      ..setImageSampler(1, blurImage);

    try {
      return _rasterize(
        width: source.width,
        height: source.height,
        painter: (canvas, size) {
          canvas.drawRect(
            ui.Rect.fromLTWH(0, 0, size.width, size.height),
            ui.Paint()..shader = shader,
          );
        },
      );
    } finally {
      shader.dispose();
    }
  }

  Future<ui.Image> _copyImage(ui.Image source) {
    return _rasterize(
      width: source.width,
      height: source.height,
      painter: (canvas, size) {
        canvas.drawImage(source, ui.Offset.zero, ui.Paint());
      },
    );
  }

  Future<ByteData?> _rgbaByteData(ui.Image image) {
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  }

  Future<ui.Image> _decodeRgba(Uint8List bytes, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (result) => completer.complete(result),
    );
    return completer.future;
  }

  Future<ui.Image> _rasterize({
    required int width,
    required int height,
    required void Function(ui.Canvas canvas, ui.Size size) painter,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    painter(canvas, ui.Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  Future<ui.FragmentProgram> _shaderProgramFor(DistortionEffect effect) {
    return _shaderPrograms.putIfAbsent(
      effect,
      () => ui.FragmentProgram.fromAsset(_shaderAssetFor(effect)),
    );
  }

  void dispose() {}
}

String _shaderAssetFor(DistortionEffect effect) {
  return switch (effect) {
    DistortionEffect.original =>
      throw ArgumentError.value(effect, 'effect', 'Original has no shader'),
    DistortionEffect.narrowReed => 'effects/shaders/narrow_reed.glsl',
    DistortionEffect.wideReed => 'effects/shaders/wide_reed.glsl',
    DistortionEffect.lumina => 'effects/shaders/lumina.glsl',
    DistortionEffect.grid => 'effects/shaders/grid.glsl',
    DistortionEffect.liquid => 'effects/shaders/liquid.glsl',
    DistortionEffect.ripple => 'effects/shaders/ripple.glsl',
  };
}

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

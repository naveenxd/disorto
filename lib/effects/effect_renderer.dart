import 'dart:async';
import 'dart:math' as math;
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

class _RenderParams {
  const _RenderParams({
    required this.sourceBytes,
    required this.blurBytesLow,
    required this.blurBytesHigh,
    required this.blurMix,
    required this.width,
    required this.height,
    required this.intensity,
    required this.mapWidth,
    required this.mapHeight,
    required this.mapData,
    required this.originalDetailWeight,
  });

  final Uint8List sourceBytes;
  final Uint8List blurBytesLow;
  final Uint8List blurBytesHigh;
  final double blurMix;
  final int width;
  final int height;
  final double intensity;
  final int mapWidth;
  final int mapHeight;
  final Float32List mapData;
  final double originalDetailWeight;
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

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

double _smoothstep(double edge0, double edge1, double x) {
  final t = _clamp01((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
}

double _mix(double a, double b, double t) => a + (b - a) * t;

int _noopIsolate(int value) => value;

class _EffectMap {
  const _EffectMap({
    required this.width,
    required this.height,
    required this.data,
  });

  final int width;
  final int height;
  final Float32List data;
}

_EffectMap _generateEffectMap(DistortionEffect effect) {
  const width = 256;
  const height = 512;
  final data = Float32List(width * height * 2);

  double idx(int x, int y, int channel) =>
      ((y * width + x) * 2 + channel).toDouble();

  for (var y = 0; y < height; y++) {
    final v = y / (height - 1);
    for (var x = 0; x < width; x++) {
      final u = x / (width - 1);
      final sample = _generateEffectSample(effect, u, v);
      data[idx(x, y, 0).toInt()] = sample.dx.toDouble();
      data[idx(x, y, 1).toInt()] = sample.dy.toDouble();
    }
  }

  return _EffectMap(width: width, height: height, data: data);
}

({double dx, double dy}) _generateEffectSample(
  DistortionEffect effect,
  double u,
  double v,
) {
  switch (effect) {
    case DistortionEffect.original:
      return (dx: 0, dy: 0);
    case DistortionEffect.narrowReed:
      const columns = 40.0;
      final x = (u * columns) % 1.0;
      final center = (x - 0.5) * 2.0;
      final bend = center * center.abs();
      return (dx: bend * 0.13, dy: 0.0);
    case DistortionEffect.wideReed:
      const columns = 14.0;
      final x = (u * columns) % 1.0;
      final center = (x - 0.5) * 2.0;
      final bend = center * center.abs();
      return (dx: bend * 0.18, dy: 0.0);
    case DistortionEffect.lumina:
      const streaks = 10.0;
      final x = (u * streaks) % 1.0;
      final stripeCenter = 1.0 - ((x - 0.5) * 2.0).abs();
      final strength = stripeCenter.clamp(0.0, 1.0);
      final drift = math.sin(v * 8.0) * 0.004 * strength;
      final pull = -0.06 * strength * (0.3 + 0.7 * v);
      return (dx: drift, dy: pull);
    case DistortionEffect.grid:
      const cellsX = 8.0;
      const cellsY = 16.0;
      final localX = (u * cellsX) % 1.0;
      final localY = (v * cellsY) % 1.0;
      final cx = (localX - 0.5) * 2.0;
      final cy = (localY - 0.5) * 2.0;
      final pinch = 1.0 - (cx.abs() + cy.abs()) * 0.5;
      final influence = pinch.clamp(0.0, 1.0);
      return (dx: cx * 0.035 * influence, dy: cy * 0.035 * influence);
    case DistortionEffect.liquid:
      final waveX = math.sin(v * 9.0 + u * 2.2);
      final waveY = math.sin(u * 8.0 - v * 1.8);
      return (dx: waveX * 0.055, dy: waveY * 0.02);
    case DistortionEffect.ripple:
      final cx = 0.5;
      final cy = 0.5;
      final rx = u - cx;
      final ry = v - cy;
      final radius = math.sqrt(rx * rx + ry * ry);
      if (radius < 0.0001) return (dx: 0.0, dy: 0.0);
      final amp = 0.030 * (1.0 - _smoothstep(0.0, 0.75, radius));
      final wave = math.sin(radius * 28.0);
      final push = amp * wave;
      return (dx: (rx / radius) * push, dy: (ry / radius) * push);
  }
}

({double dx, double dy}) _sampleEffectMap(
  Float32List data,
  int width,
  int height,
  double u,
  double v,
) {
  final x = _clamp01(u) * (width - 1);
  final y = _clamp01(v) * (height - 1);
  final x0 = x.floor().clamp(0, width - 1);
  final y0 = y.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);
  final tx = x - x0;
  final ty = y - y0;

  double read(int px, int py, int channel) =>
      data[(py * width + px) * 2 + channel];

  double lerpChannel(int channel) {
    final c00 = read(x0, y0, channel);
    final c10 = read(x1, y0, channel);
    final c01 = read(x0, y1, channel);
    final c11 = read(x1, y1, channel);
    final a = _mix(c00, c10, tx);
    final b = _mix(c01, c11, tx);
    return _mix(a, b, ty);
  }

  return (dx: lerpChannel(0), dy: lerpChannel(1));
}

Uint8List _renderEffectIsolate(_RenderParams p) {
  final source = p.sourceBytes;
  final blurLow = p.blurBytesLow;
  final blurHigh = p.blurBytesHigh;
  final blurMix = p.blurMix.clamp(0.0, 1.0);
  final output = Uint8List(source.length);
  final originalDetailWeight = p.originalDetailWeight.clamp(0.0, 1.0);
  final blurWeight = 1.0 - originalDetailWeight;

  for (var y = 0; y < p.height; y++) {
    final v = y / (p.height - 1);
    for (var x = 0; x < p.width; x++) {
      final u = x / (p.width - 1);
      final profile = _sampleEffectMap(
        p.mapData,
        p.mapWidth,
        p.mapHeight,
        u,
        v,
      );
      final sx = _clamp01(u + profile.dx * p.intensity) * (p.width - 1);
      final sy = _clamp01(v + profile.dy * p.intensity) * (p.height - 1);
      final index = (y * p.width + x) * 4;

      // Pipeline: blur -> distortion -> final.
      final blurredDistortedLow = _sampleBilinearBytes(
        blurLow,
        p.width,
        p.height,
        sx,
        sy,
      );
      final blurredDistortedHigh = _sampleBilinearBytes(
        blurHigh,
        p.width,
        p.height,
        sx,
        sy,
      );
      final blurredDistorted = (
        r: _mix(blurredDistortedLow.r, blurredDistortedHigh.r, blurMix),
        g: _mix(blurredDistortedLow.g, blurredDistortedHigh.g, blurMix),
        b: _mix(blurredDistortedLow.b, blurredDistortedHigh.b, blurMix),
      );
      // Tiny optional detail contribution from original (not dominant).
      final originalDetail = _sampleBilinearBytes(
        source,
        p.width,
        p.height,
        u * (p.width - 1),
        v * (p.height - 1),
      );

      final r =
          blurredDistorted.r * blurWeight +
          originalDetail.r * originalDetailWeight;
      final g =
          blurredDistorted.g * blurWeight +
          originalDetail.g * originalDetailWeight;
      final b =
          blurredDistorted.b * blurWeight +
          originalDetail.b * originalDetailWeight;

      output[index] = (r * 255).round().clamp(0, 255);
      output[index + 1] = (g * 255).round().clamp(0, 255);
      output[index + 2] = (b * 255).round().clamp(0, 255);
      output[index + 3] = source[index + 3];
    }
  }

  return output;
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

({double r, double g, double b}) _sampleBilinearBytes(
  Uint8List bytes,
  int width,
  int height,
  double x,
  double y,
) {
  final x0 = x.floor().clamp(0, width - 1);
  final y0 = y.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);
  final tx = x - x0;
  final ty = y - y0;

  final c00 = _readRgb(bytes, width, x0, y0);
  final c10 = _readRgb(bytes, width, x1, y0);
  final c01 = _readRgb(bytes, width, x0, y1);
  final c11 = _readRgb(bytes, width, x1, y1);

  final r0 = _mix(c00.r, c10.r, tx);
  final g0 = _mix(c00.g, c10.g, tx);
  final b0 = _mix(c00.b, c10.b, tx);
  final r1 = _mix(c01.r, c11.r, tx);
  final g1 = _mix(c01.g, c11.g, tx);
  final b1 = _mix(c01.b, c11.b, tx);

  return (r: _mix(r0, r1, ty), g: _mix(g0, g1, ty), b: _mix(b0, b1, ty));
}

({double r, double g, double b}) _readRgb(
  Uint8List bytes,
  int width,
  int x,
  int y,
) {
  final index = (y * width + x) * 4;
  return (
    r: bytes[index] / 255.0,
    g: bytes[index + 1] / 255.0,
    b: bytes[index + 2] / 255.0,
  );
}

class EffectRenderer {
  final Map<DistortionEffect, Future<_EffectMap>> _effectMapFutures = {};

  Future<void> init() async {}

  Future<void> prewarmIsolate() async {
    await compute(_noopIsolate, 1);
  }

  Future<void> prewarmEffectMaps(Iterable<DistortionEffect> effects) async {
    await Future.wait(effects.map(_effectMapForAsync));
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
      final baseData = await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (baseData == null) {
        return _copyImage(source);
      }

      final blurData = await blurredBase.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (blurData == null) {
        return _copyImage(source);
      }
      final secondary = blurredBaseSecondary ?? blurredBase;
      final blurDataSecondary = await secondary.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (blurDataSecondary == null) {
        return _decodeRgba(
          blurData.buffer.asUint8List(),
          source.width,
          source.height,
        );
      }

      if (effect == DistortionEffect.original) {
        final normalizedMix = blurMix.clamp(0.0, 1.0);
        if (normalizedMix <= 0.0001) {
          return _decodeRgba(
            blurData.buffer.asUint8List(),
            source.width,
            source.height,
          );
        }
        if (normalizedMix >= 0.9999) {
          return _decodeRgba(
            blurDataSecondary.buffer.asUint8List(),
            source.width,
            source.height,
          );
        }
        final blended = await compute(
          _blendIsolate,
          _BlendParams(
            lowBytes: blurData.buffer.asUint8List(),
            highBytes: blurDataSecondary.buffer.asUint8List(),
            mix: normalizedMix,
          ),
        );
        return _decodeRgba(
          blended,
          source.width,
          source.height,
        );
      }

      final map = await _effectMapForAsync(effect);
      final bytes = await compute(
        _renderEffectIsolate,
        _RenderParams(
          sourceBytes: baseData.buffer.asUint8List(),
          blurBytesLow: blurData.buffer.asUint8List(),
          blurBytesHigh: blurDataSecondary.buffer.asUint8List(),
          blurMix: blurMix.clamp(0.0, 1.0),
          width: source.width,
          height: source.height,
          intensity: intensity,
          mapWidth: map.width,
          mapHeight: map.height,
          mapData: map.data,
          originalDetailWeight: originalDetailWeight.clamp(0.0, 1.0),
        ),
      );

      return _decodeRgba(bytes, source.width, source.height);
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
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _copyImage(image);
    }

    final bytes = await compute(
      _blurIsolate,
      _BlurParams(
        bytes: byteData.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        scaledWidth: (image.width * scale.clamp(0.1, 1.0)).round().clamp(
          1,
          image.width,
        ),
        scaledHeight: (image.height * scale.clamp(0.1, 1.0)).round().clamp(
          1,
          image.height,
        ),
        radius: radius.clamp(0, 128),
      ),
    );

    return _decodeRgba(bytes, image.width, image.height);
  }

  Future<ui.Image> _copyImage(ui.Image source) async {
    final byteData = await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
      );
      canvas.drawImage(source, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final copy = await picture.toImage(source.width, source.height);
      picture.dispose();
      return copy;
    }
    return _decodeRgba(
      byteData.buffer.asUint8List(),
      source.width,
      source.height,
    );
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

  void dispose() {}

  Future<_EffectMap> _effectMapForAsync(DistortionEffect effect) {
    return _effectMapFutures.putIfAbsent(
      effect,
      () => compute(_generateEffectMap, effect),
    );
  }
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

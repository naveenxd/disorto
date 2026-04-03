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

  String? get shaderAsset => switch (this) {
    DistortionEffect.original => null,
    DistortionEffect.narrowReed => 'effects/shaders/narrow_reed.glsl',
    DistortionEffect.wideReed => 'effects/shaders/wide_reed.glsl',
    DistortionEffect.lumina => 'effects/shaders/lumina.glsl',
    DistortionEffect.grid => 'effects/shaders/grid.glsl',
    DistortionEffect.liquid => 'effects/shaders/liquid.glsl',
    DistortionEffect.ripple => 'effects/shaders/ripple.glsl',
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

class _RenderParams {
  const _RenderParams({
    required this.sourceBytes,
    required this.blurBytes,
    required this.width,
    required this.height,
    required this.effectIndex,
    required this.intensity,
    required this.mapWidth,
    required this.mapHeight,
    required this.mapData,
  });

  final Uint8List sourceBytes;
  final Uint8List blurBytes;
  final int width;
  final int height;
  final int effectIndex;
  final double intensity;
  final int mapWidth;
  final int mapHeight;
  final Float32List mapData;
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

  working = img.gaussianBlur(working, radius: p.radius);

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
  final noise = (math.sin(u * 120.0 + v * 80.0) - 0.5) * 0.003;

  switch (effect) {
    case DistortionEffect.original:
      return (dx: 0, dy: 0);
    case DistortionEffect.narrowReed:
      final count = 34.0;
      final bar = (u * count) % 1.0;
      final normal = (bar - 0.5) * 2.0;
      final center = (1.0 - normal.abs()).clamp(0.0, 1.0);
      return (
        dx: normal * normal.abs() * 0.065 + (center - 0.5) * 0.004 + noise,
        dy: noise * 0.4,
      );
    case DistortionEffect.wideReed:
      final count = 15.0;
      final bar = (u * count) % 1.0;
      final normal = (bar - 0.5) * 2.0;
      final center = (1.0 - normal.abs()).clamp(0.0, 1.0);
      final strip = (u * count).floorToDouble();
      final yOffset = math.sin(strip * 0.8 + v * 2.5) * 0.010;
      return (
        dx: normal * normal.abs() * 0.090 + noise,
        dy: yOffset * center + noise * 0.4,
      );
    case DistortionEffect.lumina:
      final count = 9.0;
      final bar = (u * count) % 1.0;
      final normal = (bar - 0.5) * 2.0;
      final center = (1.0 - normal.abs()).clamp(0.0, 1.0);
      final rise = v * v;
      return (
        dx: math.sin(v * 6.0 + u * 2.0) * center * 0.006 + noise,
        dy: -center * rise * 0.050 + noise * 0.4,
      );
    case DistortionEffect.grid:
      const cellsX = 6.2;
      const cellsY = 6.2 * (512.0 / 256.0);
      final gx = (u * cellsX) % 1.0 - 0.5;
      final gy = (v * cellsY) % 1.0 - 0.5;
      final qx = gx.abs() - 0.24;
      final qy = gy.abs() - 0.24;
      final radius = math.sqrt(
        (qx > 0 ? qx : 0) * (qx > 0 ? qx : 0) +
            (qy > 0 ? qy : 0) * (qy > 0 ? qy : 0),
      );
      final tile = 1.0 - _smoothstep(0.02, 0.10, radius);
      return (
        dx: gx * 0.055 * tile + noise,
        dy: gy * 0.055 * tile + noise * 0.4,
      );
    case DistortionEffect.liquid:
      final weight = 0.35 + 0.65 * v;
      final wave1 = math.sin(v * 5.0 + u * 2.2);
      final wave2 = math.sin(v * 9.0 - u * 1.1);
      return (
        dx: (wave1 * 0.100 + wave2 * 0.050) * weight + noise,
        dy: wave2 * 0.020 * weight + noise * 0.4,
      );
    case DistortionEffect.ripple:
      final cx = 0.5;
      final cy = 0.57;
      const aspect = 256.0 / 512.0;
      var dx = (u - cx) * aspect;
      var dy = v - cy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final lens = 1.0 - _smoothstep(0.0, 0.42, dist);
      final ring =
          math.sin(dist * 26.0) * (1.0 - _smoothstep(0.06, 0.52, dist));
      final radius = dist * (1.0 - lens * 0.82) + ring * 0.045;
      final angle = math.atan2(dy, dx);
      dx = math.cos(angle) * radius / aspect - (u - cx);
      dy = math.sin(angle) * radius - (v - cy);
      return (dx: dx * 1.4 + noise, dy: dy * 1.4 + noise * 0.4);
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
  final blur = p.blurBytes;
  final output = Uint8List(source.length);
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
      final glass = _sampleBilinearBytes(blur, p.width, p.height, sx, sy);
      final detailMix = 0.20;
      final r = _mix(glass.r, source[index] / 255.0, detailMix);
      final g = _mix(glass.g, source[index + 1] / 255.0, detailMix);
      final b = _mix(glass.b, source[index + 2] / 255.0, detailMix);

      output[index] = (r * 255).round().clamp(0, 255);
      output[index + 1] = (g * 255).round().clamp(0, 255);
      output[index + 2] = (b * 255).round().clamp(0, 255);
      output[index + 3] = source[index + 3];
    }
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
  final Map<DistortionEffect, _EffectMap> _effectMaps = {};

  Future<void> init() async {}

  Future<ui.Image> render({
    required ui.Image source,
    ui.Image? blurredBase,
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

      final blurImage = blurredBase ?? source;
      final blurData = await blurImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (blurData == null) {
        return _copyImage(source);
      }

      if (effect == DistortionEffect.original) {
        return _decodeRgba(
          blurData.buffer.asUint8List(),
          source.width,
          source.height,
        );
      }

      final bytes = await compute(
        _renderEffectIsolate,
        _RenderParams(
          sourceBytes: baseData.buffer.asUint8List(),
          blurBytes: blurData.buffer.asUint8List(),
          width: source.width,
          height: source.height,
          effectIndex: effect.index,
          intensity: intensity,
          mapWidth: _effectMapFor(effect).width,
          mapHeight: _effectMapFor(effect).height,
          mapData: _effectMapFor(effect).data,
        ),
      );

      return _decodeRgba(bytes, source.width, source.height);
    } catch (_) {
      return _copyImage(blurredBase ?? source);
    }
  }

  Future<ui.Image> prepareBlurredBase({
    required ui.Image source,
    required int blurLevel,
  }) async {
    if (blurLevel <= 0) {
      return _copyImage(source);
    }
    return _applyBlur(image: source, blurLevel: blurLevel);
  }

  Future<ui.Image> _applyBlur({
    required ui.Image image,
    required int blurLevel,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _copyImage(image);
    }

    final scale = switch (blurLevel) {
      1 => 0.90,
      2 => 0.75,
      3 => 0.65,
      _ => 0.55,
    };
    final radius = switch (blurLevel) {
      1 => 6,
      2 => 10,
      3 => 14,
      _ => 18,
    };

    final bytes = await compute(
      _blurIsolate,
      _BlurParams(
        bytes: byteData.buffer.asUint8List(),
        width: image.width,
        height: image.height,
        scaledWidth: (image.width * scale).round().clamp(1, image.width),
        scaledHeight: (image.height * scale).round().clamp(1, image.height),
        radius: radius,
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

  _EffectMap _effectMapFor(DistortionEffect effect) {
    return _effectMaps.putIfAbsent(effect, () => _generateEffectMap(effect));
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

class ShaderProgramCache {
  final Map<String, Future<ui.FragmentProgram>> _pending = {};
  final Map<String, ui.FragmentProgram> _ready = {};

  Future<void> init() async {
    await Future.wait(
      DistortionEffect.values
          .where((effect) => effect.shaderAsset != null)
          .map((effect) => loadProgram(effect)),
    );
  }

  Future<ui.FragmentProgram?> loadProgram(DistortionEffect effect) async {
    final asset = effect.shaderAsset;
    if (asset == null) {
      return null;
    }
    final cached = _ready[asset];
    if (cached != null) {
      return cached;
    }

    final pending = _pending.putIfAbsent(
      asset,
      () => ui.FragmentProgram.fromAsset(asset),
    );
    final program = await pending;
    _ready[asset] = program;
    _pending.remove(asset);
    return program;
  }

  ui.FragmentProgram? getCachedProgram(DistortionEffect effect) {
    final asset = effect.shaderAsset;
    if (asset == null) {
      return null;
    }
    return _ready[asset];
  }

  void dispose() {
    _pending.clear();
    _ready.clear();
  }
}

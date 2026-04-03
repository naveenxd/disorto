import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../effects/effect_renderer.dart';
import '../services/image_export_service.dart';
import '../services/wallpaper_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditorScreen
// ─────────────────────────────────────────────────────────────────────────────

class EditorScreen extends StatefulWidget {
  final String imagePath;
  const EditorScreen({super.key, required this.imagePath});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static final int _blurLevels = kBlurPresets.length;
  static const double _previewScale = 0.55; // 50-70% preview resolution
  static const int _previewMaxDimension = 1400; // hard cap for UI rendering
  static const Duration _renderDebounceDelay = Duration(milliseconds: 66);
  static const Duration _minRenderInterval = Duration(milliseconds: 84);

  // ── Renderer ───────────────────────────────────────────────────────────────
  final EffectRenderer _renderer = EffectRenderer();

  // ── Source image (encoded/original for export only) ────────────────────────
  Uint8List? _sourceBytes;
  ui.Image? _previewSource;

  // ── Processing state ───────────────────────────────────────────────────────
  ui.Image? _previewImage;
  bool _initialising = true;

  // ── Controls ───────────────────────────────────────────────────────────────
  DistortionEffect _effect = DistortionEffect.original;
  double _rawBlurValue = 0.0; // 0.0-1.0 (UI motion)
  int _snappedBlurIndex = 0; // actual blur preset index
  bool _isBlurDragging = false;

  // ── Thumbnail cache ────────────────────────────────────────────────────────
  // Keyed by DistortionEffect; generated at load time from a downscaled source.
  final Map<DistortionEffect, ui.Image?> _thumbs = {};
  ui.Image? _thumbSource; // downscaled source for thumbnail rendering
  final Map<int, ui.Image> _previewBlurBases = {};
  final Map<int, ui.Image> _thumbBlurBases = {};
  Timer? _renderDebounceTimer;
  Timer? _renderThrottleTimer;
  int _renderGeneration = 0;
  bool _renderInFlight = false;
  bool _renderQueued = false;
  DateTime _lastRenderStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Saving state ──────────────────────────────────────────────────────────
  bool _saving = false;
  bool _wallpapering = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _renderDebounceTimer?.cancel();
    _renderThrottleTimer?.cancel();
    _renderer.dispose();
    _previewImage?.dispose();
    _sourceBytes = null;
    _previewSource?.dispose();
    _thumbSource?.dispose();
    for (final t in _thumbs.values) {
      t?.dispose();
    }
    for (final image in _previewBlurBases.values) {
      image.dispose();
    }
    for (final image in _thumbBlurBases.values) {
      image.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bootstrap
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    // Keep original encoded bytes for export, but decode only a bounded preview.
    final bytes = await File(widget.imagePath).readAsBytes();
    _sourceBytes = bytes;
    final preview = await _decodePreviewFromBytes(bytes);
    if (!mounted) {
      preview.dispose();
      return;
    }
    setState(() {
      _previewSource = preview;
      _initialising = false;
    });

    // Heavy processing stays fully asynchronous and never blocks first paint.
    unawaited(_bootstrapBackgroundWork());
  }

  Future<void> _bootstrapBackgroundWork() async {
    if (_previewSource == null || !mounted) return;
    await _renderer.init();

    // Start with an immediate render pass using whatever cache is available.
    _scheduleDebouncedRender(immediate: true);

    // Blur cache generation (background): level 0 first, then the rest.
    await _precomputePreviewBlurLevel(0);
    unawaited(_runBackgroundPrewarm());
    for (var level = 1; level < _blurLevels; level++) {
      if (!mounted) return;
      await _precomputePreviewBlurLevel(level);
    }

    if (!mounted) return;
    // Refresh once full blur cache is ready.
    _scheduleDebouncedRender(immediate: true);

    // Thumbnails are non-critical: build lazily in background.
    unawaited(_prepareThumbPipeline());
  }

  Future<void> _runRenderNow() async {
    if (_previewSource == null) return;
    if (_renderInFlight) {
      _renderQueued = true;
      return;
    }
    _renderInFlight = true;
    _lastRenderStartAt = DateTime.now();
    final generation = ++_renderGeneration;
    try {
      final rendered = await _renderInterpolatedEffect(
        source: _previewSource!,
        effect: _effect,
        blurValue: _rawBlurValue,
        blurCache: _previewBlurBases,
      );
      if (!mounted) {
        rendered.dispose();
        return;
      }
      if (generation != _renderGeneration) {
        rendered.dispose();
        return;
      }
      setState(() {
        _schedulePreviewImageDispose(_previewImage);
        _previewImage = rendered;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Effect render failed: $e');
    } finally {
      _renderInFlight = false;
      if (_renderQueued && mounted) {
        _renderQueued = false;
        _scheduleDebouncedRender();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Thumbnail generation (downscaled, all effects, background)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _generateThumbnails() async {
    if (_thumbSource == null) return;
    for (final effect in DistortionEffect.values) {
      if (!mounted) return;
      final blurredBase = _getCachedBlurLevel(
        _thumbBlurBases,
        0,
        _thumbSource!,
      );
      final thumb = await _renderer.render(
        source: _thumbSource!,
        blurredBase: blurredBase,
        effect: effect,
        intensity: 1.0,
      );
      if (mounted) {
        setState(() {
          _thumbs[effect]?.dispose();
          _thumbs[effect] = thumb;
        });
      } else {
        thumb.dispose();
        return;
      }
    }
  }

  Future<void> _runBackgroundPrewarm() async {
    if (_previewSource == null) return;
    final source = _previewSource!;
    final base0 = _previewBlurBases[0];
    if (base0 == null) return;

    try {
      final dummyRenderFuture = _renderer.render(
        source: source,
        blurredBase: base0,
        effect: DistortionEffect.original,
        intensity: 0.0,
      );

      await Future.wait([
        _renderer.prewarmIsolate(),
        _renderer.prewarmEffectMaps(
          DistortionEffect.values.where(
            (effect) => effect != DistortionEffect.original,
          ),
        ),
      ]);
      final dummyImage = await dummyRenderFuture;
      dummyImage.dispose();
    } catch (_) {
      // Prewarm is best-effort and must never block interaction.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<ui.Image> _downscale(ui.Image src, {required int targetWidth}) async {
    final tw = targetWidth.clamp(1, src.width);
    final th = (src.height * (tw / src.width)).round().clamp(1, src.height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(tw, th);
    picture.dispose();
    return img;
  }

  Future<ui.Image> _decodePreviewFromBytes(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);

    final sourceWidth = descriptor.width;
    final sourceHeight = descriptor.height;
    final longestEdge = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
    final appliedScale = math.min(
      _previewScale,
      _previewMaxDimension / longestEdge,
    ).clamp(0.1, 1.0);
    final targetWidth = (sourceWidth * appliedScale).round().clamp(1, sourceWidth);
    final targetHeight = (sourceHeight * appliedScale).round().clamp(
      1,
      sourceHeight,
    );

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<ui.Image> _decodeOriginalFromBytes(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final frame = await codec.getNextFrame();
    codec.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<String> _exportToTemp() async {
    final sourceBytes = _sourceBytes;
    if (sourceBytes == null) {
      throw StateError('Original image bytes are not available.');
    }
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/distorto_export_${DateTime.now().millisecondsSinceEpoch}.png';

    final fullResSource = await _decodeOriginalFromBytes(sourceBytes);
    ui.Image? exportBlur;
    ui.Image? rendered;
    try {
      exportBlur = await _renderer.prepareBlurredBase(
        source: fullResSource,
        presetLevel: _snappedBlurIndex,
      );
      rendered = await _renderer.render(
        source: fullResSource,
        blurredBase: exportBlur,
        originalDetailWeight: _detailWeightForBlurValue(
          _snappedBlurIndex / (_blurLevels - 1),
        ),
        effect: _effect,
        intensity: 1.0,
      );
      final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode exported image.');
      }
      await File(outPath).writeAsBytes(byteData.buffer.asUint8List());
    } finally {
      rendered?.dispose();
      exportBlur?.dispose();
      fullResSource.dispose();
    }
    return outPath;
  }

  Future<void> _precomputePreviewBlurLevel(int level) async {
    if (_previewBlurBases.containsKey(level)) return;
    _previewBlurBases[level] = await _renderer.prepareBlurredBase(
      source: _previewSource!,
      presetLevel: level,
    );
  }

  Future<void> _prepareThumbPipeline() async {
    final source = _previewSource;
    if (source == null || !mounted) return;
    final thumb = await _downscale(source, targetWidth: 200);
    if (!mounted) {
      thumb.dispose();
      return;
    }
    _thumbSource?.dispose();
    _thumbSource = thumb;
    _thumbBlurBases[0]?.dispose();
    _thumbBlurBases[0] = await _renderer.prepareBlurredBase(
      source: _thumbSource!,
      presetLevel: 0,
    );
    await _generateThumbnails();
  }

  ui.Image _getCachedBlurLevel(
    Map<int, ui.Image> cache,
    int level,
    ui.Image fallback,
  ) {
    final exact = cache[level];
    if (exact != null) return exact;
    for (var i = 0; i < _blurLevels; i++) {
      final down = cache[level - i];
      if (down != null) return down;
      final up = cache[level + i];
      if (up != null) return up;
    }
    return fallback;
  }

  ({ui.Image low, ui.Image high, double mix}) _resolveBlurBlend({
    required Map<int, ui.Image> cache,
    required double blurValue,
    required ui.Image fallback,
  }) {
    final steps = _blurLevels - 1;
    final scaled = blurValue.clamp(0.0, 1.0) * steps;
    final lowIndex = scaled.floor().clamp(0, steps);
    final highIndex = scaled.ceil().clamp(0, steps);
    final mix = (scaled - lowIndex).clamp(0.0, 1.0);
    final low = _getCachedBlurLevel(cache, lowIndex, fallback);
    final high = _getCachedBlurLevel(cache, highIndex, fallback);
    return (low: low, high: high, mix: mix);
  }

  double _detailWeightForBlurValue(double blurValue) {
    final t = blurValue.clamp(0.0, 1.0);
    return ui.lerpDouble(0.12, 0.02, t) ?? 0.08;
  }

  Future<ui.Image> _renderInterpolatedEffect({
    required ui.Image source,
    required DistortionEffect effect,
    required double blurValue,
    required Map<int, ui.Image> blurCache,
  }) async {
    final blend = _resolveBlurBlend(
      cache: blurCache,
      blurValue: blurValue,
      fallback: source,
    );
    return _renderer.render(
      source: source,
      blurredBase: blend.low,
      blurredBaseSecondary: blend.high,
      blurMix: blend.mix,
      originalDetailWeight: _detailWeightForBlurValue(blurValue),
      effect: effect,
      intensity: 1.0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onEffectSelected(DistortionEffect effect) async {
    if (_effect == effect) return;
    setState(() => _effect = effect);
    _scheduleDebouncedRender(immediate: true);
  }

  void _onBlurChanged(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((_rawBlurValue - clamped).abs() < 0.0001) return;
    final steps = _blurLevels - 1;
    final nextIndex = (clamped * steps).round().clamp(0, steps);
    setState(() {
      _rawBlurValue = clamped;
      _snappedBlurIndex = nextIndex;
    });
    _scheduleDebouncedRender(immediate: true);
  }

  void _onBlurDragStart(double _) {
    if (!_isBlurDragging) {
      setState(() => _isBlurDragging = true);
    }
  }

  void _onBlurDragEnd(double _) {
    final steps = _blurLevels - 1;
    final nextIndex = (_rawBlurValue.clamp(0.0, 1.0) * steps).round().clamp(
      0,
      steps,
    );
    final target = nextIndex / steps;
    final shouldRender = nextIndex != _snappedBlurIndex;
    if (_isBlurDragging) {
      setState(() {
        _isBlurDragging = false;
        _rawBlurValue = target;
        _snappedBlurIndex = nextIndex;
      });
    } else {
      setState(() {
        _rawBlurValue = target;
        _snappedBlurIndex = nextIndex;
      });
    }
    if (shouldRender) {
      HapticFeedback.selectionClick();
    }
    _scheduleDebouncedRender(immediate: true);
  }

  void _scheduleDebouncedRender({bool immediate = false}) {
    _renderDebounceTimer?.cancel();
    final delay = immediate ? Duration.zero : _renderDebounceDelay;
    _renderDebounceTimer = Timer(delay, _scheduleThrottledRender);
  }

  void _scheduleThrottledRender() {
    _renderThrottleTimer?.cancel();
    final elapsed = DateTime.now().difference(_lastRenderStartAt);
    final wait = _minRenderInterval - elapsed;
    if (wait <= Duration.zero) {
      unawaited(_runRenderNow());
      return;
    }
    _renderThrottleTimer = Timer(wait, () {
      unawaited(_runRenderNow());
    });
  }

  void _schedulePreviewImageDispose(ui.Image? image) {
    if (image == null) return;
    final candidate = image;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) {
        candidate.dispose();
        return;
      }
      if (!identical(candidate, _previewImage)) {
        candidate.dispose();
      }
    });
  }

  Future<void> _onSave() async {
    if (_saving || _sourceBytes == null) return;
    setState(() => _saving = true);
    try {
      final path = await _exportToTemp();
      await ImageExportService.saveFileToGallery(path);
      if (mounted) {
        _showSnack('Saved to gallery ✓');
      }
    } on ExportException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onSetWallpaper() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _WallpaperSheet(
        onSelect: (location) {
          Navigator.pop(ctx);
          _applyWallpaper(location);
        },
      ),
    );
  }

  Future<void> _applyWallpaper(int location) async {
    if (_wallpapering || _sourceBytes == null) return;
    setState(() => _wallpapering = true);
    try {
      final path = await _exportToTemp();
      await WallpaperService.setWallpaper(imagePath: path, location: location);
      if (mounted) _showSnack('Wallpaper set ✓');
    } on WallpaperException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('Failed: $e');
    } finally {
      if (mounted) setState(() => _wallpapering = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          children: [
            // ── Full-screen image preview ────────────────────────────────
            _PreviewPane(
              previewImage: _previewImage ?? _previewSource,
              initialising: _initialising,
            ),

            // ── Top-right action buttons ─────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: _TopActions(
                saving: _saving,
                wallpapering: _wallpapering,
                onSave: _onSave,
                onWallpaper: _onSetWallpaper,
              ),
            ),

            // ── Back button ──────────────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 4,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),

            // ── Persistent bottom sheet ──────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomPanel(
                blurValue: _rawBlurValue,
                isDraggingBlur: _isBlurDragging,
                snappedBlurIndex: _snappedBlurIndex,
                blurSteps: _blurLevels - 1,
                selectedEffect: _effect,
                thumbs: _thumbs,
                onBlurChanged: _onBlurChanged,
                onBlurChangeStart: _onBlurDragStart,
                onBlurChangeEnd: _onBlurDragEnd,
                onEffectSelected: _onEffectSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PreviewPane
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewPane extends StatelessWidget {
  final ui.Image? previewImage;
  final bool initialising;

  const _PreviewPane({required this.previewImage, required this.initialising});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: initialising
            ? const _LoadingPlaceholder(key: ValueKey('loading'))
            : previewImage != null
            ? _ImageDisplay(
                key: ValueKey('${previewImage.hashCode}'),
                image: previewImage!,
              )
            : const _LoadingPlaceholder(key: ValueKey('blank')),
      ),
    );
  }
}

class _ImageDisplay extends StatelessWidget {
  final ui.Image image;

  const _ImageDisplay({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: image.width.toDouble(),
          height: image.height.toDouble(),
          child: RawImage(image: image, fit: BoxFit.fill),
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0A0A0A),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white30,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TopActions
// ─────────────────────────────────────────────────────────────────────────────

class _TopActions extends StatelessWidget {
  final bool saving;
  final bool wallpapering;
  final VoidCallback onSave;
  final VoidCallback onWallpaper;

  const _TopActions({
    required this.saving,
    required this.wallpapering,
    required this.onSave,
    required this.onWallpaper,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
          icon: Icons.download_rounded,
          loading: saving,
          onTap: onSave,
          tooltip: 'Save to gallery',
        ),
        const SizedBox(width: 6),
        _ActionButton(
          icon: Icons.wallpaper_rounded,
          loading: wallpapering,
          onTap: onWallpaper,
          tooltip: 'Set wallpaper',
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.loading,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(140),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(30), width: 0.8),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BottomPanel  (persistent bottom sheet visual)
// ─────────────────────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final double blurValue;
  final bool isDraggingBlur;
  final int snappedBlurIndex;
  final int blurSteps;
  final DistortionEffect selectedEffect;
  final Map<DistortionEffect, ui.Image?> thumbs;
  final ValueChanged<double> onBlurChanged;
  final ValueChanged<double> onBlurChangeStart;
  final ValueChanged<double> onBlurChangeEnd;
  final ValueChanged<DistortionEffect> onEffectSelected;

  const _BottomPanel({
    required this.blurValue,
    required this.isDraggingBlur,
    required this.snappedBlurIndex,
    required this.blurSteps,
    required this.selectedEffect,
    required this.thumbs,
    required this.onBlurChanged,
    required this.onBlurChangeStart,
    required this.onBlurChangeEnd,
    required this.onEffectSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6111111), // ~90% opaque
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x22FFFFFF), width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle.
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Blur section.
          _BlurSection(
            blurValue: blurValue,
            isDragging: isDraggingBlur,
            snappedBlurIndex: snappedBlurIndex,
            blurSteps: blurSteps,
            onChanged: onBlurChanged,
            onChangeStart: onBlurChangeStart,
            onChangeEnd: onBlurChangeEnd,
          ),

          const SizedBox(height: 22),

          // Effect thumbnails.
          _EffectRow(
            selectedEffect: selectedEffect,
            thumbs: thumbs,
            onSelect: onEffectSelected,
          ),

          SizedBox(height: 16 + bottomPad),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BlurSection
// ─────────────────────────────────────────────────────────────────────────────

class _BlurSection extends StatelessWidget {
  final double blurValue;
  final bool isDragging;
  final int snappedBlurIndex;
  final int blurSteps;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  const _BlurSection({
    required this.blurValue,
    required this.isDragging,
    required this.snappedBlurIndex,
    required this.blurSteps,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Blur',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                opacity: isDragging ? 0.72 : 0.56,
                child: Text(
                  '${((isDragging ? blurValue : (snappedBlurIndex / blurSteps)) * 100).round()}%',
                  style: TextStyle(
                    color: isDragging
                        ? Colors.white.withAlpha(186)
                        : Colors.white.withAlpha(142),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _BlurSlider(
            value: blurValue,
            isDragging: isDragging,
            snappedIndex: snappedBlurIndex,
            steps: blurSteps,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _BlurSlider extends StatefulWidget {
  final double value;
  final bool isDragging;
  final int snappedIndex;
  final int steps;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  const _BlurSlider({
    required this.value,
    required this.isDragging,
    required this.snappedIndex,
    required this.steps,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  @override
  State<_BlurSlider> createState() => _BlurSliderState();
}

class _BlurSliderState extends State<_BlurSlider> {
  double _animatedValue = 0.0;

  @override
  void initState() {
    super.initState();
    _animatedValue = widget.value.clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _BlurSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value.clamp(0.0, 1.0);
    if ((next - _animatedValue).abs() > 0.0001 && !widget.isDragging) {
      _animatedValue = next;
    }
  }

  double _valueFromDx(double dx, double width) {
    if (width <= 0) return widget.value.clamp(0.0, 1.0);
    return (dx / width).clamp(0.0, 1.0);
  }

  void _handleTapDown(TapDownDetails details, double width) {
    final next = _valueFromDx(details.localPosition.dx, width);
    widget.onChangeStart(widget.value.clamp(0.0, 1.0));
    widget.onChanged(next);
  }

  void _handleTapUp() {
    widget.onChangeEnd(widget.value.clamp(0.0, 1.0));
  }

  void _handlePanStart() {
    widget.onChangeStart(widget.value.clamp(0.0, 1.0));
  }

  void _handlePanUpdate(DragUpdateDetails details, double width) {
    widget.onChanged(_valueFromDx(details.localPosition.dx, width));
  }

  void _handlePanEnd() {
    widget.onChangeEnd(widget.value.clamp(0.0, 1.0));
  }

  void _handlePanCancel() {
    widget.onChangeEnd(widget.value.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final rawValue = widget.value.clamp(0.0, 1.0);
    final isDragging = widget.isDragging;
    final steps = widget.steps <= 0 ? 1 : widget.steps;
    final dragIndex = (rawValue * steps).round().clamp(0, steps);
    final targetIndex = isDragging
        ? dragIndex
        : widget.snappedIndex.clamp(0, steps);
    final targetVisual = targetIndex / steps;
    const curve = Cubic(0.22, 1.0, 0.36, 1.0);
    const duration = Duration(milliseconds: 116);
    if ((_animatedValue - targetVisual).abs() > 0.0001 && !isDragging) {
      _animatedValue = targetVisual;
    }

    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleTapDown(details, trackWidth),
            onTapUp: (_) => _handleTapUp(),
            onHorizontalDragStart: (_) => _handlePanStart(),
            onHorizontalDragUpdate: (details) =>
                _handlePanUpdate(details, trackWidth),
            onHorizontalDragEnd: (_) => _handlePanEnd(),
            onHorizontalDragCancel: _handlePanCancel,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _animatedValue, end: targetVisual),
              duration: duration,
              curve: curve,
              builder: (context, visualValue, _) {
                _animatedValue = visualValue;
                const pillHeight = 30.0;
                const horizontalInset = 19.0;
                const thumbDiameter = 20.0;
                final usableWidth = (trackWidth - horizontalInset * 2).clamp(
                  1.0,
                  trackWidth,
                );
                final stepWidth =
                    usableWidth / (widget.steps <= 0 ? 1 : widget.steps);
                final thumbCenterX =
                    horizontalInset + visualValue * usableWidth;
                const opticalThumbShift = 1.5;
                const fillEndOffset = 2.0;
                final thumbLeft =
                    thumbCenterX - thumbDiameter / 2 - opticalThumbShift;
                final activeWidth = (thumbCenterX - fillEndOffset).clamp(
                  0.0,
                  trackWidth,
                );
                final dotCount = widget.steps + 1;
                const dotSize = 6.0;
                final activeDotIndex = (visualValue * widget.steps)
                    .round()
                    .clamp(0, widget.steps);

                return Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(pillHeight / 2),
                    child: SizedBox(
                      width: trackWidth,
                      height: pillHeight,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: pillHeight,
                            width: trackWidth,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(26),
                              borderRadius: BorderRadius.circular(
                                pillHeight / 2,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: duration,
                            curve: curve,
                            height: pillHeight,
                            width: activeWidth.clamp(0.0, trackWidth),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(
                                isDragging ? 38 : 32,
                              ),
                              borderRadius: BorderRadius.circular(
                                pillHeight / 2,
                              ),
                            ),
                          ),
                          ...List.generate(dotCount, (i) {
                            final active = i <= activeDotIndex;
                            final dotX = horizontalInset + i * stepWidth;
                            return AnimatedPositioned(
                              duration: duration,
                              curve: curve,
                              left: dotX - dotSize / 2,
                              top: (pillHeight - dotSize) / 2,
                              child: AnimatedContainer(
                                duration: duration,
                                curve: curve,
                                width: dotSize,
                                height: dotSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? Colors.white.withAlpha(
                                          (122 + (i / (dotCount - 1)) * 38)
                                              .round(),
                                        )
                                      : Colors.white.withAlpha(50),
                                ),
                              ),
                            );
                          }),
                          AnimatedPositioned(
                            duration: duration,
                            curve: curve,
                            left: thumbLeft,
                            top: (pillHeight - thumbDiameter) / 2,
                            child: AnimatedScale(
                              duration: Duration(
                                milliseconds: isDragging ? 80 : 130,
                              ),
                              curve: curve,
                              scale: isDragging ? 1.15 : 1.0,
                              child: AnimatedContainer(
                                duration: duration,
                                curve: curve,
                                width: thumbDiameter,
                                height: thumbDiameter,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withAlpha(
                                        isDragging ? 76 : 52,
                                      ),
                                      blurRadius: isDragging ? 12 : 9,
                                      spreadRadius: isDragging ? 0.8 : 0.2,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withAlpha(55),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EffectRow — horizontal scrollable thumbnail strip
// ─────────────────────────────────────────────────────────────────────────────

class _EffectRow extends StatelessWidget {
  final DistortionEffect selectedEffect;
  final Map<DistortionEffect, ui.Image?> thumbs;
  final ValueChanged<DistortionEffect> onSelect;

  const _EffectRow({
    required this.selectedEffect,
    required this.thumbs,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: DistortionEffect.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final effect = DistortionEffect.values[i];
          return _EffectThumb(
            effect: effect,
            thumb: thumbs[effect],
            selected: effect == selectedEffect,
            onTap: () => onSelect(effect),
          );
        },
      ),
    );
  }
}

// ── Single effect thumbnail ───────────────────────────────────────────────────

class _EffectThumb extends StatelessWidget {
  final DistortionEffect effect;
  final ui.Image? thumb;
  final bool selected;
  final VoidCallback onTap;

  const _EffectThumb({
    required this.effect,
    required this.thumb,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 70,
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.white.withAlpha(80),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
              color: const Color(0xFF1A1A1A),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: thumb != null
                  ? RawImage(
                      image: thumb,
                      fit: BoxFit.cover,
                      width: 70,
                      height: 90,
                    )
                  : const Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white24,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            effect.label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF888888),
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WallpaperSheet — modal bottom sheet for wallpaper location
// ─────────────────────────────────────────────────────────────────────────────

class _WallpaperSheet extends StatelessWidget {
  final ValueChanged<int> onSelect;

  const _WallpaperSheet({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set Wallpaper',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose where to apply',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 20),

            _WallpaperOption(
              icon: Icons.home_outlined,
              label: 'Home Screen',
              onTap: () => onSelect(WallpaperService.homeScreen),
            ),
            const SizedBox(height: 10),
            _WallpaperOption(
              icon: Icons.lock_outline_rounded,
              label: 'Lock Screen',
              onTap: () => onSelect(WallpaperService.lockScreen),
            ),
            const SizedBox(height: 10),
            _WallpaperOption(
              icon: Icons.layers_outlined,
              label: 'Both',
              onTap: () => onSelect(WallpaperService.bothScreens),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _WallpaperOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _WallpaperOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A2A), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFF444444),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

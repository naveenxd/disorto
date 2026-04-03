import 'dart:async';
import 'dart:io';
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
  // ── Renderer ───────────────────────────────────────────────────────────────
  final EffectRenderer _renderer = EffectRenderer();

  // ── Source image (full-res, never mutated) ─────────────────────────────────
  ui.Image? _sourceImage;

  // ── Processing state ───────────────────────────────────────────────────────
  ui.Image? _previewImage;
  bool _initialising = true;

  // ── Controls ───────────────────────────────────────────────────────────────
  DistortionEffect _effect = DistortionEffect.original;
  double _blurValue = 0.0; // 0.0-1.0
  bool _isBlurDragging = false;

  // ── Thumbnail cache ────────────────────────────────────────────────────────
  // Keyed by DistortionEffect; generated at load time from a downscaled source.
  final Map<DistortionEffect, ui.Image?> _thumbs = {};
  ui.Image? _thumbSource; // downscaled source for thumbnail rendering
  final Map<int, ui.Image> _previewBlurBases = {};
  final Map<int, ui.Image> _thumbBlurBases = {};
  Timer? _blurDebounceTimer;
  int _renderGeneration = 0;

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
    _blurDebounceTimer?.cancel();
    _renderer.dispose();
    _previewImage?.dispose();
    _sourceImage?.dispose();
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
    // Load source image.
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodecFromBuffer(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    _sourceImage = frame.image;

    // Initialize renderer.
    await _renderer.init();

    // Build a downscaled copy for thumbnail rendering (~200px wide).
    _thumbSource = await _downscale(_sourceImage!, targetWidth: 200);
    _previewBlurBases[0] = await _renderer.prepareBlurredBase(
      source: _sourceImage!,
      blurValue: 0.0,
    );
    _thumbBlurBases[0] = await _renderer.prepareBlurredBase(
      source: _thumbSource!,
      blurValue: 0.0,
    );

    // Kick off thumbnail generation for all effects (non-blocking fire-and-forget).
    _generateThumbnails();
    _warmBlurCaches();

    await _rerender();

    if (mounted) setState(() => _initialising = false);
  }

  Future<void> _rerender() async {
    if (_sourceImage == null) return;
    final generation = ++_renderGeneration;
    ui.Image? transientBlurBase;
    try {
      final blurBaseResult = await _getPreviewEffectBase(_blurValue);
      final blurredBase = blurBaseResult.image;
      transientBlurBase = blurBaseResult.transient ? blurredBase : null;
      final rendered = await _renderer.render(
        source: _sourceImage!,
        blurredBase: blurredBase,
        effect: _effect,
        intensity: 1.0,
      );
      transientBlurBase?.dispose();
      transientBlurBase = null;
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
      transientBlurBase?.dispose();
      if (!mounted) return;
      _showSnack('Effect render failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Thumbnail generation (downscaled, all effects, background)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _generateThumbnails() async {
    if (_thumbSource == null) return;
    for (final effect in DistortionEffect.values) {
      if (!mounted) return;
      final blurredBase = await _getThumbEffectBase(0.0);
      final thumb = await _renderer.render(
        source: _thumbSource!,
        blurredBase: blurredBase,
        effect: effect,
        intensity: 1.0,
      );
      if (mounted) {
        setState(() => _thumbs[effect] = thumb);
      } else {
        thumb.dispose();
        return;
      }
    }
  }

  Future<void> _warmBlurCaches() async {
    if (_sourceImage == null || _thumbSource == null) return;
    for (final rawValue in [0.25, 0.5, 0.75, 1.0]) {
      if (!mounted) return;
      final eased = Curves.easeOutCubic.transform(rawValue);
      await _getPreviewBlurBaseForKey(_blurCacheKey(eased));
      await _getThumbBlurBaseForKey(_blurCacheKey(eased));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<ui.Image> _downscale(ui.Image src, {required int targetWidth}) async {
    final scale = targetWidth / src.width;
    final tw = targetWidth;
    final th = (src.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawImage(src, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final img = await picture.toImage(tw, th);
    picture.dispose();
    return img;
  }

  Future<String> _exportToTemp() async {
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/distorto_export_${DateTime.now().millisecondsSinceEpoch}.png';
    final blurBaseResult = await _getPreviewEffectBase(_blurValue);
    final blurredBase = blurBaseResult.image;
    final rendered = await _renderer.render(
      source: _sourceImage!,
      blurredBase: blurredBase,
      effect: _effect,
      intensity: 1.0,
    );
    if (blurBaseResult.transient) {
      blurredBase.dispose();
    }
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    await File(outPath).writeAsBytes(byteData!.buffer.asUint8List());
    return outPath;
  }

  int _blurCacheKey(double value) => (value.clamp(0.0, 1.0) * 100).round();

  Future<ui.Image> _getPreviewBlurBaseForKey(int key) async {
    final cached = _previewBlurBases[key];
    if (cached != null) return cached;

    final image = await _renderer.prepareBlurredBase(
      source: _sourceImage!,
      blurValue: key / 100.0,
    );
    _previewBlurBases[key] = image;
    return image;
  }

  Future<ui.Image> _getThumbBlurBaseForKey(int key) async {
    final cached = _thumbBlurBases[key];
    if (cached != null) return cached;

    final image = await _renderer.prepareBlurredBase(
      source: _thumbSource!,
      blurValue: key / 100.0,
    );
    _thumbBlurBases[key] = image;
    return image;
  }

  Future<({ui.Image image, bool transient})> _getPreviewEffectBase(
    double blurValue,
  ) async {
    final eased = Curves.easeOutCubic.transform(blurValue.clamp(0.0, 1.0));
    final position = eased * 100.0;
    final lowKey = position.floor().clamp(0, 100);
    final highKey = position.ceil().clamp(0, 100);
    final t = position - lowKey;
    final low = await _getPreviewBlurBaseForKey(lowKey);
    if (highKey == lowKey || t <= 0.0001) {
      return (image: low, transient: false);
    }
    final high = await _getPreviewBlurBaseForKey(highKey);
    final interpolated = await _lerpImage(low, high, t);
    return (image: interpolated, transient: true);
  }

  Future<ui.Image> _getThumbEffectBase(double blurValue) async {
    final eased = Curves.easeOutCubic.transform(blurValue.clamp(0.0, 1.0));
    return _getThumbBlurBaseForKey(_blurCacheKey(eased));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onEffectSelected(DistortionEffect effect) async {
    if (_effect == effect) return;
    setState(() => _effect = effect);
    await _rerender();
  }

  void _onBlurChanged(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((_blurValue - clamped).abs() < 0.0001) return;
    setState(() => _blurValue = clamped);
    _scheduleDebouncedRender();
  }

  void _onBlurDragStart(double _) {
    if (!_isBlurDragging) {
      setState(() => _isBlurDragging = true);
    }
  }

  void _onBlurDragEnd(double _) {
    if (_isBlurDragging) {
      setState(() => _isBlurDragging = false);
    }
    _scheduleDebouncedRender(immediate: true);
  }

  void _scheduleDebouncedRender({bool immediate = false}) {
    _blurDebounceTimer?.cancel();
    final delay = immediate ? Duration.zero : const Duration(milliseconds: 60);
    _blurDebounceTimer = Timer(delay, () {
      _rerender();
    });
  }

  Future<ui.Image> _lerpImage(ui.Image a, ui.Image b, double t) async {
    final width = a.width;
    final height = a.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.drawImage(a, Offset.zero, Paint());
    canvas.drawImage(
      b,
      Offset.zero,
      Paint()..color = Color.fromRGBO(255, 255, 255, t.clamp(0.0, 1.0)),
    );
    final picture = recorder.endRecording();
    final blended = await picture.toImage(width, height);
    picture.dispose();
    return blended;
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
    if (_saving || _sourceImage == null) return;
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
    if (_wallpapering || _sourceImage == null) return;
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
              previewImage: _previewImage,
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
                blurValue: _blurValue,
                isDraggingBlur: _isBlurDragging,
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
  final DistortionEffect selectedEffect;
  final Map<DistortionEffect, ui.Image?> thumbs;
  final ValueChanged<double> onBlurChanged;
  final ValueChanged<double> onBlurChangeStart;
  final ValueChanged<double> onBlurChangeEnd;
  final ValueChanged<DistortionEffect> onEffectSelected;

  const _BottomPanel({
    required this.blurValue,
    required this.isDraggingBlur,
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
            onChanged: onBlurChanged,
            onChangeStart: onBlurChangeStart,
            onChangeEnd: onBlurChangeEnd,
          ),

          const SizedBox(height: 20),

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
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  const _BlurSection({
    required this.blurValue,
    required this.isDragging,
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
              Text(
                '${(blurValue.clamp(0.0, 1.0) * 100).round()}%',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BlurSlider(
            value: blurValue,
            isDragging: isDragging,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _BlurSlider extends StatelessWidget {
  final double value;
  final bool isDragging;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  const _BlurSlider({
    required this.value,
    required this.isDragging,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: isDragging ? 1.015 : 1.0,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: isDragging ? 1.0 : 0.95,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.0,
            activeTrackColor: Colors.white,
            inactiveTrackColor: const Color(0xFF333333),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withAlpha(28),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: null,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ),
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

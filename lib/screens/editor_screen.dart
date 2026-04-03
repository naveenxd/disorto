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
  final ShaderProgramCache _shaderProgramCache = ShaderProgramCache();

  // ── Source image (full-res, never mutated) ─────────────────────────────────
  ui.Image? _sourceImage;

  // ── Processing state ───────────────────────────────────────────────────────
  ui.Image? _previewBlurImage;
  ui.FragmentShader? _previewShader;
  bool _rendering = false;
  bool _initialising = true;

  // ── Controls ───────────────────────────────────────────────────────────────
  DistortionEffect _effect = DistortionEffect.original;
  int _blurLevel = 0; // 0-4

  // ── Thumbnail cache ────────────────────────────────────────────────────────
  // Keyed by DistortionEffect; generated at load time from a downscaled source.
  final Map<DistortionEffect, ui.Image?> _thumbs = {};
  ui.Image? _thumbSource; // downscaled source for thumbnail rendering
  final Map<int, ui.Image> _previewBlurBases = {};
  final Map<int, ui.Image> _thumbBlurBases = {};

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
    _renderer.dispose();
    _shaderProgramCache.dispose();
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

    // Pre-warm shaders.
    await _renderer.init();
    await _shaderProgramCache.init();

    // Build a downscaled copy for thumbnail rendering (~200px wide).
    _thumbSource = await _downscale(_sourceImage!, targetWidth: 200);
    _previewBlurBases[0] = await _renderer.prepareBlurredBase(
      source: _sourceImage!,
      blurLevel: 0,
    );
    _thumbBlurBases[0] = await _renderer.prepareBlurredBase(
      source: _thumbSource!,
      blurLevel: 0,
    );

    // Kick off thumbnail generation for all effects (non-blocking fire-and-forget).
    _generateThumbnails();
    _warmBlurCaches();

    await _rerender();

    if (mounted) setState(() => _initialising = false);
  }

  Future<void> _rerender() async {
    if (_sourceImage == null) return;
    setState(() => _rendering = true);
    try {
      final blurredBase = await _getPreviewEffectBase(_effect, _blurLevel);
      final program = await _shaderProgramCache.loadProgram(_effect);
      final shader = program?.fragmentShader();
      if (!mounted) return;
      setState(() {
        _previewBlurImage = blurredBase;
        _previewShader = shader;
        _rendering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rendering = false);
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
      final blurredBase = await _getThumbEffectBase(effect, 0);
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
    for (final level in [1, 2, 3, 4]) {
      if (!mounted) return;
      await _getPreviewBlurBase(level);
      await _getThumbBlurBase(level);
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
    final blurredBase = await _getPreviewEffectBase(_effect, _blurLevel);
    final rendered = await _renderer.render(
      source: _sourceImage!,
      blurredBase: blurredBase,
      effect: _effect,
      intensity: 1.0,
    );
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    await File(outPath).writeAsBytes(byteData!.buffer.asUint8List());
    return outPath;
  }

  Future<ui.Image> _getPreviewBlurBase(int level) async {
    final cached = _previewBlurBases[level];
    if (cached != null) return cached;

    final image = await _renderer.prepareBlurredBase(
      source: _sourceImage!,
      blurLevel: level,
    );
    _previewBlurBases[level] = image;
    return image;
  }

  Future<ui.Image> _getThumbBlurBase(int level) async {
    final cached = _thumbBlurBases[level];
    if (cached != null) return cached;

    final image = await _renderer.prepareBlurredBase(
      source: _thumbSource!,
      blurLevel: level,
    );
    _thumbBlurBases[level] = image;
    return image;
  }

  Future<ui.Image> _getPreviewEffectBase(
    DistortionEffect effect,
    int blurLevel,
  ) async {
    return _getPreviewBlurBase(blurLevel);
  }

  Future<ui.Image> _getThumbEffectBase(
    DistortionEffect effect,
    int blurLevel,
  ) async {
    return _getThumbBlurBase(blurLevel);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onEffectSelected(DistortionEffect effect) async {
    if (_effect == effect) return;
    setState(() => _effect = effect);
    await _rerender();
  }

  Future<void> _onBlurChanged(int level) async {
    if (_blurLevel == level) return;
    setState(() => _blurLevel = level);
    await _rerender();
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
              sourceImage: _sourceImage,
              blurImage: _previewBlurImage,
              effect: _effect,
              shader: _previewShader,
              initialising: _initialising,
              rendering: _rendering,
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
                blurLevel: _blurLevel,
                selectedEffect: _effect,
                thumbs: _thumbs,
                onBlurChanged: _onBlurChanged,
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
  final ui.Image? sourceImage;
  final ui.Image? blurImage;
  final DistortionEffect effect;
  final ui.FragmentShader? shader;
  final bool initialising;
  final bool rendering;

  const _PreviewPane({
    required this.sourceImage,
    required this.blurImage,
    required this.effect,
    required this.shader,
    required this.initialising,
    required this.rendering,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: initialising
            ? const _LoadingPlaceholder(key: ValueKey('loading'))
            : sourceImage != null && blurImage != null
            ? _ImageDisplay(
                key: ValueKey(
                  '${sourceImage.hashCode}-${blurImage.hashCode}-${effect.index}',
                ),
                sourceImage: sourceImage!,
                blurImage: blurImage!,
                effect: effect,
                shader: shader,
              )
            : const _LoadingPlaceholder(key: ValueKey('blank')),
      ),
    );
  }
}

class _ImageDisplay extends StatelessWidget {
  final ui.Image sourceImage;
  final ui.Image blurImage;
  final DistortionEffect effect;
  final ui.FragmentShader? shader;

  const _ImageDisplay({
    super.key,
    required this.sourceImage,
    required this.blurImage,
    required this.effect,
    required this.shader,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: sourceImage.width.toDouble(),
          height: sourceImage.height.toDouble(),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ShaderPreviewPainter(
                sourceImage: sourceImage,
                blurImage: blurImage,
                effect: effect,
                intensity: 1.0,
                shader: shader,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShaderPreviewPainter extends CustomPainter {
  const _ShaderPreviewPainter({
    required this.sourceImage,
    required this.blurImage,
    required this.effect,
    required this.intensity,
    required this.shader,
  });

  final ui.Image sourceImage;
  final ui.Image blurImage;
  final DistortionEffect effect;
  final double intensity;
  final ui.FragmentShader? shader;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final activeShader = shader;
    const timeSeconds = 0.0;

    if (effect == DistortionEffect.original || activeShader == null) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: blurImage,
        fit: BoxFit.fill,
      );
      return;
    }

    activeShader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, intensity)
      ..setFloat(3, timeSeconds)
      ..setImageSampler(0, sourceImage)
      ..setImageSampler(1, blurImage);

    canvas.drawRect(rect, Paint()..shader = activeShader);
  }

  @override
  bool shouldRepaint(covariant _ShaderPreviewPainter oldDelegate) {
    return oldDelegate.sourceImage != sourceImage ||
        oldDelegate.blurImage != blurImage ||
        oldDelegate.effect != effect ||
        oldDelegate.intensity != intensity ||
        oldDelegate.shader != shader;
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
  final int blurLevel;
  final DistortionEffect selectedEffect;
  final Map<DistortionEffect, ui.Image?> thumbs;
  final ValueChanged<int> onBlurChanged;
  final ValueChanged<DistortionEffect> onEffectSelected;

  const _BottomPanel({
    required this.blurLevel,
    required this.selectedEffect,
    required this.thumbs,
    required this.onBlurChanged,
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
          _BlurSection(blurLevel: blurLevel, onChanged: onBlurChanged),

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
  final int blurLevel;
  final ValueChanged<int> onChanged;

  const _BlurSection({required this.blurLevel, required this.onChanged});

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
                blurLevel == 0 ? 'Off' : '$blurLevel',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DotSlider(value: blurLevel, max: 4, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── 5-step discrete dot slider ────────────────────────────────────────────────

class _DotSlider extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _DotSlider({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _updateFromDx(details.localPosition.dx, context),
      onHorizontalDragUpdate: (details) =>
          _updateFromDx(details.localPosition.dx, context),
      child: SizedBox(
        height: 36,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Track line.
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                // Active track.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 2,
                    width: max == 0 ? 0 : w * value / max,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                // Step dots.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(max + 1, (i) {
                    final active = i <= value;
                    final current = i == value;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: current ? 18 : 10,
                      height: current ? 18 : 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? Colors.white : const Color(0xFF333333),
                        boxShadow: current
                            ? [
                                BoxShadow(
                                  color: Colors.white.withAlpha(80),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _updateFromDx(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final w = box.size.width;
    final stepped = (dx / w * max).round().clamp(0, max);
    onChanged(stepped);
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

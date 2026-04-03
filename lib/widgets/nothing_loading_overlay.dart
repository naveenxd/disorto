import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class NothingLoadingOverlay extends StatefulWidget {
  final ImageProvider backgroundImage;
  final Duration duration;
  final double gridSpacing;
  final double dotDiameter;
  final double frequency;
  final double speed;
  final double phaseOffset;
  final double waveFalloff;

  const NothingLoadingOverlay({
    super.key,
    required this.backgroundImage,
    this.duration = const Duration(milliseconds: 2400),
    this.gridSpacing = 14,
    this.dotDiameter = 1.4,
    this.frequency = 0.015,
    this.speed = 6.0,
    this.phaseOffset = 0.02,
    this.waveFalloff = 0.000035,
  });

  @override
  State<NothingLoadingOverlay> createState() => _NothingLoadingOverlayState();
}

class _NothingLoadingOverlayState extends State<NothingLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _NothingDotGridPainter _painter;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _painter = _NothingDotGridPainter(
      progress: _controller,
      gridSpacing: widget.gridSpacing,
      dotDiameter: widget.dotDiameter,
      frequency: widget.frequency,
      speed: widget.speed,
      phaseOffset: widget.phaseOffset,
      waveFalloff: widget.waveFalloff,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: widget.backgroundImage,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.8)),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.08,
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.03),
                Colors.white.withValues(alpha: 0.07),
              ],
              stops: const [0.0, 0.58, 0.84, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: _painter,
            isComplex: true,
            willChange: true,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _NothingDotGridPainter extends CustomPainter {
  final Animation<double> progress;
  final double gridSpacing;
  final double dotDiameter;
  final double frequency;
  final double speed;
  final double phaseOffset;
  final double waveFalloff;

  final Paint _dotPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  Size _lastSize = Size.zero;
  final List<Offset> _dots = <Offset>[];

  _NothingDotGridPainter({
    required this.progress,
    required this.gridSpacing,
    required this.dotDiameter,
    required this.frequency,
    required this.speed,
    required this.phaseOffset,
    required this.waveFalloff,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (size != _lastSize) {
      _rebuildGrid(size);
    }

    final double time = progress.value;
    final double radius = dotDiameter * 0.5;
    final double height = size.height;
    final double waveFront = height * (1.0 - time);

    for (int i = 0; i < _dots.length; i++) {
      final Offset dot = _dots[i];
      final double yFromBottom = height - dot.dy;
      final double dist = yFromBottom - waveFront;
      final double wave = math.exp(-(dist * dist) * waveFalloff);

      double opacity = 0.08 + (wave * 0.82);

      final double verticalFade = 0.78 + ((dot.dy / height) * 0.34);
      opacity *= verticalFade;
      if (opacity > 1.0) opacity = 1.0;

      _dotPaint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(dot, radius, _dotPaint);
    }
  }

  void _rebuildGrid(Size size) {
    _dots.clear();
    final double spacing = gridSpacing;

    final double colCount = (size.width / spacing).floorToDouble();
    final double rowCount = (size.height / spacing).floorToDouble();

    final double usedWidth = colCount * spacing;
    final double usedHeight = rowCount * spacing;

    final double xStart = (size.width - usedWidth) * 0.5;
    final double yStart = (size.height - usedHeight) * 0.5;

    for (double y = yStart; y <= size.height - yStart; y += spacing) {
      for (double x = xStart; x <= size.width - xStart; x += spacing) {
        _dots.add(Offset(x, y));
      }
    }

    _lastSize = size;
  }

  @override
  bool shouldRepaint(covariant _NothingDotGridPainter oldDelegate) => true;
}

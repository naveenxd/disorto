import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'editor_screen.dart';
import '../widgets/nothing_loading_overlay.dart';

Route<void> buildLoaderRoute(File image) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) =>
        LoaderScreen(image: image),
  );
}

class LoaderScreen extends StatefulWidget {
  final File image;

  const LoaderScreen({super.key, required this.image});

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> {
  static const Duration _minimumVisibleTime = Duration(milliseconds: 600);

  late final Stopwatch _sw;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final result = await prepareInitialState(widget.image);
      final elapsed = _sw.elapsed;
      if (elapsed < _minimumVisibleTime) {
        await Future<void>.delayed(_minimumVisibleTime - elapsed);
      }
      if (!mounted) {
        result.previewImage.dispose();
        result.previewSource.dispose();
        for (final image in result.previewBlurBases.values) {
          image.dispose();
        }
        result.renderer.dispose();
        return;
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              EditorScreen(data: result),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
              child: child,
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: NothingLoadingOverlay(
              backgroundImage: FileImage(widget.image),
            ),
          ),
          if (_error != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(170),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withAlpha(32)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to prepare editor: $_error',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

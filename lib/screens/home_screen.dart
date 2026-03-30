import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'editor_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _picking = false;
  late final AnimationController _wordmarkCtrl;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<Offset> _wordmarkSlide;
  late final Animation<double> _buttonOpacity;

  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Entrance animation — wordmark fades + slides up, button fades in after.
    _wordmarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _wordmarkOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _wordmarkCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _wordmarkSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _wordmarkCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _buttonOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _wordmarkCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _wordmarkCtrl.forward();

    // Warm-start share intent — if the app was already running and the user
    // shares a new image, we receive it here.
    _intentSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedFiles, onError: (_) {});
  }

  @override
  void dispose() {
    _wordmarkCtrl.dispose();
    _intentSub?.cancel();
    super.dispose();
  }

  // ── Intent handling ────────────────────────────────────────────────────────

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (!mounted || files.isEmpty) return;
    final image = files.firstWhere(
      (f) => f.type == SharedMediaType.image,
      orElse: () => files.first,
    );
    ReceiveSharingIntent.instance.reset();
    _navigateToEditor(image.path);
  }

  // ── Image picker ───────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        // We always export at original resolution (see context §Export).
        imageQuality: 100,
      );

      if (picked != null && mounted) {
        _navigateToEditor(picked.path);
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _navigateToEditor(String path) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            EditorScreen(imagePath: path),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              // Top spacer — pushes wordmark into the visual upper-third.
              const Spacer(flex: 3),

              // ── Wordmark + tagline ──────────────────────────────────────
              FadeTransition(
                opacity: _wordmarkOpacity,
                child: SlideTransition(
                  position: _wordmarkSlide,
                  child: const _Wordmark(),
                ),
              ),

              const Spacer(flex: 4),

              // ── Select Wallpaper button ─────────────────────────────────
              FadeTransition(
                opacity: _buttonOpacity,
                child: _SelectButton(
                  loading: _picking,
                  onTap: _pickImage,
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Wordmark
// ─────────────────────────────────────────────────────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App name.
        const Text(
          'distorto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 52,
            fontWeight: FontWeight.w800,
            letterSpacing: -3.0,
            height: 1.0,
          ),
        ),

        const SizedBox(height: 12),

        // Tagline — muted, minimal.
        Text(
          'OS-style wallpaper effects\nfor every phone.',
          style: TextStyle(
            color: Colors.white.withAlpha(120),
            fontSize: 15,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.2,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SelectButton
// ─────────────────────────────────────────────────────────────────────────────

class _SelectButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onTap;

  const _SelectButton({required this.loading, required this.onTap});

  @override
  State<_SelectButton> createState() => _SelectButtonState();
}

class _SelectButtonState extends State<_SelectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _hoverCtrl.forward(),
      onTapUp: (_) {
        _hoverCtrl.reverse();
        if (!widget.loading) widget.onTap();
      },
      onTapCancel: () => _hoverCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.loading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF0A0A0A),
                    ),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.photo_library_outlined,
                        color: Color(0xFF0A0A0A),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Select Wallpaper',
                        style: TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

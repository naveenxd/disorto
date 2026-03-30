import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait — wallpaper apps are always portrait.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Draw content edge-to-edge (behind status bar + nav bar).
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const DistortoApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Root app widget
// ─────────────────────────────────────────────────────────────────────────────

class DistortoApp extends StatelessWidget {
  const DistortoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'distorto',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,

      // ── Dark theme ──────────────────────────────────────────────────────────
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,

        // Near-black background per design spec (#0A0A0A).
        colorScheme: ColorScheme.dark(
          surface: const Color(0xFF0A0A0A),
          onSurface: Colors.white,
          primary: Colors.white,
          onPrimary: const Color(0xFF0A0A0A),
          secondary: const Color(0xFF1E1E1E),
          onSecondary: Colors.white,
          surfaceContainerHighest: const Color(0xFF1A1A1A),
        ),

        scaffoldBackgroundColor: const Color(0xFF0A0A0A),

        // Typography — clean, modern; matches "DM Sans / Space Grotesk" feel.
        // (Google Fonts added later; for now we use the system sans-serif.)
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
          titleLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          bodyMedium: TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 14,
          ),
          labelSmall: TextStyle(
            color: Color(0xFF888888),
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),

        // AppBar — blends into the dark background.
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),

        // Bottom sheets — dark glass surface.
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF111111),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),

        // Sliders.
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.white,
          inactiveTrackColor: Color(0xFF333333),
          thumbColor: Colors.white,
          overlayColor: Color(0x22FFFFFF),
        ),

        // Icon buttons.
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),

        // Page transitions — subtle fade+slide.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),

      // The splash screen widget resolves the initial route.
      home: const _AppShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AppShell — resolves the startup route
//
// Handles cold-start share intent: if the OS launched this app because the
// user shared an image from the gallery, _AppShell detects it via
// ReceiveSharingIntent.getInitialMedia() and navigates straight to
// EditorScreen, bypassing HomeScreen entirely.
//
// After the initial intent is consumed (reset()), warm-start shares are
// handled by the stream listener inside HomeScreen itself.
// ─────────────────────────────────────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  // Whether we have finished checking for a cold-start share intent.
  bool _resolved = false;

  // Non-null when a shared image was found on cold start.
  String? _sharedImagePath;

  @override
  void initState() {
    super.initState();
    _resolveInitialIntent();
  }

  // ── Cold-start share intent ─────────────────────────────────────────────────

  Future<void> _resolveInitialIntent() async {
    try {
      final files = await ReceiveSharingIntent.instance.getInitialMedia();

      if (files.isNotEmpty) {
        // Find the first image-type file.
        final image = files.firstWhere(
          (f) => f.type == SharedMediaType.image,
          orElse: () => files.first,
        );

        // Tell the plugin we handled the intent — prevents re-trigger on resume.
        ReceiveSharingIntent.instance.reset();

        if (mounted) {
          setState(() {
            _sharedImagePath = image.path;
            _resolved = true;
          });
        }
        return;
      }
    } catch (_) {
      // If the plugin throws (e.g. platform channel not ready), fall through
      // to HomeScreen gracefully.
    }

    if (mounted) {
      setState(() => _resolved = true);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show a minimal dark splash until we know the initial route.
    if (!_resolved) {
      return const _SplashScreen();
    }

    // Cold-start share detected → go straight to editor.
    if (_sharedImagePath != null) {
      return EditorScreen(imagePath: _sharedImagePath!);
    }

    // Normal launch → show home.
    return const HomeScreen();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SplashScreen
//
// Displayed for the brief moment while getInitialMedia() resolves (~1 frame).
// Matches the dark theme so there is no white flash on startup.
// ─────────────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: Center(
        child: _DistortoWordmark(),
      ),
    );
  }
}

// Simple animated wordmark shown during splash.
class _DistortoWordmark extends StatefulWidget {
  const _DistortoWordmark();

  @override
  State<_DistortoWordmark> createState() => _DistortoWordmarkState();
}

class _DistortoWordmarkState extends State<_DistortoWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: const Text(
        'distorto',
        style: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ),
      ),
    );
  }
}

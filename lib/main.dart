import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_database.dart';
import 'bg_photo.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  // Catch errors that escape Flutter so the app never dies silently.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    // Scoring is designed for portrait.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    // Open the UI immediately; the database loads behind a splash screen.
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'C Crushers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey.shade50,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle:
              TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        // smoother page transitions on every platform
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Shows a splash while the database opens, then fades into HomeScreen.
/// If the database fails, shows a Retry screen instead of a blank page.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // keep the splash visible for a moment so it never just flashes
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 2000));
    try {
      await AppDatabase.instance;
      await minSplash;
      if (!mounted) return;
      setState(() {
        _error = null;
        _ready = true;
      });
    } catch (e, st) {
      debugPrint('Database init failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _ready = false;
    });
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      child: _error != null
          ? _ErrorView(key: const ValueKey('error'), error: _error!, onRetry: _retry)
          : _ready
              ? const KeyedSubtree(key: ValueKey('home'), child: HomeScreen())
              : const _Splash(key: ValueKey('splash')),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF111B3A), Color(0xFF1F3C88)],
            ),
          ),
          child: SmokyPhotoBackground(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v.clamp(0.0, 1.2).toDouble(), child: child),
                  child: Container(
                    height: 112,
                    width: 112,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.5),
                            blurRadius: 34,
                            spreadRadius: 2),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Text('C',
                            style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontStyle: FontStyle.italic)),
                        Positioned(
                          bottom: 14,
                          right: 14,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                                color: Colors.orangeAccent, shape: BoxShape.circle),
                            child: const Icon(Icons.sports_cricket,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                        offset: Offset(0, 14 * (1 - v)), child: child),
                  ),
                  child: const Column(
                    children: [
                      Text('C Crushers',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2)),
                      SizedBox(height: 6),
                      Text('LIVE CRICKET SCORING',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3)),
                    ],
                  ),
                ),
                const SizedBox(height: 44),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.lightGreenAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.storage_rounded, color: Colors.redAccent, size: 48),
              ),
              const SizedBox(height: 18),
              const Text('Could not open the database',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                kDebugMode ? '$error' : 'Please try again. If it keeps happening, restart the app.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Try again',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  SMOKY PHOTO BACKGROUND
//  Faint, smoky team logo behind any screen.
//  Use it anywhere:   SmokyPhotoBackground(child: yourScreenContent)
//  (from another file:  import '../main.dart';)
//  Logo lives in lib/bg_photo.dart (base64 PNG)
// ============================================================================
final Uint8List kBgPhotoBytes = base64Decode(kBgPhotoBase64);

class SmokyPhotoBackground extends StatefulWidget {
  final Widget child;
  final double opacity; // how visible the photo is (0.0 - 1.0)
  final Color tint; // colour the photo fades into
  const SmokyPhotoBackground({
    super.key,
    required this.child,
    this.opacity = 0.30,
    this.tint = const Color(0xFF111B3A),
  });

  @override
  State<SmokyPhotoBackground> createState() => _SmokyPhotoBackgroundState();
}

class _SmokyPhotoBackgroundState extends State<SmokyPhotoBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // team logo: soft glow behind it + faint, centred in the lower-middle
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.35),
              child: FractionallySizedBox(
                widthFactor: 0.82,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.10 * widget.opacity / 0.3),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                      Opacity(
                        // logo is dark blue, so it needs a bit more strength than a photo
                        opacity: (widget.opacity * 1.7).clamp(0.0, 1.0).toDouble(),
                        child: Image.memory(
                          kBgPhotoBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // vignette: edges melt into the background colour
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.2),
                  radius: 1.1,
                  colors: [Colors.transparent, widget.tint.withOpacity(0.7)],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),
        ),
        // drifting smoke
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _SmokePainter(_ctrl)),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _SmokePainter extends CustomPainter {
  final Animation<double> anim;
  _SmokePainter(this.anim) : super(repaint: anim);

  // x, y (0..1), radius (x shortest side), speed, phase
  static const List<List<double>> _blobs = [
    [0.20, 0.25, 0.55, 1.0, 0.0],
    [0.80, 0.35, 0.50, 1.0, 1.7],
    [0.45, 0.55, 0.65, 2.0, 3.1],
    [0.15, 0.75, 0.50, 1.0, 4.4],
    [0.85, 0.80, 0.55, 2.0, 5.6],
    [0.55, 0.10, 0.45, 1.0, 2.4],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final base = anim.value * 2 * math.pi;
    for (final b in _blobs) {
      final t = base * b[3] + b[4];
      final c = Offset(
        size.width * (b[0] + 0.10 * math.sin(t)),
        size.height * (b[1] + 0.06 * math.cos(t * 0.8)),
      );
      final r = size.shortestSide * b[2] * (1 + 0.12 * math.sin(t * 1.3));
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withOpacity(0.11), Colors.white.withOpacity(0.0)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SmokePainter old) => false;
}
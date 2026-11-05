import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Logo in the background with living fire behind it:
///  - pulsing heat aura
///  - flames that rise from behind the logo and fade into smoke
///  - glowing orange rim that flickers around the logo shape
///  - small embers floating up over the whole screen
///
/// Usage:
///   FireLogoBackground(
///     logo: const AssetImage('assets/images/logo.png'),
///     child: SafeArea(...your screen...),
///   )
class FireLogoBackground extends StatefulWidget {
  final ImageProvider logo;
  final Widget child;

  /// how visible the logo itself is (0..1)
  final double logoOpacity;

  /// logo width as a fraction of the screen width
  final double logoWidthFactor;

  /// where the logo sits (Alignment(0, 0.6) = a bit below the middle)
  final Alignment logoAlignment;

  /// 0..1  - amount of fire / embers
  final double intensity;

  const FireLogoBackground({
    super.key,
    required this.logo,
    required this.child,
    this.logoOpacity = 0.55,
    this.logoWidthFactor = 0.74,
    this.logoAlignment = const Alignment(0, 0.62),
    this.intensity = 1.0,
  });

  @override
  State<FireLogoBackground> createState() => _FireLogoBackgroundState();
}

class _FireLogoBackgroundState extends State<FireLogoBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // everything below uses whole-number cycles of this loop => seamless
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _flicker() {
    final t = _ctrl.value * 2 * math.pi;
    final f = math.sin(t * 3) * 0.5 + math.sin(t * 7 + 1.3) * 0.3 + math.sin(t * 11 + 0.4) * 0.2;
    return 0.5 + 0.5 * f; // 0..1
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final size = math.min(w * widget.logoWidthFactor, h * 0.5);
      final rect = Rect.fromLTWH(
        (w - size) / 2 * (1 + widget.logoAlignment.x),
        (h - size) / 2 * (1 + widget.logoAlignment.y),
        size,
        size,
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          // fire behind the logo
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FirePainter(_ctrl, rect, widget.intensity, embersOnly: false),
                ),
              ),
            ),
          ),

          // logo with flickering glow
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final f = _flicker();
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // glowing rim (orange silhouette, blurred)
                      Opacity(
                        opacity: (0.30 + 0.45 * f) * widget.intensity.clamp(0.0, 1.0),
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: ColorFiltered(
                            colorFilter:
                                const ColorFilter.mode(Color(0xFFFF7A18), BlendMode.srcATop),
                            child: Image(image: widget.logo, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      // the logo itself, warmed by the fire
                      Opacity(
                        opacity: widget.logoOpacity,
                        child: Transform.scale(
                          scale: 1.0 + 0.012 * f,
                          child: ColorFiltered(
                            colorFilter: ColorFilter.mode(
                                const Color(0xFFFF8A00).withOpacity(0.10 + 0.14 * f),
                                BlendMode.srcATop),
                            child: Image(image: widget.logo, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // embers floating over everything
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FirePainter(_ctrl, rect, widget.intensity, embersOnly: true),
                ),
              ),
            ),
          ),

          widget.child,
        ],
      );
    });
  }
}

// ----------------------------------------------------------------------------
class _Flame {
  final double sx, sy, travel, phase, r, sway, swayPh;
  final int cycles, swayK;
  _Flame(math.Random rnd)
      : sx = _edgeBiased(rnd),
        sy = 0.40 + rnd.nextDouble() * 0.60,
        travel = 0.45 + rnd.nextDouble() * 0.65,
        phase = rnd.nextDouble(),
        r = 0.07 + rnd.nextDouble() * 0.10,
        sway = 0.02 + rnd.nextDouble() * 0.05,
        swayPh = rnd.nextDouble() * math.pi * 2,
        cycles = 2 + rnd.nextInt(3),
        swayK = 1 + rnd.nextInt(3);

  // more fire at the sides & middle of the logo than anywhere else
  static double _edgeBiased(math.Random r) {
    final k = r.nextDouble();
    if (k < 0.35) return 0.02 + r.nextDouble() * 0.22; // left
    if (k < 0.70) return 0.76 + r.nextDouble() * 0.22; // right
    return 0.25 + r.nextDouble() * 0.5; // middle
  }
}

class _Ember {
  final double sx, sy, travel, phase, r, sway, swayPh, twinkle;
  final int cycles, swayK, twinkleK;
  _Ember(math.Random rnd)
      : sx = -0.1 + rnd.nextDouble() * 1.2,
        sy = 0.30 + rnd.nextDouble() * 0.70,
        travel = 0.25 + rnd.nextDouble() * 0.55,
        phase = rnd.nextDouble(),
        r = 0.8 + rnd.nextDouble() * 1.8,
        sway = 0.02 + rnd.nextDouble() * 0.06,
        swayPh = rnd.nextDouble() * math.pi * 2,
        twinkle = rnd.nextDouble() * math.pi * 2,
        cycles = 1 + rnd.nextInt(3),
        swayK = 1 + rnd.nextInt(4),
        twinkleK = 6 + rnd.nextInt(10);
}

class _FirePainter extends CustomPainter {
  final Animation<double> anim;
  final Rect logo;
  final double intensity;
  final bool embersOnly;

  _FirePainter(this.anim, this.logo, this.intensity, {required this.embersOnly})
      : super(repaint: anim);

  static final List<_Flame> _flames = (() {
    final r = math.Random(21);
    return List<_Flame>.generate(58, (_) => _Flame(r));
  })();
  static final List<_Ember> _embers = (() {
    final r = math.Random(9);
    return List<_Ember>.generate(34, (_) => _Ember(r));
  })();

  static const Color _yellow = Color(0xFFFFE066);
  static const Color _orange = Color(0xFFFF8A1F);
  static const Color _red = Color(0xFFD7261E);
  static const Color _smoke = Color(0xFF5A1630);

  Color _flameColor(double p) {
    if (p < 0.3) return Color.lerp(_yellow, _orange, p / 0.3)!;
    if (p < 0.7) return Color.lerp(_orange, _red, (p - 0.3) / 0.4)!;
    return Color.lerp(_red, _smoke, (p - 0.7) / 0.3)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    final k = intensity.clamp(0.0, 1.0);
    if (k <= 0) return;
    final t = v * 2 * math.pi;
    final flick =
        0.5 + 0.5 * (math.sin(t * 3) * 0.5 + math.sin(t * 7 + 1.3) * 0.3 + math.sin(t * 11 + 0.4) * 0.2);

    if (!embersOnly) {
      // ---- heat aura
      final c = logo.center;
      final auraR = logo.width * (0.78 + 0.06 * flick);
      canvas.drawCircle(
        c,
        auraR,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            c,
            auraR,
            [
              const Color(0xFFFF6A00).withOpacity((0.16 + 0.10 * flick) * k),
              const Color(0xFFB3141E).withOpacity(0.07 * k),
              const Color(0x00B3141E),
            ],
            const [0.0, 0.55, 1.0],
          ),
      );

      // ---- fire glow along the bottom edge of the logo
      final base = Offset(logo.center.dx, logo.bottom - logo.height * 0.04);
      final br = logo.width * 0.62;
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.scale(1.0, 0.32);
      canvas.drawCircle(
        Offset.zero,
        br,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset.zero,
            br,
            [
              const Color(0xFFFFA43A).withOpacity((0.30 + 0.18 * flick) * k),
              const Color(0x00FF4A1A),
            ],
          ),
      );
      canvas.restore();

      // ---- flames
      final n = (_flames.length * k).round();
      for (int i = 0; i < n; i++) {
        final f = _flames[i];
        final p = (v * f.cycles + f.phase) % 1.0;
        final x = logo.left +
            logo.width * f.sx +
            math.sin(2 * math.pi * v * f.swayK + f.swayPh + p * 5) *
                f.sway *
                logo.width *
                (0.4 + p);
        final y = logo.top + logo.height * f.sy - f.travel * logo.height * p;
        final r = f.r * logo.width * (1.0 - 0.72 * p) * (0.85 + 0.3 * flick);
        final fade = p < 0.12 ? p / 0.12 : (1 - p) / 0.88;
        final a = (fade * 0.55 * k).clamp(0.0, 1.0);
        final col = _flameColor(p);
        canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()
            ..blendMode = p > 0.75 ? BlendMode.srcOver : BlendMode.plus
            ..shader = ui.Gradient.radial(
              Offset(x, y),
              r,
              [col.withOpacity(a), col.withOpacity(0)],
            ),
        );
      }
    } else {
      // ---- embers
      final n = (_embers.length * k).round();
      for (int i = 0; i < n; i++) {
        final e = _embers[i];
        final p = (v * e.cycles + e.phase) % 1.0;
        final x = logo.left +
            logo.width * e.sx +
            math.sin(2 * math.pi * v * e.swayK + e.swayPh + p * 6) * e.sway * size.width;
        final y = logo.top + logo.height * e.sy - e.travel * size.height * p;
        final tw = 0.55 + 0.45 * math.sin(2 * math.pi * v * e.twinkleK + e.twinkle);
        final fade = p < 0.1 ? p / 0.1 : (1 - p) / 0.9;
        final a = (fade * tw * k).clamp(0.0, 1.0);
        final r = e.r * (1 - 0.5 * p);
        final col = Color.lerp(const Color(0xFFFFD27A), const Color(0xFFFF6A1A), p)!;
        canvas.drawCircle(
          Offset(x, y),
          r * 3.2,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(
              Offset(x, y),
              r * 3.2,
              [col.withOpacity(0.35 * a), col.withOpacity(0)],
            ),
        );
        canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col.withOpacity(0.95 * a),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FirePainter old) =>
      old.logo != logo || old.intensity != intensity || old.embersOnly != embersOnly;
}
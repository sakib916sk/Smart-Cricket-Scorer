import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import '../pdf_report.dart';
import '../team_gallery.dart';
import '../app_database.dart';
import 'package:path_provider/path_provider.dart';
import '../highlights.dart'; // 🔥 Highlights এর জন্য ইমপোর্ট

// ============================================================================
//  MODELS
// ============================================================================

enum _BallKind { dot, run, four, six, wicket, wide, noBall, bye, legBye }

class _Ball {
  final String label;
  final int runs; // team total e add hobe
  final int bowlerRuns; // bowler er khate jabe
  final bool legal;
  final _BallKind kind;
  const _Ball({
    required this.label,
    required this.runs,
    required this.bowlerRuns,
    required this.legal,
    required this.kind,
  });
}

class _Over {
  final String bowler;
  final List<_Ball> balls;
  final int runs;
  final bool maiden;
  const _Over(this.bowler, this.balls, this.runs, this.maiden);
}

class _BatStat {
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  String? out;
  double get sr => balls == 0 ? 0 : runs * 100 / balls;
  _BatStat copy() => _BatStat()
    ..runs = runs
    ..balls = balls
    ..fours = fours
    ..sixes = sixes
    ..out = out;
}

class _BowlStat {
  int legalBalls = 0, runs = 0, wickets = 0, maidens = 0;
  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get econ => legalBalls == 0 ? 0 : runs * 6 / legalBalls;
  _BowlStat copy() => _BowlStat()
    ..legalBalls = legalBalls
    ..runs = runs
    ..wickets = wickets
    ..maidens = maidens;
}

class _Fow {
  final int runs, wicket;
  final String name, over;
  const _Fow(this.runs, this.wicket, this.name, this.over);
}

class _CommentarySpeaker {
  final FlutterTts _tts = FlutterTts();
  final List<String> _queue = [];
  bool enabled = true;
  bool _ready = false;
  bool _busy = false;
  bool _disposed = false;

  Future<void> init() async {
    try {
      final hasIndian = await _tts.isLanguageAvailable('en-IN');
      await _tts.setLanguage(hasIndian == true ? 'en-IN' : 'en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true); // so lines never overlap
      _ready = true;
    } catch (_) {
      _ready = false; 
    }
  }

  void say(String text, {bool clear = false}) {
    final t = text.trim();
    if (!enabled || !_ready || _disposed || t.isEmpty) return;
    if (clear) _queue.clear();
    _queue.add(t);
    while (_queue.length > 4) {
      _queue.removeAt(0); 
    }
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && enabled && !_disposed) {
        await _tts.speak(_queue.removeAt(0));
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
    try {
      _tts.stop();
    } catch (_) {}
  }
}

class _Commentary {
  final int id;
  final String text;
  final String kind; 
  const _Commentary(this.id, this.text, this.kind);
}

class _Particle {
  final double x0, y0, vx, vy, g, rot, rotSpeed, size, flip;
  final Color color;
  const _Particle({
    required this.x0,
    required this.y0,
    required this.vx,
    required this.vy,
    required this.g,
    required this.rot,
    required this.rotSpeed,
    required this.size,
    required this.flip,
    required this.color,
  });
}

class _InningsSummary {
  final String team;
  final int runs, wickets, extras;
  final String overs;
  final Map<String, _BatStat> bat;
  final Map<String, _BowlStat> bowl;
  final List<_Fow> fow;
  const _InningsSummary({
    required this.team,
    required this.runs,
    required this.wickets,
    required this.extras,
    required this.overs,
    required this.bat,
    required this.bowl,
    required this.fow,
  });
}

class _Snapshot {
  final int runs, wickets, balls, extras, pRuns, pBalls;
  final String striker, nonStriker, bowler, lastOverBowler;
  final bool freeHit;
  final List<_Ball> over;
  final List<_Over> pastOvers;
  final Map<String, _BatStat> bat;
  final Map<String, _BowlStat> bowl;
  final List<_Fow> fow;
  final List<String> out;
  final List<String> played;
  final List<_Commentary> commentary;
  _Snapshot({
    required this.runs,
    required this.wickets,
    required this.balls,
    required this.extras,
    required this.pRuns,
    required this.pBalls,
    required this.striker,
    required this.nonStriker,
    required this.bowler,
    required this.lastOverBowler,
    required this.freeHit,
    required this.over,
    required this.pastOvers,
    required this.bat,
    required this.bowl,
    required this.fow,
    required this.out,
    required this.played,
    required this.commentary,
  });
}

// ============================================================================
//  SMALL REUSABLE WIDGETS
// ============================================================================

Widget _leftLayout(Widget? current, List<Widget> previous) {
  return Stack(
    alignment: Alignment.centerLeft,
    children: [...previous, if (current != null) current],
  );
}

class _RollingText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _RollingText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      layoutBuilder: _leftLayout,
      transitionBuilder: (child, anim) {
        final isNew = child.key == ValueKey<String>(text);
        final offset = Tween<Offset>(
          begin: Offset(0, isNew ? 0.7 : -0.7),
          end: Offset.zero,
        ).animate(anim);
        return ClipRect(
          child: SlideTransition(
            position: offset,
            child: FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      child: Text(text, key: ValueKey<String>(text), style: style),
    );
  }
}

class _PressableButton extends StatefulWidget {
  final String? text;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<Color> colors;
  final Color textColor;
  final bool enabled;
  final double fontSize;

  const _PressableButton({
    this.text,
    this.icon,
    required this.onTap,
    this.onLongPress,
    required this.colors,
    this.textColor = Colors.black87,
    this.enabled = true,
    this.fontSize = 22,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.colors,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: widget.colors.last.withOpacity(_down ? 0.15 : 0.35),
                  blurRadius: _down ? 3 : 8,
                  offset: Offset(0, _down ? 1 : 4),
                ),
              ],
            ),
            child: widget.icon != null
                ? Icon(widget.icon, color: widget.textColor, size: 24)
                : Text(
                    widget.text ?? '',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PlayerAutocomplete extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final List<String> options;
  final TextEditingController controller;
  const _PlayerAutocomplete({
    required this.label,
    required this.color,
    required this.icon,
    required this.options,
    required this.controller,
  });

  @override
  State<_PlayerAutocomplete> createState() => _PlayerAutocompleteState();
}

class _PlayerAutocompleteState extends State<_PlayerAutocomplete> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (TextEditingValue v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return widget.options;
        return widget.options.where((o) => o.toLowerCase().contains(q));
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            prefixIcon: Icon(widget.icon, color: widget.color, size: 20),
            labelText: widget.label,
            labelStyle: TextStyle(color: widget.color, fontWeight: FontWeight.w500),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black26),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: widget.color, width: 2),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.white,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 260),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Text(o, style: const TextStyle(color: Colors.black87)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TeamPhotoCard extends StatelessWidget {
  final bool compact;
  const _TeamPhotoCard({this.compact = false});

  static final Uint8List bytes = base64Decode(kTeamPhotoBase64);

  Widget _img({BoxFit fit = BoxFit.cover}) => Image.memory(
        bytes,
        fit: fit,
        width: double.infinity,
        gaplessPlayback: true,
      );

  void _open(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: InteractiveViewer(child: _img(fit: BoxFit.contain)),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 4, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: compact ? 170 : 230),
                  child: _img(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: const Text('Cricket Crushers',
                        style: TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('This app was designed & built by Sakib',
                        style: TextStyle(color: Colors.black54, fontSize: 12.5)),
                  ),
                  Icon(Icons.zoom_out_map_rounded, color: Colors.black26, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentaryTile extends StatelessWidget {
  final _Commentary entry;
  final bool latest;
  const _CommentaryTile({super.key, required this.entry, required this.latest});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (entry.kind) {
      case 'four':
        icon = Icons.sports_cricket;
        color = Colors.blueAccent;
        break;
      case 'six':
        icon = Icons.rocket_launch;
        color = Colors.deepPurple;
        break;
      case 'wicket':
        icon = Icons.bolt;
        color = Colors.redAccent;
        break;
      case 'milestone':
        icon = Icons.emoji_events;
        color = Colors.orange;
        break;
      case 'over':
        icon = Icons.flag_rounded;
        color = Colors.green;
        break;
      case 'run':
        icon = Icons.directions_run;
        color = Colors.blueGrey;
        break;
      default:
        icon = Icons.chat_bubble_outline;
        color = Colors.grey;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(30 * (1 - v), 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(latest ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(latest ? 0.35 : 0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.text,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: latest ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  PAINTERS
// ============================================================================

class _FieldPainter extends CustomPainter {
  final AnimationController fx;
  final AnimationController idle;
  final String kind; 
  final String label; 
  final double angle;

  _FieldPainter(this.fx, this.idle, this.kind, this.label, this.angle)
      : super(repaint: Listenable.merge([fx, idle]));

  static const double _release = 0.28; 
  static const double _contact = 0.46; 

  void _person(Canvas canvas, Offset p, Color color,
      {double armAngle = -1.57, double? batAngle}) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(p.translate(0, -8), 2.5, Paint()..color = color);
    canvas.drawLine(p.translate(0, -5.5), p.translate(0, 1), line);
    canvas.drawLine(p.translate(0, 1), p.translate(-2.3, 6), line);
    canvas.drawLine(p.translate(0, 1), p.translate(2.3, 6), line);
    final sh = p.translate(0, -4);
    final hand = sh + Offset(math.cos(armAngle), math.sin(armAngle)) * 5;
    canvas.drawLine(sh, hand, line);
    if (batAngle != null) {
      final tip = hand + Offset(math.cos(batAngle), math.sin(batAngle)) * 8;
      canvas.drawLine(
        hand,
        tip,
        Paint()
          ..color = const Color(0xFFE0B25A)
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _stumps(Canvas canvas, Offset base, double scatter) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (final i in [-1, 0, 1]) {
      canvas.save();
      canvas.translate(base.dx + i * 2.3 + i * scatter * 9, base.dy - scatter * 9 + scatter * scatter * 12);
      canvas.rotate(i * scatter * 1.4);
      canvas.drawLine(const Offset(0, -3.5), const Offset(0, 3.5), paint);
      canvas.restore();
    }
  }

  void _tag(Canvas canvas, Size size, Offset p, String text, Color bg, double opacity,
      double scale) {
    if (opacity <= 0 || text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withOpacity(opacity),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 12, h = tp.height + 4;
    final cx = p.dx.clamp(w / 2 + 1, size.width - w / 2 - 1).toDouble();
    final cy = p.dy.clamp(h / 2 + 1, size.height - h / 2 - 1).toDouble();
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h), const Radius.circular(8)),
      Paint()..color = bg.withOpacity(0.95 * opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h), const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(0.8 * opacity),
    );
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _ball(Canvas canvas, Offset pos, {double lift = 0, double radius = 3.4, double opacity = 1}) {
    if (lift > 0) canvas.drawCircle(pos, radius * 0.8, Paint()..color = Colors.black26);
    final p = pos.translate(0, -lift);
    canvas.drawCircle(p, radius, Paint()..color = const Color(0xFFE53935).withOpacity(opacity));
    canvas.drawCircle(p.translate(-radius * 0.3, -radius * 0.3), radius * 0.3,
        Paint()..color = Colors.white70.withOpacity(opacity));
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF47B866), Color(0xFF1D7A3B)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.55,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white24,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );

    final wob = math.sin(idle.value * math.pi) * 0.12;
    final dot = Paint()..color = Colors.white70;
    for (int i = 0; i < 9; i++) {
      final a = i * 2 * math.pi / 9 + wob;
      final rr = i.isEven ? r * 0.74 : r * 0.42;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * rr, 2, dot);
    }

    final pitch = Rect.fromCenter(center: c, width: r * 0.2, height: r * 0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pitch, const Radius.circular(2)),
      Paint()..color = const Color(0xFFD9C38F),
    );
    final crease = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(pitch.left, pitch.top + 5), Offset(pitch.right, pitch.top + 5), crease);
    canvas.drawLine(
        Offset(pitch.left, pitch.bottom - 5), Offset(pitch.right, pitch.bottom - 5), crease);

    final tv = fx.value;
    final active = tv > 0 && tv < 1 && kind.isNotEmpty;
    final t = active ? tv : 0.0;
    final isHit = kind == '0' ||
        kind == '1' ||
        kind == '2' ||
        kind == '3' ||
        kind == '4' ||
        kind == '5' ||
        kind == '6' ||
        kind == '1(Edge)'; 
    final swings = isHit || kind == 'W';
    final runsN = int.tryParse(kind.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    final scatter = (active && kind == 'W' && t >= _contact) ? _seg(t, _contact, _contact + 0.3) : 0.0;
    _stumps(canvas, Offset(c.dx, pitch.top), 0);
    _stumps(canvas, Offset(c.dx, pitch.bottom), Curves.easeOut.transform(scatter));

    final keeper = Offset(c.dx, pitch.bottom + r * 0.2);
    _person(canvas, keeper, Colors.amberAccent, armAngle: -0.5);

    final strikerEnd = Offset(c.dx - 6, pitch.bottom - 9);
    final nonStrikerEnd = Offset(c.dx + 6, pitch.top + 10);
    final bowlerHome = Offset(c.dx - 3, pitch.top - 9);
    final bowlerStart = Offset(c.dx - 3, pitch.top - r * 0.3);
    final bowlerRelease = Offset(c.dx - 3, pitch.top - 2);
    final bowlerFollow = Offset(c.dx - 3, pitch.top + 8);

    Offset bowlerPos = bowlerHome;
    double armAngle = -1.57;
    if (active) {
      if (t < _release) {
        final p = Curves.easeIn.transform(_seg(t, 0, _release));
        bowlerPos = Offset.lerp(bowlerStart, bowlerRelease, p)!;
        final u = _seg(t, 0.17, _release);
        armAngle = -1.9 + 3.2 * Curves.easeIn.transform(u) + math.sin(t * 40) * 0.15 * (1 - u);
      } else if (t < 0.5) {
        bowlerPos = Offset.lerp(bowlerRelease, bowlerFollow, _seg(t, _release, 0.5))!;
        armAngle = 1.3;
      } else if (t < 0.75) {
        bowlerPos = bowlerFollow;
        armAngle = 1.3 - 2.8 * _seg(t, 0.5, 0.75);
      } else {
        bowlerPos = Offset.lerp(bowlerFollow, bowlerHome, Curves.easeInOut.transform(_seg(t, 0.75, 1)))!;
        armAngle = -1.57;
      }
    }

    Offset striker = strikerEnd;
    Offset nonStriker = nonStrikerEnd;
    if (active && runsN >= 1 && runsN <= 3 && t > 0.52) {
      final q = _seg(t, 0.52, 0.95) * runsN;
      final leg = q.floor().clamp(0, runsN - 1).toInt();
      final w = Curves.easeInOut.transform((q - leg).clamp(0.0, 1.0).toDouble());
      if (leg.isEven) {
        striker = Offset.lerp(strikerEnd, nonStrikerEnd, w)!;
        nonStriker = Offset.lerp(nonStrikerEnd, strikerEnd, w)!;
      } else {
        striker = Offset.lerp(nonStrikerEnd, strikerEnd, w)!;
        nonStriker = Offset.lerp(strikerEnd, nonStrikerEnd, w)!;
      }
    }

    double batAngle = 1.5;
    if (active && swings) {
      if (t < _release) {
        batAngle = 1.5;
      } else if (t < 0.43) {
        batAngle = 1.5 - 3.8 * Curves.easeOut.transform(_seg(t, _release, 0.43));
      } else if (t < 0.58) {
        batAngle = -2.3 + 2.7 * Curves.easeOut.transform(_seg(t, 0.43, 0.58));
      } else {
        batAngle = 0.4 + 1.1 * _seg(t, 0.58, 0.8);
      }
    }

    _person(canvas, nonStriker, Colors.white, batAngle: 1.5);
    _person(canvas, striker, Colors.white, batAngle: batAngle);
    _person(canvas, bowlerPos, const Color(0xFFFFB74D), armAngle: armAngle);

    if (!active) {
      _ball(canvas, bowlerHome.translate(4, -10), radius: 2.4);
      return;
    }

    final bp = Offset(c.dx, pitch.bottom - 6);
    final wideEnd = Offset(c.dx + r * 0.3, pitch.bottom - 6);
    final target = kind == 'WD' ? wideEnd : bp;
    final dir = Offset(math.cos(angle), math.sin(angle));

    if (t < _release) {
      _ball(canvas, bowlerPos.translate(4, -9 + (armAngle * 2)), radius: 2.6);
      return;
    }

    if (t < _contact) {
      final u = _seg(t, _release, _contact);
      final from = Offset(c.dx - 1, pitch.top + 4);
      final pos = Offset.lerp(from, target, u)!;
      final lift = math.sin(math.pi * u) * r * 0.1;
      _ball(canvas, pos, lift: lift);
      return;
    }

    final u = _seg(t, _contact, 1);
    final fade = u < 0.85 ? 1.0 : (1 - (u - 0.85) / 0.15);
    final pop = Curves.easeOutBack.transform(_seg(u, 0, 0.12));

    Color tagColor;
    Offset ballPos = bp;
    double lift = 0;

    if (isHit && runsN != 0) {
      if (u < 0.12) {
        canvas.drawCircle(
          bp,
          3 + 10 * u / 0.12,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Colors.white.withOpacity(1 - u / 0.12),
        );
      }
      final six = runsN == 6;
      final end = (runsN == 4 || runsN == 6)
          ? c + dir * (r * (six ? 1.4 : 1.02))
          : c + dir * (r * (0.3 + 0.18 * runsN));
      final eased = Curves.easeOutCubic.transform(u);
      ballPos = Offset.lerp(bp, end, eased)!;
      lift = six ? math.sin(math.pi * u) * r * 0.4 : 0.0;
      if (runsN == 4 || runsN == 6) {
        for (int i = 7; i >= 1; i--) {
          final tt = (u - i * 0.025).clamp(0.0, 1.0).toDouble();
          final p = Offset.lerp(bp, end, Curves.easeOutCubic.transform(tt))!;
          final l = six ? math.sin(math.pi * tt) * r * 0.4 : 0.0;
          canvas.drawCircle(
            p.translate(0, -l),
            3.2 - i * 0.3,
            Paint()..color = (six ? Colors.amber : Colors.white).withOpacity(0.07 * (8 - i)),
          );
        }
        if (u > 0.8) {
          final k = (u - 0.8) / 0.2;
          canvas.drawCircle(
            c + dir * r,
            r * 0.25 * k,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = (six ? Colors.amber : Colors.lightBlueAccent).withOpacity(1 - k),
          );
        }
      }
      tagColor = runsN == 6
          ? Colors.deepPurple
          : runsN == 4
              ? Colors.blueAccent
              : Colors.green.shade700;
      _ball(canvas, ballPos, lift: lift, radius: 3.6, opacity: (runsN == 4 || runsN == 6) ? 1 : fade);
    } else if (kind == '0') {
      final end = bp + Offset(8, -r * 0.2);
      ballPos = Offset.lerp(bp, end, Curves.easeOut.transform(u))!;
      lift = math.sin(math.pi * math.min(1.0, u * 1.6)) * 5;
      tagColor = Colors.blueGrey;
      _ball(canvas, ballPos, lift: lift, opacity: fade);
    } else if (kind == 'W') {
      ballPos = bp.translate(0, 9 * Curves.easeOut.transform(u));
      tagColor = Colors.redAccent;
      final k = Curves.easeOut.transform(u);
      canvas.drawCircle(
        Offset(c.dx, pitch.bottom),
        r * 0.5 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.redAccent.withOpacity(1 - u),
      );
      for (int i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          Offset(c.dx, pitch.bottom) + d * (r * 0.1 + r * 0.22 * k),
          Offset(c.dx, pitch.bottom) + d * (r * 0.16 + r * 0.4 * k),
          Paint()
            ..strokeWidth = 2
            ..color = Colors.yellowAccent.withOpacity(1 - u),
        );
      }
      _ball(canvas, ballPos, opacity: fade);
    } else {
      final from = kind == 'WD' ? wideEnd : bp;
      final end = Offset(c.dx + (kind == 'WD' ? r * 0.1 : 0), keeper.dy - 8);
      ballPos = Offset.lerp(from, end, Curves.easeOut.transform(_seg(u, 0, 0.7)))!;
      tagColor = Colors.amber.shade800;
      _ball(canvas, ballPos, opacity: fade);
    }

    _tag(canvas, size, ballPos.translate(0, -lift - 14), label, tagColor, fade, pop);
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) =>
      old.kind != kind || old.angle != angle || old.label != label;
}

class _DuelPainter extends CustomPainter {
  final AnimationController fx;
  final AnimationController idle;
  final String kind; 
  final String label;
  final double angle;

  _DuelPainter(this.fx, this.idle, this.kind, this.label, this.angle)
      : super(repaint: Listenable.merge([fx, idle]));

  static const double release = 0.28;
  static const double contact = 0.50;

  static const Offset _striker = Offset(27, 25.5);
  static const Offset _bowler = Offset(115, 25.5);
  static const Offset _mid = Offset(71, 22);

  static double bowlerDx(double t) {
    if (t <= 0) return 0;
    if (t < 0.18) return 4 * Curves.easeOut.transform(t / 0.18);
    if (t < release) return 4 - 12 * Curves.easeIn.transform((t - 0.18) / (release - 0.18));
    if (t < 0.56) return -8 * (1 - Curves.easeInOut.transform((t - release) / (0.56 - release)));
    return 0;
  }

  static double batAngle(double t, String kind, bool act) {
    if (!act || kind == 'WD' || kind == 'X') return 0;
    if (t < 0.30) return 0;
    if (t < 0.44) return -0.30 * Curves.easeOut.transform((t - 0.30) / 0.14);
    if (t < 0.54) return -0.30 + 0.95 * Curves.easeOut.transform((t - 0.44) / 0.10);
    if (t < 0.78) return 0.65 * (1 - Curves.easeInOut.transform((t - 0.54) / 0.24));
    return 0;
  }

  static double labelAlpha(double t) {
    if (t < contact) return 0;
    if (t < 0.88) return 1;
    return (1 - (t - 0.88) / 0.12).clamp(0.0, 1.0).toDouble();
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  Color _color() {
    switch (kind) {
      case '4':
        return const Color(0xFF2979FF);
      case '6':
        return const Color(0xFF7C4DFF);
      case 'W':
        return const Color(0xFFE53935);
      case 'WD':
      case 'X':
        return const Color(0xFFEF8F00);
      case '0':
        return const Color(0xFF607D8B);
      default:
        return const Color(0xFF2E9E4F);
    }
  }

  void _ball(Canvas canvas, Offset p, {double r = 3.6, double a = 1}) {
    if (a <= 0) return;
    canvas.drawCircle(p, r, Paint()..color = const Color(0xFFE53935).withOpacity(a));
    canvas.drawCircle(p.translate(-r * 0.3, -r * 0.3), r * 0.32,
        Paint()..color = Colors.white.withOpacity(0.8 * a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tv = fx.value;
    final act = tv > 0 && tv < 1 && kind.isNotEmpty;

    if (!act) {
      final hop = math.sin(idle.value * math.pi).abs() * 4;
      _ball(canvas, Offset(_bowler.dx - 25, _bowler.dy + 8 - hop), r: 3.2, a: 0.9);
      return;
    }

    final t = tv;
    final hasHit = kind != 'WD' && kind != 'X';
    final startRel = Offset(_bowler.dx + bowlerDx(release) - 25, _bowler.dy + 6);
    final target = kind == 'WD'
        ? Offset(_striker.dx + 12, _striker.dy + 30)
        : kind == 'X'
            ? Offset(_striker.dx + 14, _striker.dy + 22)
            : Offset(_striker.dx + 21, _striker.dy + 4);

    if (t < release) {
      final lift = math.sin(math.pi * _seg(t, 0.10, release)) * 11;
      _ball(canvas, Offset(_bowler.dx + bowlerDx(t) - 25, _bowler.dy + 6 - lift), r: 3.4);
      return;
    }

    Offset flight(double u) {
      final x = startRel.dx + (target.dx - startRel.dx) * u;
      final y = startRel.dy + (target.dy - startRel.dy) * u;
      final bounce = math.sin(math.pi * u * 1.5).abs() * 12 * (1 - 0.4 * u);
      return Offset(x, y - bounce);
    }

    if (t < contact) {
      final u = _seg(t, release, contact);
      for (int k = 4; k >= 1; k--) {
        final uu = (u - 0.07 * k).clamp(0.0, 1.0).toDouble();
        _ball(canvas, flight(uu), r: 3.6 - k * 0.5, a: 0.30 - k * 0.05);
      }
      _ball(canvas, flight(u));
      return;
    }

    final u = _seg(t, contact, 1.0);
    final col = _color();
    final fade = u < 0.7 ? 1.0 : (1 - (u - 0.7) / 0.3).clamp(0.0, 1.0).toDouble();
    final e = Curves.easeOutCubic.transform(_seg(u, 0, 0.8));
    final runsN = int.tryParse(kind.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final big = kind == '4' || kind == '6';

    if (hasHit && u < 0.22) {
      final k = u / 0.22;
      canvas.drawCircle(
        target,
        3 + 13 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withOpacity(1 - k),
      );
    }

    if (hasHit && runsN > 0) {
      final dir = Offset(0.5 + 0.5 * math.cos(angle).abs(), -(0.3 + 0.7 * math.sin(angle).abs()));
      final len = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
      final d = Offset(dir.dx / len, dir.dy / len);
      final dist = runsN == 6 ? 70.0 : runsN == 4 ? 60.0 : 18.0 + 9.0 * runsN;
      Offset at(double ee) {
        var p = target + d * dist * ee;
        if (runsN == 6) p = p.translate(0, -26 * math.sin(math.pi * ee));
        return p;
      }

      if (big) {
        for (int k = 7; k >= 1; k--) {
          final ee = Curves.easeOutCubic.transform((_seg(u, 0, 0.8) - k * 0.035).clamp(0.0, 1.0).toDouble());
          canvas.drawCircle(at(ee), 3.4 - k * 0.3,
              Paint()..color = (runsN == 6 ? Colors.amber : Colors.white).withOpacity(0.06 * (8 - k) * fade));
        }
      }
      _ball(canvas, at(e), a: fade);
    } else if (kind == '0') {
      _ball(canvas, target.translate(10 * e, 12 * e), a: fade);
    } else if (kind == 'W') {
      final c = Offset(_striker.dx + 20, _striker.dy + 6);
      final k = Curves.easeOut.transform(_seg(u, 0, 0.7));
      canvas.drawCircle(
        c,
        6 + 22 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.redAccent.withOpacity(1 - k),
      );
      for (int i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final dv = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          c + dv * (5 + 8 * k),
          c + dv * (9 + 17 * k),
          Paint()
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = Colors.yellowAccent.withOpacity(1 - k),
        );
      }
      _ball(canvas, target.translate(4 * e, 14 * e), a: fade);
    } else {
      _ball(canvas, target.translate(-26 * e, 16 * e), a: fade);
    }

    if (big && u > 0.1 && u < 0.7) {
      final k = _seg(u, 0.1, 0.7);
      final c = _mid;
      canvas.drawCircle(
        c,
        10 + 26 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = (kind == '6' ? Colors.amber : Colors.lightBlueAccent).withOpacity(0.8 * (1 - k)),
      );
      for (int i = 0; i < 10; i++) {
        final a = i * math.pi / 5 + 0.3;
        final dv = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          c + dv * (14 + 22 * k),
          c + dv * (18 + 28 * k),
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withOpacity(0.85 * (1 - k)),
        );
      }
    }

    final a = labelAlpha(t);
    if (label.isNotEmpty && a > 0) {
      final pop = Curves.easeOutBack.transform(_seg(t, contact, contact + 0.1));
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withOpacity(a),
            fontSize: label.length > 2 ? 12 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = math.max(26.0, tp.width + 14);
      const h = 24.0;
      final c = _mid.translate(0, -3 * _seg(t, contact, 0.9));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(pop.clamp(0.0, 1.3).toDouble());
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h), const Radius.circular(12));
      canvas.drawRRect(
        rr.inflate(3),
        Paint()
          ..color = col.withOpacity(0.35 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(rr, Paint()..color = col.withOpacity(0.95 * a));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withOpacity(0.85 * a),
      );
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DuelPainter old) =>
      old.kind != kind || old.label != label || old.angle != angle;
}

class _DuelBgPainter extends CustomPainter {
  final AnimationController fx;
  final AnimationController idle;
  final String kind;

  _DuelBgPainter(this.fx, this.idle, this.kind) : super(repaint: Listenable.merge([fx, idle]));

  static const Offset _striker = Offset(27, 25.5);
  static const Offset _bowler = Offset(115, 25.5);

  void _glow(Canvas canvas, Offset c, double r, Color col, double a) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [col.withOpacity(a), col.withOpacity(0)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ms = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final tv = fx.value;
    final act = tv > 0 && tv < 1 && kind.isNotEmpty;
    final t = act ? tv : 0.0;
    final breathe = 0.5 + 0.5 * math.sin(ms * 2.2);

    _glow(canvas, _striker, 46, Colors.lightGreenAccent, 0.10 + 0.10 * breathe);
    _glow(canvas, _bowler, 46, Colors.orangeAccent, 0.10 + 0.10 * (1 - breathe));

    for (int i = 0; i < 8; i++) {
      final y = 86 - ((ms * (7 + i) + i * 19) % 96);
      final x = 6 + i * 18.0 + math.sin(ms * 0.9 + i) * 4;
      final a = (0.07 + 0.10 * (0.5 + 0.5 * math.sin(ms * 1.5 + i * 2))) *
          math.sin(math.pi * ((y + 10) / 96).clamp(0.0, 1.0).toDouble());
      canvas.drawCircle(Offset(x, y), 1.0 + (i % 3) * 0.4, Paint()..color = Colors.white.withOpacity(a.clamp(0.0, 1.0).toDouble()));
    }

    final whoosh = act && t > 0.12 && t < 0.56;
    final speed = whoosh ? 150.0 : 26.0;
    final baseA = whoosh ? 0.40 : 0.10;
    for (int lane = -1; lane <= 1; lane++) {
      final y = 25.5 + lane * 11.0;
      final off = (ms * speed + lane * 5) % 16;
      for (double x = 96 - off; x > 46; x -= 16) {
        final f = math.sin(math.pi * ((x - 46) / 50).clamp(0.0, 1.0).toDouble());
        canvas.drawLine(
          Offset(x, y),
          Offset(x - (whoosh ? 9 : 5), y),
          Paint()
            ..strokeWidth = whoosh ? 1.6 : 1.1
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withOpacity(baseA * f),
        );
      }
    }

    if (act && t >= 0.5) {
      final k = ((t - 0.5) / 0.4).clamp(0.0, 1.0).toDouble();
      Color? c;
      if (kind == '4') c = const Color(0xFF2979FF);
      if (kind == '6') c = const Color(0xFFFFC107);
      if (kind == 'W') c = const Color(0xFFE53935);
      if (c != null) {
        final centre = Offset(71, 24);
        _glow(canvas, centre, 40 + 70 * k, c, 0.50 * (1 - k));
        if (kind == '6') {
          for (int i = 0; i < 9; i++) {
            final px = 14 + i * 14.0 + math.sin(i * 1.7) * 4;
            final py = 70 - (30 + i * 3.0) * k;
            canvas.drawCircle(Offset(px, py), 1.8 * (1 - k * 0.5),
                Paint()..color = Colors.amberAccent.withOpacity(0.9 * (1 - k)));
          }
        }
        if (kind == 'W') {
          for (int i = 0; i < 4; i++) {
            final y = 6 + i * 20.0;
            canvas.drawLine(
              Offset(0, y),
              Offset(142 * k, y),
              Paint()
                ..strokeWidth = 1.2
                ..color = Colors.redAccent.withOpacity(0.35 * (1 - k)),
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DuelBgPainter old) => old.kind != kind;
}

class _HeroMotionPainter extends CustomPainter {
  final AnimationController anim;
  _HeroMotionPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final ms = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final w = size.width, h = size.height;

    const cols = [Colors.lightBlueAccent, Colors.greenAccent, Colors.purpleAccent];
    for (int i = 0; i < 3; i++) {
      final c = Offset(
        w * (0.30 + 0.28 * math.sin(ms * 0.45 + i * 2.1) + i * 0.18),
        h * (0.45 + 0.30 * math.cos(ms * 0.38 + i * 1.7)),
      );
      final r = math.max(w, h) * 0.34;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [cols[i].withOpacity(0.09), cols[i].withOpacity(0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final span = w + 260;
    final x = ((ms * 36) % span) - 130;
    final rect = Rect.fromLTWH(x - 60, 0, 130, h);
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 70, 0)
      ..lineTo(x + 10, h)
      ..lineTo(x - 60, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0),
            Colors.white.withOpacity(0.07),
            Colors.white.withOpacity(0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroMotionPainter old) => false;
}

class _ConfettiPainter extends CustomPainter {
  final AnimationController ctrl;
  final List<_Particle> particles;
  _ConfettiPainter(this.ctrl, this.particles) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) {
    final t = ctrl.value;
    if (t >= 1 || particles.isEmpty) return;
    final secs = (ctrl.duration?.inMilliseconds ?? 2600) / 1000.0;
    final T = t * secs;
    final fade = t > 0.75 ? ((1 - t) / 0.25).clamp(0.0, 1.0).toDouble() : 1.0;
    final paint = Paint();
    for (final p in particles) {
      final x = p.x0 * size.width + p.vx * T;
      final y = p.y0 * size.height + p.vy * T + 0.5 * p.g * T * T;
      paint.color = p.color.withOpacity(fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + p.rotSpeed * T);
      canvas.scale(1, math.cos(T * p.flip));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.particles != particles;
}

// ============================================================================
//  SCREEN
// ============================================================================

class ScoringScreen extends StatefulWidget {
  final String teamAId;
  final String teamBId;
  final String teamAName;
  final String teamBName;
  final int totalOvers;
  final String battingTeamId;
  final String bowlingTeamId;

  const ScoringScreen({
    super.key,
    required this.teamAId,
    required this.teamBId,
    required this.teamAName,
    required this.teamBName,
    required this.totalOvers,
    required this.battingTeamId,
    required this.bowlingTeamId,
  });

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> with TickerProviderStateMixin {
  // ---------------------------------------------------------------- state
  int currentInnings = 1;
  int targetScore = 0;
  int totalRuns = 0;
  int wickets = 0;
  int legalBalls = 0;
  int extras = 0;
  int partnershipRuns = 0;
  int partnershipBalls = 0;
  bool freeHit = false;

  List<_Ball> currentOverBalls = [];
  List<_Over> pastOvers = [];
  List<_Snapshot> history = [];
  List<_Commentary> commentary = [];
  Map<String, _BatStat> batStats = {};
  Map<String, _BowlStat> bowlStats = {};
  List<_Fow> fow = [];
  List<String> outPlayers = [];
  List<String> playedBowlers = [];
  
  // 🔥 NEW ADDITION: Highlights save করার লিস্ট
  List<HighlightClip> matchHighlights = [];

  String strikerName = '';
  String nonStrikerName = '';
  String bowlerName = '';
  String lastOverBowler = '';

  List<Map<String, dynamic>> _battingTeamPlayers = [];
  List<Map<String, dynamic>> _bowlingTeamPlayers = [];
  final Map<String, File> playerImages = {};

  _InningsSummary? _inn1;
  _InningsSummary? _inn2;

  bool isMatchEnded = false;
  bool _showTargetOverlay = false;
  int _matchStage = 0; // 0 none, 1 winner, 2 summary
  String _winnerName = '';
  String _resultText = '';
  String _motmName = '';
  String _motmLine = '';

  // ---------------------------------------------------------- effects state
  final math.Random _rng = math.Random();
  int _commentaryId = 0;

  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final _CommentarySpeaker _speaker = _CommentarySpeaker();

  late final AnimationController _pulseCtrl;
  late final AnimationController _fieldCtrl;
  late final AnimationController _flashCtrl;
  late final AnimationController _shakeCtrl;
  late final AnimationController _confettiCtrl;

  List<_Particle> _particles = [];
  String _fieldKind = '';
  String _fieldLabel = '';
  double _fieldAngle = 0;
  Color _flashColor = Colors.white;

  static const Color _baseGlow = Color(0xFF2F5BEA);
  Color _glowColor = _baseGlow;
  Timer? _glowTimer;

  String? _celebrationType;
  String? _activePlayerName;
  File? _activePlayerImage;
  String _celebrationSub = '';
  int _celebId = 0;
  Timer? _celebTimer;

  String _lastAction = '';
  bool _showHitAction = false;
  int _hitCounter = 0;

  static const List<Color> _fourPalette = [
    Colors.blueAccent,
    Colors.lightBlueAccent,
    Colors.white,
    Colors.cyanAccent,
  ];
  static const List<Color> _sixPalette = [
    Colors.deepPurpleAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.amber,
    Colors.white,
  ];
  static const List<Color> _goldPalette = [
    Colors.amber,
    Colors.orange,
    Colors.yellowAccent,
    Colors.white,
  ];
  static const List<Color> _wicketPalette = [
    Colors.redAccent,
    Colors.deepOrange,
    Colors.yellowAccent,
  ];
  static const List<Color> _partyPalette = [
    Colors.redAccent,
    Colors.blueAccent,
    Colors.green,
    Colors.amber,
    Colors.purpleAccent,
    Colors.cyan,
    Colors.orange,
  ];

  // --------------------------------------------------------------- lifecycle
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _fieldCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1200), value: 1);
    _flashCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);
    _shakeCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
    _confettiCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 2600), value: 1);
    _speaker.init();
    _loadPlayersAndShowSetup(isSecondInnings: false);
  }

  @override
  void dispose() {
    _speaker.dispose();
    _glowTimer?.cancel();
    _celebTimer?.cancel();
    _audioPlayer.dispose();
    _pulseCtrl.dispose();
    _fieldCtrl.dispose();
    _flashCtrl.dispose();
    _shakeCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- helpers
  String _teamName(String id) => id == widget.teamAId ? widget.teamAName : widget.teamBName;
  String get battingTeamName =>
      currentInnings == 1 ? _teamName(widget.battingTeamId) : _teamName(widget.bowlingTeamId);
  String get bowlingTeamName =>
      currentInnings == 1 ? _teamName(widget.bowlingTeamId) : _teamName(widget.battingTeamId);

  _BatStat _bat(String n) => batStats.putIfAbsent(n, () => _BatStat());
  _BowlStat _bowl(String n) => bowlStats.putIfAbsent(n, () => _BowlStat());

  File? get strikerImage => playerImages[strikerName];
  File? get bowlerImage => playerImages[bowlerName];

  bool get _locked =>
      isMatchEnded || _showTargetOverlay || strikerName.isEmpty || bowlerName.isEmpty;

  int get totalBalls => widget.totalOvers * 6;
  int get ballsRemaining => math.max(0, totalBalls - legalBalls);
  int get maxWickets {
    final n = _battingTeamPlayers.length;
    if (n < 2) return 10;
    return math.min(10, n - 1);
  }

  int get currentOverNumber => math.min((legalBalls ~/ 6) + 1, widget.totalOvers);
  int get legalBallsThisOver => currentOverBalls.where((b) => b.legal).length;
  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get crr => legalBalls == 0 ? 0 : totalRuns * 6 / legalBalls;
  double get rrr => ballsRemaining == 0 ? 0 : (targetScore - totalRuns) * 6 / ballsRemaining;
  int get projected => legalBalls == 0 ? 0 : (crr * widget.totalOvers).round();

  int get _bowlerQuota => math.max(1, (widget.totalOvers / 5).ceil());
  bool get _quotaActive {
    final n = _names(_bowlingTeamPlayers, mode: 'bowl').length;
    return n > 0 && n * _bowlerQuota >= widget.totalOvers;
  }

  double get winProbability {
    if (currentInnings != 2) return 0.5;
    final need = targetScore - totalRuns;
    if (need <= 0) return 1;
    if (ballsRemaining == 0 || wickets >= maxWickets) return 0;
    final wl = (maxWickets - wickets).clamp(1, 10).toInt();
    final required = need * 6 / ballsRemaining;
    final firstRate = (targetScore - 1) * 6 / totalBalls;
    final par = math.max(firstRate, 6.0) * math.sqrt(wl / 10);
    final p = 1 / (1 + math.exp(0.9 * (required - par)));
    return p.clamp(0.02, 0.98).toDouble();
  }

  List<String> _names(
    List<Map<String, dynamic>> players, {
    String? mode,
    Iterable<String> exclude = const [],
  }) {
    final ex = exclude.map((e) => e.toLowerCase()).toSet();
    List<Map<String, dynamic>> pool = players;
    if (mode == 'bat') {
      final f = players.where((p) => (p['role'] ?? '').toString() != 'Bowler').toList();
      if (f.isNotEmpty) pool = f;
    } else if (mode == 'bowl') {
      final f = players.where((p) {
        final r = (p['role'] ?? '').toString();
        return r == 'Bowler' || r == 'All-rounder';
      }).toList();
      if (f.isNotEmpty) pool = f;
    }
    return pool
        .map((p) => (p['name'] ?? '').toString())
        .where((n) => n.isNotEmpty && !ex.contains(n.toLowerCase()))
        .toList();
  }

  String _pick(List<String> l) => l[_rng.nextInt(l.length)];

  void swapStrike() {
    final t = strikerName;
    strikerName = nonStrikerName;
    nonStrikerName = t;
  }

  Future<void> _loadPlayersAndShowSetup({required bool isSecondInnings}) async {
    if (isSecondInnings) {
      _battingTeamPlayers = await AppDatabase.getPlayers(widget.bowlingTeamId);
      _bowlingTeamPlayers = await AppDatabase.getPlayers(widget.battingTeamId);
    } else {
      _battingTeamPlayers = await AppDatabase.getPlayers(widget.battingTeamId);
      _bowlingTeamPlayers = await AppDatabase.getPlayers(widget.bowlingTeamId);
    }
    if (mounted) {
      setState(() {});
      _showSetupDialog(isSecondInnings: isSecondInnings);
    }
  }

  void _addCommentary(String text, {String kind = 'info', String? say, bool speak = true}) {
    if (!mounted) return;
    setState(() {
      commentary.insert(0, _Commentary(++_commentaryId, text, kind));
      if (commentary.length > 12) commentary.removeLast();
    });
    if (speak) _speaker.say(_spoken(say ?? text));
  }

  String _spoken(String t) {
    var s = t.replaceAllMapped(RegExp(r'(\d+)/(\d+)'), (m) => '${m[1]} for ${m[2]}');
    s = s.replaceAllMapped(
        RegExp(r'\b([A-Z]{4,})\b'), (m) => m[1]![0] + m[1]!.substring(1).toLowerCase());
    s = s.replaceAll(RegExp(r'\bHIT\b'), 'hit').replaceAll(RegExp(r'[()•]'), ', ');
    return s;
  }

  String _ord(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  int _trailingDots() {
    int c = 0;
    for (int i = currentOverBalls.length - 1; i >= 0; i--) {
      if (currentOverBalls[i].kind == _BallKind.dot) {
        c++;
      } else {
        break;
      }
    }
    return c;
  }

  String _chaseLine() {
    if (currentInnings != 2) return '';
    final need = targetScore - totalRuns;
    if (need <= 0 || ballsRemaining <= 0) return '';
    return ' $battingTeamName need $need from $ballsRemaining ball${ballsRemaining == 1 ? "" : "s"}.';
  }

  void _saveHistory() {
    history.add(_Snapshot(
      runs: totalRuns,
      wickets: wickets,
      balls: legalBalls,
      extras: extras,
      pRuns: partnershipRuns,
      pBalls: partnershipBalls,
      striker: strikerName,
      nonStriker: nonStrikerName,
      bowler: bowlerName,
      lastOverBowler: lastOverBowler,
      freeHit: freeHit,
      over: List<_Ball>.from(currentOverBalls),
      pastOvers: List<_Over>.from(pastOvers),
      bat: batStats.map((k, v) => MapEntry(k, v.copy())),
      bowl: bowlStats.map((k, v) => MapEntry(k, v.copy())),
      fow: List<_Fow>.from(fow),
      out: List<String>.from(outPlayers),
      played: List<String>.from(playedBowlers),
      commentary: List<_Commentary>.from(commentary),
    ));
    if (history.length > 150) history.removeAt(0);
  }

  void _restore(_Snapshot s) {
    totalRuns = s.runs;
    wickets = s.wickets;
    legalBalls = s.balls;
    extras = s.extras;
    partnershipRuns = s.pRuns;
    partnershipBalls = s.pBalls;
    strikerName = s.striker;
    nonStrikerName = s.nonStriker;
    bowlerName = s.bowler;
    lastOverBowler = s.lastOverBowler;
    freeHit = s.freeHit;
    currentOverBalls = List<_Ball>.from(s.over);
    pastOvers = List<_Over>.from(s.pastOvers);
    batStats = s.bat.map((k, v) => MapEntry(k, v.copy()));
    bowlStats = s.bowl.map((k, v) => MapEntry(k, v.copy()));
    fow = List<_Fow>.from(s.fow);
    outPlayers = List<String>.from(s.out);
    playedBowlers = List<String>.from(s.played);
    commentary = List<_Commentary>.from(s.commentary);
  }

  Future<void> undo() async {
    if (history.isEmpty || isMatchEnded || _showTargetOverlay) return;

    _Ball? last;
    if (currentOverBalls.isNotEmpty) {
      last = currentOverBalls.last;
    } else if (pastOvers.isNotEmpty && pastOvers.last.balls.isNotEmpty) {
      last = pastOvers.last.balls.last;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.undo_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Undo last action?',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (last != null) ...[
              Row(
                children: [
                  const Text('Last ball: ', style: TextStyle(color: Colors.black54)),
                  _buildBallChip(last, size: 30, animate: false),
                ],
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Score, batsmen, over and commentary will go back to the previous state. '
              'Are you sure you want to undo?',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK, Undo',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    if (history.isEmpty || isMatchEnded || _showTargetOverlay) return;

    HapticFeedback.selectionClick();
    _celebTimer?.cancel();
    setState(() {
      _restore(history.removeLast());
      _celebrationType = null;
      _showHitAction = false;
      // 🔥 Remove highlight if we undo
      if (matchHighlights.isNotEmpty) {
        matchHighlights.removeLast();
      }
    });
    _speaker.stop();
    _addCommentary('Last ball undone.', speak: false);
  }

  void _manualSwap() {
    if (_locked) return;
    HapticFeedback.selectionClick();
    _saveHistory();
    setState(swapStrike);
    _addCommentary('Strike changed: $strikerName is now on strike.', speak: false);
  }

  void _flash(Color c) {
    _flashColor = c;
    _flashCtrl.forward(from: 0);
  }

  void _shake() => _shakeCtrl.forward(from: 0);

  void _pulseGlow(Color c) {
    setState(() => _glowColor = c);
    _glowTimer?.cancel();
    _glowTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _glowColor = _baseGlow);
    });
  }

  void _fieldEvent(String kind, [String? label]) {
    setState(() {
      _fieldKind = kind;
      _fieldLabel = label ?? kind;
      _fieldAngle = _rng.nextDouble() * 2 * math.pi;
    });
    _fieldCtrl.duration = Duration(milliseconds: (kind == '4' || kind == '6') ? 2300 : 1900);
    _fieldCtrl.forward(from: 0);
  }

  void _spawnConfetti(int count, List<Color> palette, {bool rain = false, double seconds = 2.6}) {
    final list = List<_Particle>.generate(count, (_) {
      double x0, y0, vx, vy, g;
      if (rain) {
        x0 = _rng.nextDouble();
        y0 = -0.05 - _rng.nextDouble() * 0.4;
        vx = (_rng.nextDouble() - 0.5) * 90;
        vy = 90 + _rng.nextDouble() * 170;
        g = 70;
      } else {
        final ang = -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi * 1.3;
        final speed = 300 + _rng.nextDouble() * 520;
        x0 = 0.5;
        y0 = 0.3;
        vx = math.cos(ang) * speed;
        vy = math.sin(ang) * speed;
        g = 900;
      }
      return _Particle(
        x0: x0,
        y0: y0,
        vx: vx,
        vy: vy,
        g: g,
        rot: _rng.nextDouble() * math.pi * 2,
        rotSpeed: (_rng.nextDouble() - 0.5) * 12,
        size: 7 + _rng.nextDouble() * 8,
        flip: 4 + _rng.nextDouble() * 8,
        color: palette[_rng.nextInt(palette.length)],
      );
    });
    setState(() => _particles = list);
    _confettiCtrl.duration = Duration(milliseconds: (seconds * 1000).round());
    _confettiCtrl.forward(from: 0);
  }

  Future<void> _playSound(String soundName) async {
    try {
      await _audioPlayer.play(AssetSource('sounds/$soundName.mp3'));
    } catch (e) {
      debugPrint('Sound not found: $e');
    }
  }

  void _triggerCelebration(String type, String playerName, File? playerImage, {String sub = ''}) {
    _celebTimer?.cancel();
    setState(() {
      _celebrationType = type;
      _activePlayerName = playerName;
      _activePlayerImage = playerImage;
      _celebrationSub = sub;
      _celebId++;
    });
    if (type == 'FOUR' || type == 'SIX') {
      _playSound(type.toLowerCase());
    }
    _celebTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _celebrationType = null);
    });
  }

  void _triggerHitAction(String action) {
    final id = ++_hitCounter;
    setState(() {
      _lastAction = action;
      _showHitAction = true;
    });
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted && id == _hitCounter) setState(() => _showHitAction = false);
    });
  }

  void _boundaryFx(int runs, String name) {
    if (runs == 4) {
      HapticFeedback.mediumImpact();
      _flash(Colors.blueAccent);
      _pulseGlow(Colors.blueAccent);
      _spawnConfetti(38, _fourPalette);
      _triggerCelebration('FOUR', name, playerImages[name]);
    } else if (runs == 6) {
      HapticFeedback.heavyImpact();
      _flash(Colors.deepPurpleAccent);
      _pulseGlow(Colors.deepPurpleAccent);
      _spawnConfetti(75, _sixPalette);
      _triggerCelebration('SIX', name, playerImages[name]);
    }
  }

  // =========================================================================
  //  SETUP / PLAYER DIALOGS
  // =========================================================================
  void _showSetupDialog({required bool isSecondInnings}) {
    final sc = TextEditingController();
    final nc = TextEditingController();
    final bc = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Icon(Icons.sports_cricket, color: Colors.blueAccent.shade400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSecondInnings ? '2nd Innings Setup' : 'Match Setup',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${isSecondInnings ? _teamName(widget.bowlingTeamId) : _teamName(widget.battingTeamId)} batting',
                      style: const TextStyle(color: Colors.black45, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _PlayerAutocomplete(
                    label: 'Striker Name',
                    color: Colors.green.shade700,
                    icon: Icons.sports_cricket,
                    options: _names(_battingTeamPlayers, mode: 'bat'),
                    controller: sc,
                  ),
                  const SizedBox(height: 10),
                  _PlayerAutocomplete(
                    label: 'Non-Striker Name',
                    color: Colors.black87,
                    icon: Icons.person_outline,
                    options: _names(_battingTeamPlayers, mode: 'bat'),
                    controller: nc,
                  ),
                  const SizedBox(height: 10),
                  _PlayerAutocomplete(
                    label: 'Opening Bowler',
                    color: Colors.orange.shade800,
                    icon: Icons.sports_baseball,
                    options: _names(_bowlingTeamPlayers, mode: 'bowl'),
                    controller: bc,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                label: const Text('Start Innings',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final s = sc.text.trim(), n = nc.text.trim(), b = bc.text.trim();
                  if (s.isEmpty || n.isEmpty || b.isEmpty) {
                    setD(() => error = 'Please fill all three names');
                    return;
                  }
                  if (s.toLowerCase() == n.toLowerCase()) {
                    setD(() => error = 'Striker and non-striker must be different');
                    return;
                  }
                  Navigator.pop(ctx);
                  _startInnings(s, n, b, isSecondInnings);
                },
              ),
            ],
          );
        });
      },
    );
  }

  void _startInnings(String s, String n, String b, bool second) {
    setState(() {
      strikerName = s;
      nonStrikerName = n;
      bowlerName = b;
      _bat(s);
      _bat(n);
      _bowl(b);
      if (!playedBowlers.contains(b)) playedBowlers.add(b);
    });
    if (second) {
      _addCommentary(
          '2nd innings: $battingTeamName need $targetScore to win from ${widget.totalOvers} overs. '
          '$s and $n begin the chase against $b.',
          kind: 'over');
    } else {
      _addCommentary(
          'Match started, ${widget.totalOvers} overs a side. $s and $n are at the crease, $b has the new ball.',
          kind: 'over');
    }
  }

  void _showNewBatsmanDialog(String outName) {
    final c = TextEditingController();
    String? error;
    final taken = [...outPlayers, strikerName, nonStrikerName];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('New Batsman',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$outName is out. Who walks in next?',
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
                _PlayerAutocomplete(
                  label: 'Batsman Name',
                  color: Colors.green.shade700,
                  icon: Icons.sports_cricket,
                  options: _names(_battingTeamPlayers, exclude: taken),
                  controller: c,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final name = c.text.trim();
                  if (name.isEmpty) {
                    setD(() => error = 'Enter the batsman name');
                    return;
                  }
                  if (taken.any((t) => t.toLowerCase() == name.toLowerCase())) {
                    setD(() => error = 'This player is already batting or out');
                    return;
                  }
                  Navigator.pop(ctx);
                  setState(() {
                    if (strikerName == outName) {
                      strikerName = name;
                    } else {
                      nonStrikerName = name;
                    }
                    _bat(name);
                  });
                  _addCommentary('New batter $name walks in at $totalRuns/$wickets.');
                  _afterBall();
                },
                child: const Text('Confirm',
                    style: TextStyle(
                        color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  String? _bowlerBlock(String name) {
    if (name.isEmpty) return 'Enter the bowler name';
    if (name.toLowerCase() == lastOverBowler.toLowerCase()) {
      return '$name bowled the last over';
    }
    if (_quotaActive) {
      final done = (bowlStats[name]?.legalBalls ?? 0) ~/ 6;
      if (done >= _bowlerQuota) return '$name has used the $_bowlerQuota-over quota';
    }
    return null;
  }

  void _showBowlerChangeDialog() {
    final c = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                const Icon(Icons.flag_rounded, color: Colors.green),
                const SizedBox(width: 8),
                Text('Over ${pastOvers.length} done',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score $totalRuns/$wickets  •  Select next bowler',
                      style: const TextStyle(color: Colors.black54, fontSize: 14)),
                  const SizedBox(height: 14),
                  if (playedBowlers.isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: playedBowlers.map((name) {
                        final block = _bowlerBlock(name);
                        final ok = block == null;
                        final ov = bowlStats[name]?.overs ?? '0.0';
                        return InkWell(
                          onTap: ok
                              ? () {
                                  Navigator.pop(ctx);
                                  _changeBowler(name);
                                }
                              : () => setD(() => error = block),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: (ok ? Colors.blueAccent : Colors.grey).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: (ok ? Colors.blueAccent : Colors.grey).withOpacity(0.5)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name,
                                    style: TextStyle(
                                        color: ok ? Colors.blueAccent : Colors.grey,
                                        fontWeight: FontWeight.bold)),
                                Text('$ov ov',
                                    style: const TextStyle(color: Colors.black45, fontSize: 11)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 18),
                  const Text('Or add a new bowler:',
                      style: TextStyle(color: Colors.black54, fontSize: 12)),
                  _PlayerAutocomplete(
                    label: 'Bowler Name',
                    color: Colors.orange.shade800,
                    icon: Icons.sports_baseball,
                    options: _names(_bowlingTeamPlayers, mode: 'bowl', exclude: [lastOverBowler]),
                    controller: c,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final name = c.text.trim();
                  final block = _bowlerBlock(name);
                  if (block != null) {
                    setD(() => error = block);
                    return;
                  }
                  Navigator.pop(ctx);
                  _changeBowler(name);
                },
                child: const Text('Confirm',
                    style: TextStyle(
                        color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  void _changeBowler(String name) {
    setState(() {
      bowlerName = name;
      if (!playedBowlers.contains(name)) playedBowlers.add(name);
      _bowl(name);
    });
    _addCommentary(
        '$name comes into the attack for over ${pastOvers.length + 1}. '
        '${widget.totalOvers - pastOvers.length} over${widget.totalOvers - pastOvers.length == 1 ? "" : "s"} to go.',
        kind: 'over');
  }

  // =========================================================================
  //  SCORING LOGIC
  // =========================================================================
  
  // 🔥 NEW ADDITION: Edge boundary method (1 run, no strike change)
  void addEdgeBoundaryRun() {
    if (_locked) return;
    HapticFeedback.lightImpact();
    _saveHistory();

    final batter = strikerName;
    final bat = _bat(batter);
    final bowl = _bowl(bowlerName);

    setState(() {
      currentOverBalls.add(_Ball(
        label: '1(Edge)',
        runs: 1,
        bowlerRuns: 1,
        legal: true,
        kind: _BallKind.run,
      ));
      totalRuns += 1;
      legalBalls++;
      bat.runs += 1;
      bat.balls++;
      bowl.runs += 1;
      bowl.legalBalls++;
      partnershipRuns += 1;
      partnershipBalls++;
      freeHit = false;
      // 🔥 No swapStrike() here, as per user's custom rule
    });

    _triggerHitAction('1');
    _fieldEvent('1(Edge)', '1');
    
    final sc = '${bat.runs} off ${bat.balls}';
    _addCommentary('Edged to the boundary! They run 1. $batter is on $sc. Strike remains same.', kind: 'run');

    _afterBall();
  }

  void addRuns(int runs) {
    if (_locked) return;
    HapticFeedback.lightImpact();
    _saveHistory();

    final batter = strikerName;
    final bowler = bowlerName;
    final bat = _bat(batter);
    final bowl = _bowl(bowler);
    final prev = bat.runs;
    final prevP = partnershipRuns;
    final fh = freeHit ? 'Free hit! ' : '';

    setState(() {
      currentOverBalls.add(_Ball(
        label: '$runs',
        runs: runs,
        bowlerRuns: runs,
        legal: true,
        kind: runs == 4
            ? _BallKind.four
            : runs == 6
                ? _BallKind.six
                : runs == 0
                    ? _BallKind.dot
                    : _BallKind.run,
      ));
      totalRuns += runs;
      legalBalls++;
      bat.runs += runs;
      bat.balls++;
      if (runs == 4) bat.fours++;
      if (runs == 6) bat.sixes++;
      bowl.runs += runs;
      bowl.legalBalls++;
      partnershipRuns += runs;
      partnershipBalls++;
      freeHit = false;
    });

    _triggerHitAction('$runs');
    _fieldEvent('$runs', '$runs');

    final sc = '${bat.runs} off ${bat.balls}';
    if (runs == 4) {
      _addCommentary(
          '${fh}FOUR! ${_pick(["Cracked through the covers", "Pierces the gap", "Races away to the fence", "Timed to perfection", "Driven beautifully", "Pulled away to the boundary", "Finds the gap, no need to run"])} by $batter. $sc.',
          kind: 'four');
      // 🔥 Save Highlight for 4
      matchHighlights.add(HighlightClip(
        path: 'dummy_four_${DateTime.now().millisecondsSinceEpoch}.mp4',
        kind: 'FOUR',
        player: batter,
        info: sc,
      ));
    } else if (runs == 6) {
      _addCommentary(
          '${fh}SIX! ${_pick(["Launched into the stands", "That is out of the ground", "Clean strike", "Massive hit", "Dispatched over long on", "Lofted high and handsome"])} from $batter! $sc.',
          kind: 'six');
      // 🔥 Save Highlight for 6
      matchHighlights.add(HighlightClip(
        path: 'dummy_six_${DateTime.now().millisecondsSinceEpoch}.mp4',
        kind: 'SIX',
        player: batter,
        info: sc,
      ));
    } else if (runs == 0) {
      final d = _trailingDots();
      _addCommentary(d >= 3
          ? '$d dot balls in a row! $bowler is building pressure on $batter.'
          : '${_pick(["Dot ball", "Beaten outside off", "Defended solidly", "No run"])}. $bowler keeps it tight.');
    } else if (runs == 1) {
      _addCommentary(
          '$fh${_pick(["Worked away for a single", "Nudged into the gap for one", "Quick single taken", "Pushed to the on side, easy single"])}. $batter on ${bat.runs}.',
          kind: 'run');
    } else if (runs == 2) {
      _addCommentary(
          '$fh${_pick(["Placed in the gap, they hurry back for two", "Good running, two runs", "Pushed hard, two more"])}. $batter on ${bat.runs}.',
          kind: 'run');
    } else if (runs == 3) {
      _addCommentary('${fh}Excellent running between the wickets! Three runs for $batter.',
          kind: 'run');
    } else {
      _addCommentary('$fh$runs runs to $batter.', kind: 'run');
    }

    _boundaryFx(runs, batter);

    if (prev < 50 && bat.runs >= 50) {
      _spawnConfetti(90, _goldPalette);
      _flash(Colors.amber);
      _triggerCelebration('FIFTY', batter, playerImages[batter],
          sub: '${bat.runs} (${bat.balls}) • ${bat.fours}x4 ${bat.sixes}x6');
      _addCommentary(
          'FIFTY! Brilliant half-century for $batter, ${bat.runs} off ${bat.balls} balls with ${bat.fours} four${bat.fours == 1 ? "" : "s"} and ${bat.sixes} six${bat.sixes == 1 ? "" : "es"}.',
          kind: 'milestone');
      // 🔥 Save Highlight for 50
      matchHighlights.add(HighlightClip(
        path: 'dummy_fifty_${DateTime.now().millisecondsSinceEpoch}.mp4',
        kind: 'FIFTY',
        player: batter,
        info: '${bat.runs} (${bat.balls})',
      ));
    }
    if (prev < 100 && bat.runs >= 100) {
      _spawnConfetti(130, _goldPalette, seconds: 3.4);
      _flash(Colors.amber);
      _triggerCelebration('CENTURY', batter, playerImages[batter],
          sub: '${bat.runs} (${bat.balls}) • ${bat.fours}x4 ${bat.sixes}x6');
      _addCommentary(
          'CENTURY! Magnificent hundred by $batter, ${bat.runs} off ${bat.balls} balls. What an innings!',
          kind: 'milestone');
    }
    if (prevP < 50 && partnershipRuns >= 50) {
      _addCommentary(
          'Fifty partnership between $strikerName and $nonStrikerName, ${partnershipBalls} balls so far.',
          kind: 'milestone');
    }

    if (runs.isOdd) setState(swapStrike);
    _afterBall();
  }

  void addExtra(String type, {int runs = 0}) {
    if (_locked) return;
    HapticFeedback.lightImpact();
    _saveHistory();

    final batter = strikerName;
    final bat = _bat(batter);
    final bowl = _bowl(bowlerName);
    final prev = bat.runs;
    String label;
    bool shouldSwap = true; // 🔥 Track if strike should swap

    if (type == 'WD') {
      // 🔥 NEW ADDITION: Wide + boundary = 2 runs & no strike change
      int total = (runs == 4) ? 2 : 1 + runs;
      
      if (runs == 4) {
        label = 'WD+4(2 Runs)';
        shouldSwap = false;
      } else {
        label = runs == 0 ? 'WD' : 'WD+$runs';
        shouldSwap = runs.isOdd;
      }

      setState(() {
        currentOverBalls.add(_Ball(
            label: label, runs: total, bowlerRuns: total, legal: false, kind: _BallKind.wide));
        totalRuns += total;
        extras += total;
        bowl.runs += total;
        partnershipRuns += total;
      });
      _addCommentary(runs == 4
          ? 'Wide, but it goes to the boundary! Only 2 runs given. Strike will not change.'
          : (runs == 0
              ? _pick([
                  'Wide! Too far down the leg side.',
                  'Wide called, that has drifted away from the batter.',
                  'Wayward from $bowlerName, that is a wide.',
                ])
              : 'Wide, and they scamper $runs more. $total added to the total.'));
    } else if (type == 'NB') {
      final total = 1 + runs;
      label = runs == 0 ? 'NB' : 'NB+$runs';
      setState(() {
        currentOverBalls.add(_Ball(
            label: label, runs: total, bowlerRuns: total, legal: false, kind: _BallKind.noBall));
        totalRuns += total;
        extras += 1;
        bat.runs += runs;
        bat.balls++;
        if (runs == 4) bat.fours++;
        if (runs == 6) bat.sixes++;
        bowl.runs += total;
        partnershipRuns += total;
        partnershipBalls++;
        freeHit = true;
      });
      _addCommentary(
          'No ball! ${runs > 0 ? "$batter hits $runs off it. " : ""}FREE HIT coming up, $bowlerName must be careful.',
          kind: 'milestone');
      if (runs == 4 || runs == 6) _boundaryFx(runs, batter);
      if (prev < 50 && bat.runs >= 50) {
        _spawnConfetti(90, _goldPalette);
        _triggerCelebration('FIFTY', batter, playerImages[batter],
            sub: '${bat.runs} (${bat.balls})');
      }
      shouldSwap = runs.isOdd;
    } else {
      final isBye = type == 'BYE';
      label = '${isBye ? "B" : "LB"}$runs';
      setState(() {
        currentOverBalls.add(_Ball(
            label: label,
            runs: runs,
            bowlerRuns: 0,
            legal: true,
            kind: isBye ? _BallKind.bye : _BallKind.legBye));
        totalRuns += runs;
        extras += runs;
        legalBalls++;
        bat.balls++;
        bowl.legalBalls++;
        partnershipRuns += runs;
        partnershipBalls++;
        freeHit = false;
      });
      _addCommentary(isBye
          ? 'Beats the bat and the keeper, $runs bye${runs == 1 ? "" : "s"}.'
          : 'Off the pads, $runs leg bye${runs == 1 ? "" : "s"}.');
      shouldSwap = runs.isOdd;
    }

    _triggerHitAction(label);
    _fieldEvent(
      type == 'WD'
          ? 'WD'
          : (type == 'NB' && runs > 0)
              ? '$runs'
              : 'X',
      label,
    );
    
    // 🔥 Apply strike change only if custom rules allow
    if (shouldSwap) setState(swapStrike);
    
    _afterBall();
  }

  // ---- wickets
  void _showWicketSheet() {
    if (_locked) return;
    final types = freeHit
        ? ['Run Out']
        : ['Bowled', 'Caught', 'LBW', 'Stumped', 'Run Out', 'Hit Wicket'];
    final icons = <String, IconData>{
      'Bowled': Icons.sports_cricket,
      'Caught': Icons.pan_tool,
      'LBW': Icons.block,
      'Stumped': Icons.bolt,
      'Run Out': Icons.directions_run,
      'Hit Wicket': Icons.report_problem,
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How was the batsman out?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (freeHit)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('FREE HIT: only Run Out is possible.',
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: types.map((t) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (t == 'Run Out') {
                        _showRunOutDialog();
                      } else {
                        _applyWicket(t);
                      }
                    },
                    child: Container(
                      width: 96,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(icons[t], color: Colors.redAccent),
                          const SizedBox(height: 6),
                          Text(t,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRunOutDialog() {
    bool strikerOut = true;
    int runs = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setD(onTap),
            );
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Run Out', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Who is out?', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                chip(strikerName, strikerOut, () => strikerOut = true),
                chip(nonStrikerName, !strikerOut, () => strikerOut = false),
              ]),
              const SizedBox(height: 16),
              const Text('Runs completed before the run out:',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (int i = 0; i <= 3; i++) chip('$i', runs == i, () => runs = i),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _applyWicket('Run Out',
                    outName: strikerOut ? strikerName : nonStrikerName, runs: runs);
              },
              child: const Text('Confirm',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }

  void _applyWicket(String kind, {String? outName, int runs = 0}) {
    if (_locked) return;
    _saveHistory();

    final batter = strikerName;
    final bowler = bowlerName;
    final out = outName ?? batter;
    final credited = kind != 'Run Out';
    final bat = _bat(batter);
    final bowl = _bowl(bowler);

    String desc;
    switch (kind) {
      case 'Bowled':
        desc = 'b $bowler';
        break;
      case 'Caught':
        desc = 'ct b $bowler';
        break;
      case 'LBW':
        desc = 'lbw b $bowler';
        break;
      case 'Stumped':
        desc = 'st b $bowler';
        break;
      case 'Hit Wicket':
        desc = 'hit wkt b $bowler';
        break;
      default:
        desc = 'run out';
    }

    setState(() {
      currentOverBalls.add(_Ball(
        label: runs > 0 ? 'W+$runs' : 'W',
        runs: runs,
        bowlerRuns: runs,
        legal: true,
        kind: _BallKind.wicket,
      ));
      totalRuns += runs;
      legalBalls++;
      wickets++;
      bat.balls++;
      bat.runs += runs;
      bowl.legalBalls++;
      bowl.runs += runs;
      if (credited) bowl.wickets++;
      _bat(out).out = desc;
      outPlayers.add(out);
      fow.add(_Fow(totalRuns, wickets, out, overs));
      partnershipRuns = 0;
      partnershipBalls = 0;
      freeHit = false;
      if (runs.isOdd) swapStrike();
    });

    HapticFeedback.heavyImpact();
    _triggerHitAction('W');
    _fieldEvent('W', runs > 0 ? 'W+$runs' : 'W');
    _shake();
    _flash(Colors.redAccent);
    _pulseGlow(Colors.redAccent);
    _spawnConfetti(36, _wicketPalette);
    _triggerCelebration(
      'WICKET',
      credited ? bowler : out,
      credited ? playerImages[bowler] : playerImages[out],
      sub: '$out • $kind',
    );
    final os = _bat(out);
    String how;
    switch (kind) {
      case 'Bowled':
        how = '$out is bowled by $bowler!';
        break;
      case 'Caught':
        how = '$out is caught! $bowler gets the wicket.';
        break;
      case 'LBW':
        how = '$out is trapped in front, LBW to $bowler!';
        break;
      case 'Stumped':
        how = '$out is stumped! Sharp work behind the stumps, $bowler strikes.';
        break;
      case 'Hit Wicket':
        how = '$out disturbs his own stumps off $bowler!';
        break;
      default:
        how = '$out is run out!';
    }
    final made = os.runs == 0
        ? (os.balls <= 1 ? 'Golden duck!' : 'Out for a duck!')
        : '${os.runs} off ${os.balls} balls.';
    _addCommentary(
      'OUT! $how $made ${_ord(wickets)} wicket down, $totalRuns/$wickets.',
      kind: 'wicket',
    );

    if (wickets < maxWickets) {
      _showNewBatsmanDialog(out);
    } else {
      _afterBall();
    }
  }

  void _afterBall() {
    bool overEnded = false;

    if (legalBallsThisOver >= 6) {
      overEnded = true;
      final overRuns = currentOverBalls.fold<int>(0, (s, b) => s + b.runs);
      final bowlerOverRuns = currentOverBalls.fold<int>(0, (s, b) => s + b.bowlerRuns);
      final maiden = bowlerOverRuns == 0;
      final bowler = bowlerName;

      setState(() {
        if (maiden) _bowl(bowler).maidens++;
        pastOvers.add(_Over(bowler, List<_Ball>.from(currentOverBalls), overRuns, maiden));
        currentOverBalls = [];
        swapStrike();
        lastOverBowler = bowler;
      });
      final overNo = pastOvers.length;
      _addCommentary(
        maiden
            ? 'MAIDEN! $bowler bowls a superb over, no runs off the bat. $totalRuns/$wickets.${_chaseLine()}'
            : 'End of over $overNo: $overRuns run${overRuns == 1 ? "" : "s"}. Score $totalRuns/$wickets, run rate ${crr.toStringAsFixed(2)}.${_chaseLine()}',
        kind: 'over',
      );
    }

    final inningsOver = legalBalls >= totalBalls || wickets >= maxWickets;
    final chased = currentInnings == 2 && totalRuns >= targetScore;

    if (inningsOver || chased) {
      if (currentInnings == 1) {
        _endFirstInnings();
      } else {
        _endMatch();
      }
    } else if (overEnded) {
      _showBowlerChangeDialog();
    }
  }

  _InningsSummary _currentSummary() => _InningsSummary(
        team: battingTeamName,
        runs: totalRuns,
        wickets: wickets,
        extras: extras,
        overs: overs,
        bat: batStats,
        bowl: bowlStats,
        fow: List<_Fow>.from(fow),
      );

  void _endFirstInnings() {
    _inn1 = _currentSummary();
    _speaker.say(
        _spoken('Innings break. $battingTeamName scored $totalRuns/$wickets in $overs overs. '
            '$bowlingTeamName need ${totalRuns + 1} to win.'),
        clear: true);
    HapticFeedback.mediumImpact();
    setState(() {
      targetScore = totalRuns + 1;
      currentInnings = 2;
      totalRuns = 0;
      wickets = 0;
      legalBalls = 0;
      extras = 0;
      partnershipRuns = 0;
      partnershipBalls = 0;
      freeHit = false;
      batStats = {};
      bowlStats = {};
      fow = [];
      currentOverBalls = [];
      pastOvers = [];
      history = [];
      outPlayers = [];
      playedBowlers = [];
      commentary = [];
      lastOverBowler = '';
      strikerName = '';
      nonStrikerName = '';
      bowlerName = '';
      _showTargetOverlay = true;
      matchHighlights.clear(); // 🔥 Clear highlights for new innings
    });

    Future.delayed(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      setState(() => _showTargetOverlay = false);
      _loadPlayersAndShowSetup(isSecondInnings: true);
    });
  }

  void _endMatch() {
    _inn2 = _currentSummary();
    final chasing = battingTeamName;
    final first = bowlingTeamName;
    String result;
    String winner;

    if (totalRuns >= targetScore) {
      final wl = maxWickets - wickets;
      result = '$chasing won by $wl wicket${wl == 1 ? "" : "s"} '
          '($ballsRemaining ball${ballsRemaining == 1 ? "" : "s"} left)';
      winner = chasing;
    } else if (totalRuns == targetScore - 1) {
      result = 'Match tied! Scores are level.';
      winner = 'TIED';
    } else {
      final by = targetScore - 1 - totalRuns;
      result = '$first won by $by run${by == 1 ? "" : "s"}';
      winner = first;
    }

    _speaker.say(_spoken('Match over. $result.'), clear: true);
    _computeMotm();
    HapticFeedback.heavyImpact();
    setState(() {
      isMatchEnded = true;
      _winnerName = winner;
      _resultText = result;
      _matchStage = 1;
      _celebrationType = null;
    });
    _spawnConfetti(150, _partyPalette, rain: true, seconds: 5);

    Future.delayed(const Duration(milliseconds: 3800), () {
      if (mounted) setState(() => _matchStage = 2);
    });
  }

  void _computeMotm() {
    final pts = <String, int>{};
    final rn = <String, int>{};
    final bl = <String, int>{};
    final wk = <String, int>{};

    void addBat(Map<String, _BatStat> m) => m.forEach((k, v) {
          rn[k] = (rn[k] ?? 0) + v.runs;
          bl[k] = (bl[k] ?? 0) + v.balls;
          pts[k] = (pts[k] ?? 0) + v.runs + (v.runs >= 50 ? 10 : 0) + (v.runs >= 100 ? 15 : 0);
        });
    void addBowl(Map<String, _BowlStat> m) => m.forEach((k, v) {
          wk[k] = (wk[k] ?? 0) + v.wickets;
          pts[k] = (pts[k] ?? 0) + v.wickets * 20 + v.maidens * 6;
        });

    if (_inn1 != null) {
      addBat(_inn1!.bat);
      addBowl(_inn1!.bowl);
    }
    if (_inn2 != null) {
      addBat(_inn2!.bat);
      addBowl(_inn2!.bowl);
    }
    if (pts.isEmpty) return;

    final best = pts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final parts = <String>[];
    if ((bl[best] ?? 0) > 0) parts.add('${rn[best]} (${bl[best]} balls)');
    if ((wk[best] ?? 0) > 0) parts.add('${wk[best]} wkt${wk[best] == 1 ? "" : "s"}');
    _motmName = best;
    _motmLine = parts.join('  •  ');
  }

  Future<void> _pickImage(bool isStriker) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.black87),
                title: const Text('Take Photo (Camera)', style: TextStyle(color: Colors.black87)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? f = await _picker.pickImage(source: ImageSource.camera);
                  _updateImage(f, isStriker);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.black87),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.black87)),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? f = await _picker.pickImage(source: ImageSource.gallery);
                  _updateImage(f, isStriker);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateImage(XFile? pickedFile, bool isStriker) {
    if (pickedFile == null) return;
    setState(() {
      playerImages[isStriker ? strikerName : bowlerName] = File(pickedFile.path);
    });
  }

  void _showExtraSheet(String type) {
    if (_locked) return;
    final opts = type == 'WD'
        ? [0, 1, 2, 3, 4]
        : type == 'NB'
            ? [0, 1, 2, 3, 4, 6]
            : [1, 2, 3, 4];
    final title = type == 'WD'
        ? 'Wide ball'
        : type == 'NB'
            ? 'No ball'
            : type == 'BYE'
                ? 'Byes'
                : 'Leg byes';
    final sub = type == 'WD'
        ? 'Extra runs run on top of the wide penalty'
        : type == 'NB'
            ? 'Runs hit off the bat on the no ball (next ball is a free hit)'
            : 'How many runs were taken?';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: opts.map((n) {
                  final label = (type == 'WD' && n == 0)
                      ? 'Wide only'
                      : (type == 'NB' && n == 0)
                          ? 'No run'
                          : type == 'WD'
                              ? '+$n'
                              : '$n';
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(ctx);
                      addExtra(type, runs: n);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.withOpacity(0.6)),
                      ),
                      child: Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_InningsSummary> _allInnings() {
    if (currentInnings == 1) return [_currentSummary()];
    return [_inn1!, isMatchEnded && _inn2 != null ? _inn2! : _currentSummary()];
  }

  void _showScorecard() {
    final list = _allInnings();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: DefaultTabController(
              length: list.length,
              initialIndex: list.length - 1,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.black12, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 6),
                  TabBar(
                    labelColor: Colors.blueAccent,
                    unselectedLabelColor: Colors.black45,
                    indicatorColor: Colors.blueAccent,
                    tabs: list
                        .map((s) => Tab(
                              child: Text('${s.team} ${s.runs}/${s.wickets}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ))
                        .toList(),
                  ),
                  Expanded(child: TabBarView(children: list.map(_inningsView).toList())),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sc(String t,
      {int flex = 1, bool bold = false, TextAlign align = TextAlign.center, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(t,
          textAlign: align,
          style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black87)),
    );
  }

  Widget _scHeader(String title, List<String> cols) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          _sc(title, flex: 5, bold: true, align: TextAlign.left, color: Colors.blueAccent),
          for (final c in cols) _sc(c, bold: true, color: Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _inningsView(_InningsSummary s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Text('${s.team}  ${s.runs}/${s.wickets}  (${s.overs} ov)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        _scHeader('BATTING', const ['R', 'B', '4s', '6s', 'SR']),
        for (final e in s.bat.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(e.value.out ?? 'not out',
                          style: TextStyle(
                              fontSize: 11,
                              color: e.value.out == null ? Colors.green : Colors.black45)),
                    ],
                  ),
                ),
                _sc('${e.value.runs}', bold: true),
                _sc('${e.value.balls}'),
                _sc('${e.value.fours}'),
                _sc('${e.value.sixes}'),
                _sc(e.value.sr.toStringAsFixed(0)),
              ],
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text('Extras: ${s.extras}', style: const TextStyle(color: Colors.black54)),
        ),
        _scHeader('BOWLING', const ['O', 'M', 'R', 'W', 'ECO']),
        for (final e in s.bowl.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              children: [
                _sc(e.key, flex: 5, bold: true, align: TextAlign.left),
                _sc(e.value.overs),
                _sc('${e.value.maidens}'),
                _sc('${e.value.runs}'),
                _sc('${e.value.wickets}', bold: true),
                _sc(e.value.econ.toStringAsFixed(1)),
              ],
            ),
          ),
        if (s.fow.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Fall of wickets',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 6),
          Text(
            s.fow.map((f) => '${f.wicket}-${f.runs} (${f.name}, ${f.over} ov)').join(',  '),
            style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }

  MatchReportData _reportData() {
    PdfInnings conv(_InningsSummary s) => PdfInnings(
          team: s.team,
          runs: s.runs,
          wickets: s.wickets,
          extras: s.extras,
          overs: s.overs,
          batters: s.bat.entries
              .map((e) => PdfBatter(
                  name: e.key,
                  runs: e.value.runs,
                  balls: e.value.balls,
                  fours: e.value.fours,
                  sixes: e.value.sixes,
                  out: e.value.out))
              .toList(),
          bowlers: s.bowl.entries
              .map((e) => PdfBowler(
                  name: e.key,
                  overs: e.value.overs,
                  maidens: e.value.maidens,
                  runs: e.value.runs,
                  wickets: e.value.wickets))
              .toList(),
          fow: s.fow.map((f) => '${f.wicket}-${f.runs} (${f.name}, ${f.over} ov)').toList(),
        );

    return MatchReportData(
      title: '${widget.teamAName} vs ${widget.teamBName}',
      totalOvers: widget.totalOvers,
      result: _resultText,
      innings: [if (_inn1 != null) conv(_inn1!), if (_inn2 != null) conv(_inn2!)],
      motmName: _motmName,
      motmLine: _motmLine,
      photo: _TeamPhotoCard.bytes,
    );
  }

  void _openPdfSheet() => showPdfOptions(context, _reportData());

  Future<bool> _onWillPop() async {
    if (isMatchEnded || (currentInnings == 1 && legalBalls == 0 && totalRuns == 0)) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave match?'),
        content: const Text('Live scoring progress will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // =========================================================================
  //  BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live Scoring',
                  style: TextStyle(
                      color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${widget.teamAName} vs ${widget.teamBName}',
                  style: const TextStyle(color: Colors.black45, fontSize: 12)),
            ],
          ),
          actions: [
            IconButton(
                tooltip: 'Swap strike',
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: _manualSwap),
            IconButton(
                tooltip: 'Scorecard',
                icon: const Icon(Icons.table_chart_rounded),
                onPressed: _showScorecard),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.07,
                  child: Image.memory(_TeamPhotoCard.bytes,
                      fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(child: _buildBackgroundImage(strikerImage)),
                  Expanded(child: _buildBackgroundImage(bowlerImage)),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _shakeCtrl,
              builder: (context, child) {
                final t = _shakeCtrl.value;
                final dx = math.sin(t * math.pi * 10) * (1 - t) * 9;
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        _buildHero(),
                        _buildPlayerCards(),
                        _buildOverCard(),
                        TeamPhotoGallery(first: _TeamPhotoCard.bytes),
                      ],
                    ),
                  ),
                  _buildControls(),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flashCtrl,
                  builder: (context, _) {
                    final v = _flashCtrl.value;
                    if (v >= 1) return const SizedBox.shrink();
                    return Container(color: _flashColor.withOpacity((1 - v) * 0.28));
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _showTargetOverlay
                    ? _buildTargetOverlay()
                    : const SizedBox.shrink(key: ValueKey('no-target')),
              ),
            ),
            _buildSmallCelebration(),
            if (_matchStage != 0) Positioned.fill(child: _buildMatchEnd()),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ConfettiPainter(_confettiCtrl, _particles)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final chase = currentInnings == 2;
    final need = targetScore - totalRuns;
    final progress = chase
        ? (targetScore == 0 ? 0.0 : totalRuns / targetScore)
        : legalBalls / math.max(1, totalBalls);
    final onTrack = crr >= rrr;
    final barColor = chase
        ? (need <= 0 ? Colors.greenAccent : (onTrack ? Colors.lightGreenAccent : Colors.orangeAccent))
        : Colors.lightBlueAccent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111B3A), Color(0xFF1F3C88)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: _glowColor.withOpacity(0.45), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: CustomPaint(painter: _HeroMotionPainter(_pulseCtrl)),
              ),
            ),
          ),
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      battingTeamName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('INN $currentInnings • OV $currentOverNumber/${widget.totalOvers}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  _liveBadge(),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, bc) {
                      final scoreW =
                          '$totalRuns'.length * 33.0 + 18 + '$wickets'.length * 19.0;
                      final showMomentum = bc.maxWidth - scoreW >= 80;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (showMomentum)
                            Positioned(right: 2, top: 0, child: _buildMomentum()),
                          Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _RollingText('$totalRuns',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                    height: 1.05)),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text('/',
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w300)),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _RollingText('$wickets',
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Overs $overs / ${widget.totalOvers}',
                            style: const TextStyle(
                                color: Colors.lightGreenAccent,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: freeHit ? _freeHitBadge() : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                        ],
                      );
                    }),
                  ),
                  _buildGround(),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _heroPill('CRR', crr.toStringAsFixed(2))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: chase
                        ? _heroPill('RRR', need <= 0 ? '0.00' : rrr.toStringAsFixed(2),
                            valueColor: onTrack ? Colors.lightGreenAccent : Colors.orangeAccent)
                        : _heroPill('PROJ', '$projected'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _heroPill('EXTRAS', '$extras')),
                  const SizedBox(width: 8),
                  Expanded(child: _heroPill("P'SHIP", '$partnershipRuns ($partnershipBalls)')),
                ],
              ),
              const SizedBox(height: 14),
              _progressBar(progress, barColor),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    chase
                        ? (need > 0 ? 'Need $need from $ballsRemaining balls' : 'Target achieved!')
                        : 'Overs bowled ${(progress * 100).round()}%',
                    style: TextStyle(
                        color: chase ? Colors.orangeAccent : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(chase ? 'Target $targetScore' : 'Proj. $projected',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
              if (chase) ...[
                const SizedBox(height: 12),
                _winBar(),
              ],
            ],
          ),
          _buildHitFloat(),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5 + 0.5 * _pulseCtrl.value),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text('LIVE',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }

  Widget _freeHitBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.75 + 0.25 * _pulseCtrl.value),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.amber.withOpacity(0.5 * _pulseCtrl.value),
                  blurRadius: 12,
                  spreadRadius: 1),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flash_on, size: 14, color: Colors.black87),
              SizedBox(width: 3),
              Text('FREE HIT',
                  style: TextStyle(
                      color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildMomentum() {
    List<_Ball> balls = currentOverBalls;
    bool dim = false;
    if (balls.isEmpty && pastOvers.isNotEmpty) {
      balls = pastOvers.last.balls; 
      dim = true;
    }
    final shown = balls.length > 6 ? balls.sublist(balls.length - 6) : balls;

    Color colorOf(_Ball b) {
      switch (b.kind) {
        case _BallKind.four:
          return const Color(0xFF448AFF);
        case _BallKind.six:
          return const Color(0xFFB388FF);
        case _BallKind.wicket:
          return const Color(0xFFFF5252);
        case _BallKind.wide:
        case _BallKind.noBall:
        case _BallKind.bye:
        case _BallKind.legBye:
          return const Color(0xFFFFB300);
        case _BallKind.dot:
          return const Color(0xFF90A4AE);
        default:
          return const Color(0xFF69F0AE);
      }
    }

    double heightOf(_Ball b) {
      switch (b.kind) {
        case _BallKind.six:
          return 54;
        case _BallKind.wicket:
          return 46;
        case _BallKind.four:
          return 40;
        case _BallKind.dot:
          return 7;
        case _BallKind.wide:
        case _BallKind.noBall:
          return 16;
        case _BallKind.bye:
        case _BallKind.legBye:
          return 14;
        default:
          return 10.0 + b.runs * 7;
      }
    }

    return SizedBox(
      width: 68,
      height: 62,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final ms = DateTime.now().millisecondsSinceEpoch / 1000.0;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1.2, color: Colors.white24),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < 6; i++)
                    if (i < shown.length)
                      TweenAnimationBuilder<double>(
                        key: ValueKey('mom-$i-${shown[i].label}-${shown.length}'),
                        tween: Tween<double>(begin: 0, end: heightOf(shown[i])),
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOutBack,
                        builder: (context, h, _) {
                          final c = colorOf(shown[i]);
                          final big = shown[i].kind == _BallKind.four ||
                              shown[i].kind == _BallKind.six ||
                              shown[i].kind == _BallKind.wicket;
                          final breathe = 1.6 * math.sin(ms * 3 + i * 0.9);
                          final hh = math.max(3.0, h + (h > 8 ? breathe : 0));
                          return Container(
                            width: 7,
                            height: hh,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  c.withOpacity(dim ? 0.35 : 0.65),
                                  c.withOpacity(dim ? 0.55 : 1.0),
                                ],
                              ),
                              boxShadow: big && !dim
                                  ? [BoxShadow(color: c.withOpacity(0.55), blurRadius: 7)]
                                  : null,
                            ),
                          );
                        },
                      )
                    else
                      Container(
                        width: 7,
                        height: 4 + 1.5 * (0.5 + 0.5 * math.sin(ms * 2.4 + i)),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _lastBallBadge(_Ball b) {
    Color c;
    switch (b.kind) {
      case _BallKind.four:
        c = const Color(0xFF2979FF);
        break;
      case _BallKind.six:
        c = const Color(0xFF7C4DFF);
        break;
      case _BallKind.wicket:
        c = const Color(0xFFE53935);
        break;
      case _BallKind.wide:
      case _BallKind.noBall:
      case _BallKind.bye:
      case _BallKind.legBye:
        c = const Color(0xFFEF8F00);
        break;
      case _BallKind.dot:
        c = const Color(0xFF607D8B);
        break;
      default:
        c = const Color(0xFF2E9E4F);
    }
    return Column(
      key: ValueKey('badge-${pastOvers.length}-${currentOverBalls.length}-$totalRuns-$wickets'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.2),
            boxShadow: [BoxShadow(color: c.withOpacity(0.6), blurRadius: 9)],
          ),
          child: Center(
            widthFactor: 1,
            child: Text(b.label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: b.label.length > 2 ? 10.5 : 14,
                    fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 2),
        const Text('VS',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      ],
    );
  }

  Widget _buildGround() {
    _Ball? last;
    if (currentOverBalls.isNotEmpty) {
      last = currentOverBalls.last;
    } else if (pastOvers.isNotEmpty && pastOvers.last.balls.isNotEmpty) {
      last = pastOvers.last.balls.last;
    }

    final _Ball? lastBall = last; 

    String runText(_Ball b) {
      final r = b.runs;
      final s = r == 1 ? '' : 's';
      switch (b.kind) {
        case _BallKind.wicket:
          return r > 0 ? 'Wicket + $r run$s' : 'Wicket';
        case _BallKind.wide:
          return 'Wide - $r run$s';
        case _BallKind.noBall:
          return 'No ball - $r run$s';
        case _BallKind.bye:
          return 'Bye - $r run$s';
        case _BallKind.legBye:
          return 'Leg bye - $r run$s';
        case _BallKind.dot:
          return 'Dot ball (0 run)';
        default:
          return '$r run$s';
      }
    }

    Widget avatar(String name, String fallback, String role, File? img, Color ring,
        bool isStriker, double glow) {
      return SizedBox(
        width: 54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: name.isEmpty ? null : () => _pickImage(isStriker),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                  boxShadow: [BoxShadow(color: ring.withOpacity(0.45), blurRadius: glow)],
                ),
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.white24,
                  backgroundImage: img != null ? FileImage(img) : null,
                  child: img == null
                      ? Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name.isEmpty ? fallback : name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
            Text(role,
                style: TextStyle(
                    color: ring, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ],
        ),
      );
    }

    return SizedBox(
      width: 142,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_fieldCtrl, _pulseCtrl]),
            builder: (context, _) {
              final tv = _fieldCtrl.value;
              final act = tv > 0 && tv < 1 && _fieldKind.isNotEmpty;
              final t = act ? tv : 0.0;
              final glow = 7 + 6 * _pulseCtrl.value;

              Color strikerRing = Colors.lightGreenAccent;
              if (act && t >= _DuelPainter.contact && t < 0.88) {
                if (_fieldKind == 'W') {
                  strikerRing = Colors.redAccent;
                } else if (_fieldKind == '4') {
                  strikerRing = Colors.lightBlueAccent;
                } else if (_fieldKind == '6') {
                  strikerRing = Colors.purpleAccent;
                }
              }

              double shake = 0, jump = 0;
              if (act && t >= _DuelPainter.contact) {
                final k = (1 - (t - _DuelPainter.contact) / 0.4).clamp(0.0, 1.0).toDouble();
                if (_fieldKind == 'W') shake = math.sin(t * 90) * 3 * k;
                if ((_fieldKind == '4' || _fieldKind == '6') && t < _DuelPainter.contact + 0.24) {
                  jump = -math.sin(math.pi * (t - _DuelPainter.contact) / 0.24) * 5;
                }
              }
              final labelA = act ? _DuelPainter.labelAlpha(t) : 0.0;
              final bob = act ? 0.0 : math.sin(_pulseCtrl.value * math.pi) * 1.5;

              return SizedBox(
                height: 82,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                            painter: _DuelBgPainter(_fieldCtrl, _pulseCtrl, _fieldKind)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Transform.translate(
                        offset: Offset(shake, jump),
                        child: Transform.rotate(
                          angle: _DuelPainter.batAngle(t, _fieldKind, act),
                          alignment: Alignment.bottomCenter,
                          child: avatar(strikerName, 'Batter', 'BAT', strikerImage, strikerRing,
                              true, glow),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Transform.translate(
                        offset: Offset(_DuelPainter.bowlerDx(t), bob),
                        child: avatar(bowlerName, 'Bowler', 'BOWL', bowlerImage,
                            Colors.orangeAccent, false, glow),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 9,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          switchInCurve: Curves.easeOutBack,
                          transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim, child: ScaleTransition(scale: anim, child: child)),
                          child: (act || lastBall == null)
                              ? Opacity(
                                  key: const ValueKey('vs'),
                                  opacity: (1 - labelA).clamp(0.0, 1.0).toDouble(),
                                  child: const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text('VS',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            fontStyle: FontStyle.italic,
                                            letterSpacing: 1)),
                                  ),
                                )
                              : _lastBallBadge(lastBall),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _DuelPainter(
                              _fieldCtrl, _pulseCtrl, _fieldKind, _fieldLabel, _fieldAngle),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          if (last == null)
            const Text('Ready to bowl', style: TextStyle(color: Colors.white54, fontSize: 11))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBallChip(last,
                    size: 30,
                    key: ValueKey(
                        'hero-${pastOvers.length}-${currentOverBalls.length}-$totalRuns-$wickets')),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(runText(last),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _heroPill(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _RollingText(value,
                  style: TextStyle(
                      color: valueColor ?? Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar(double v, Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: v.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, val, _) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: val,
          minHeight: 8,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }

  Widget _winBar() {
    final p = winProbability;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.5, end: p),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, val, _) {
        final left = (val * 100).round();
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text('$battingTeamName $left%',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.lightGreenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const Text('WIN CHANCE (est.)',
                    style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.8)),
                Flexible(
                  child: Text('${100 - left}% $bowlingTeamName',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    Expanded(
                        flex: (val * 1000).round().clamp(1, 999).toInt(),
                        child: Container(color: Colors.lightGreenAccent)),
                    Expanded(
                        flex: ((1 - val) * 1000).round().clamp(1, 999).toInt(),
                        child: Container(color: Colors.redAccent)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHitFloat() {
    if (!_showHitAction) return const SizedBox.shrink();
    Color color;
    switch (_lastAction) {
      case '4':
        color = Colors.lightBlueAccent;
        break;
      case '6':
        color = Colors.orangeAccent;
        break;
      case 'W':
        color = Colors.redAccent;
        break;
      default:
        color = Colors.white;
    }
    return Positioned(
      left: 20,
      top: 56,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_hitCounter),
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, v, _) => Transform.translate(
            offset: Offset(70 * v, -46 * v),
            child: Opacity(
              opacity: (1 - v).clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(
                scale: 0.8 + 0.9 * v,
                child: Text(
                  _lastAction,
                  style: TextStyle(
                    color: color,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 16)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCards() {
    final bowl = bowlerName.isEmpty ? null : bowlStats[bowlerName];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: _cardDecoration(Colors.green),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _batterRow(strikerName, true),
                    const Divider(color: Colors.black12, height: 16),
                    _batterRow(nonStrikerName, false),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: _cardDecoration(Colors.orange),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sports_baseball, color: Colors.orange, size: 15),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            layoutBuilder: _leftLayout,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                        begin: const Offset(0.3, 0), end: Offset.zero)
                                    .animate(anim),
                                child: child,
                              ),
                            ),
                            child: Text(
                              bowlerName.isEmpty ? 'Bowler' : bowlerName,
                              key: ValueKey('bw$bowlerName'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: bowlerName.isEmpty ? null : () => _pickImage(false),
                          child: Icon(
                            bowlerImage != null ? Icons.check_circle : Icons.camera_alt,
                            color: bowlerImage != null ? Colors.green : Colors.grey,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _RollingText('${bowl?.wickets ?? 0}/${bowl?.runs ?? 0}',
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text('${bowl?.overs ?? "0.0"} ov',
                            style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Econ ${(bowl?.econ ?? 0).toStringAsFixed(1)}  •  M ${bowl?.maidens ?? 0}',
                      style: const TextStyle(color: Colors.black45, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(Color border) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      );

  Widget _pulseDot() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.green.withOpacity(0.55),
                blurRadius: 3 + 5 * _pulseCtrl.value,
                spreadRadius: 1 + 2 * _pulseCtrl.value),
          ],
        ),
      ),
    );
  }

  Widget _batterRow(String name, bool striker) {
    final st = name.isEmpty ? null : batStats[name];
    final color = striker ? Colors.green.shade700 : Colors.black54;
    return Row(
      children: [
        SizedBox(width: 14, child: striker ? _pulseDot() : null),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      layoutBuilder: _leftLayout,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        name.isEmpty ? (striker ? 'Striker' : 'Non-Striker') : name,
                        key: ValueKey('$striker-$name'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color,
                            fontSize: striker ? 14 : 13,
                            fontWeight: striker ? FontWeight.bold : FontWeight.w500),
                      ),
                    ),
                  ),
                  if (striker)
                    InkWell(
                      onTap: name.isEmpty ? null : () => _pickImage(true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          strikerImage != null ? Icons.check_circle : Icons.camera_alt,
                          color: strikerImage != null ? Colors.green : Colors.grey,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                st == null
                    ? ' '
                    : 'SR ${st.sr.toStringAsFixed(0)}  •  4s ${st.fours}  •  6s ${st.sixes}',
                style: const TextStyle(color: Colors.black38, fontSize: 10.5),
              ),
            ],
          ),
        ),
        _RollingText('${st?.runs ?? 0}',
            style: TextStyle(
                color: Colors.black87,
                fontSize: striker ? 18 : 15,
                fontWeight: FontWeight.w800)),
        Text(' (${st?.balls ?? 0})',
            style: const TextStyle(color: Colors.black45, fontSize: 12)),
      ],
    );
  }

  Widget _buildBallChip(_Ball ball,
      {double size = 36, Key? key, bool animate = true}) {
    Color bg = Colors.grey.shade200;
    Color fg = Colors.black87;
    switch (ball.kind) {
      case _BallKind.four:
        bg = Colors.blueAccent.withOpacity(0.2);
        fg = Colors.blueAccent;
        break;
      case _BallKind.six:
        bg = Colors.orange.withOpacity(0.2);
        fg = Colors.orange.shade800;
        break;
      case _BallKind.wicket:
        bg = Colors.redAccent;
        fg = Colors.white;
        break;
      case _BallKind.wide:
      case _BallKind.noBall:
        bg = Colors.amber.withOpacity(0.3);
        fg = Colors.amber.shade900;
        break;
      case _BallKind.bye:
      case _BallKind.legBye:
        bg = Colors.teal.withOpacity(0.15);
        fg = Colors.teal.shade700;
        break;
      case _BallKind.dot:
        fg = Colors.black45;
        break;
      case _BallKind.run:
        break;
    }

    final chip = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.all(size * 0.16),
          child: Text(ball.label,
              style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      ),
    );

    if (!animate) return chip;
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: chip,
    );
  }

  Widget _buildOverCard() {
    final legal = legalBallsThisOver;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('This Over',
                  style: TextStyle(
                      color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
              Flexible(
                child: Text(
                  bowlerName.isEmpty ? '' : 'Over $currentOverNumber • $bowlerName',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black45, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              6,
              (i) => Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < legal ? Colors.green : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (currentOverBalls.isEmpty)
            const Text('No balls bowled yet in this over.',
                style: TextStyle(color: Colors.black38, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < currentOverBalls.length; i++)
                  _buildBallChip(currentOverBalls[i],
                      key: ValueKey('o${pastOvers.length}-$i')),
              ],
            ),
          if (pastOvers.isNotEmpty) ...[
            const Divider(color: Colors.black12, height: 28),
            const Text('Previous Overs',
                style: TextStyle(
                    color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pastOvers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final idx = pastOvers.length - 1 - i;
                  return _pastOverCard(idx + 1, pastOvers[idx]);
                },
              ),
            ),
          ],
          const Divider(color: Colors.black12, height: 28),
          Row(
            children: [
              const Text('Commentary',
                  style: TextStyle(
                      color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _speaker.enabled = !_speaker.enabled);
                  if (_speaker.enabled) {
                    _speaker.say('Commentary on');
                  } else {
                    _speaker.stop();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (_speaker.enabled ? Colors.green : Colors.grey).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: (_speaker.enabled ? Colors.green : Colors.grey).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_speaker.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          size: 16, color: _speaker.enabled ? Colors.green : Colors.grey),
                      const SizedBox(width: 4),
                      Text(_speaker.enabled ? 'Voice on' : 'Voice off',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _speaker.enabled ? Colors.green.shade700 : Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (commentary.isEmpty)
            const Text('No commentary yet.',
                style: TextStyle(color: Colors.black38, fontSize: 12))
          else
            Column(
              children: [
                for (int i = 0; i < commentary.length && i < 8; i++)
                  _CommentaryTile(
                      key: ValueKey(commentary[i].id), entry: commentary[i], latest: i == 0),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pastOverCard(int n, _Over o) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: o.maiden ? Colors.green.withOpacity(0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: o.maiden ? Colors.green.withOpacity(0.4) : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Ov $n  •  ${o.runs} run${o.runs == 1 ? "" : "s"}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if (o.maiden)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('MAIDEN',
                      style: TextStyle(
                          color: Colors.green, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          Text(o.bowler,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black45, fontSize: 11)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: o.balls
                  .map((b) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _buildBallChip(b, size: 24, animate: false),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    String text,
    VoidCallback onTap, {
    List<Color>? colors,
    Color textColor = Colors.black87,
    VoidCallback? onLong,
    IconData? icon,
    double fontSize = 22,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _PressableButton(
          text: icon == null ? text : null,
          icon: icon,
          onTap: onTap,
          onLongPress: onLong,
          colors: colors ?? const [Colors.white, Color(0xFFEFF1F7)],
          textColor: textColor,
          enabled: !_locked,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Widget _buildControls() {
    const blue = [Color(0xFF5C95FF), Color(0xFF2F5BEA)];
    const orange = [Color(0xFFFFA84C), Color(0xFFFF6B3D)];
    const amber = [Color(0xFFFFD54F), Color(0xFFFFB300)];
    const red = [Color(0xFFFF6677), Color(0xFFE53950)];
    const grey = [Color(0xFFE6E9F0), Color(0xFFCDD2DC)];
    const teal = [Color(0xFF4DD0E1), Color(0xFF00ACC1)];
    const purple = [Color(0xFFB388FF), Color(0xFF7C4DFF)];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _btn('0', () => addRuns(0)),
              _btn('1', () => addRuns(1)),
              _btn('2', () => addRuns(2)),
              _btn('3', () => addRuns(3)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _btn('4', () => addRuns(4), colors: blue, textColor: Colors.white),
              _btn('6', () => addRuns(6), colors: orange, textColor: Colors.white),
              _btn('WD', () => addExtra('WD'),
                  colors: amber,
                  textColor: Colors.white,
                  onLong: () => _showExtraSheet('WD'),
                  fontSize: 18),
              _btn('NB', () => addExtra('NB'),
                  colors: amber,
                  textColor: Colors.white,
                  onLong: () => _showExtraSheet('NB'),
                  fontSize: 18),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              // 🔥 NEW: Edge Boundary Button
              _btn('Edge\n(1 Run)', addEdgeBoundaryRun,
                  colors: purple, textColor: Colors.white, fontSize: 12),
              // 🔥 NEW: Wide + 4 Button
              _btn('WD+4\n(2 Runs)', () => addExtra('WD', runs: 4),
                  colors: amber, textColor: Colors.white, fontSize: 12),
              _btn('W', _showWicketSheet, colors: red, textColor: Colors.white),
              _btn('', undo, colors: grey, icon: Icons.undo_rounded),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Tap WD / NB = quick extra  •  Hold = add extra runs',
                  style: TextStyle(color: Colors.black38, fontSize: 10.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundImage(File? image) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: image == null
          ? const SizedBox.expand(key: ValueKey('noimg'))
          : Opacity(
              key: ValueKey(image.path),
              opacity: 0.12,
              child: Image.file(image,
                  fit: BoxFit.cover, height: double.infinity, width: double.infinity),
            ),
    );
  }

  Widget _buildTargetOverlay() {
    final s = _inn1;
    return Container(
      key: const ValueKey('target'),
      color: Colors.white.withOpacity(0.97),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('INNINGS BREAK',
                  style: TextStyle(color: Colors.black54, fontSize: 22, letterSpacing: 3)),
              const SizedBox(height: 6),
              if (s != null)
                Text('${s.team}: ${s.runs}/${s.wickets} (${s.overs} ov)',
                    style: const TextStyle(color: Colors.black45, fontSize: 15)),
              const SizedBox(height: 18),
              const Text('TARGET',
                  style: TextStyle(
                      color: Colors.black87, fontSize: 30, fontWeight: FontWeight.bold)),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: targetScore),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, val, _) => Text('$val',
                    style: const TextStyle(
                        color: Colors.green,
                        fontSize: 92,
                        fontWeight: FontWeight.w900,
                        height: 1.1)),
              ),
              const SizedBox(height: 14),
              Text('${_teamName(widget.bowlingTeamId)} need $targetScore runs to win',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                  'Required rate: ${(targetScore * 6 / math.max(1, totalBalls)).toStringAsFixed(2)} per over',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallCelebration() {
    Color c;
    String title;
    IconData icon;
    switch (_celebrationType) {
      case 'SIX':
        c = Colors.deepPurple;
        title = 'SIX!';
        icon = Icons.rocket_launch;
        break;
      case 'FOUR':
        c = Colors.blueAccent;
        title = 'FOUR!';
        icon = Icons.sports_cricket;
        break;
      case 'FIFTY':
        c = Colors.orange;
        title = 'FIFTY!';
        icon = Icons.emoji_events;
        break;
      case 'CENTURY':
        c = Colors.amber.shade700;
        title = 'CENTURY!';
        icon = Icons.military_tech;
        break;
      default:
        c = Colors.redAccent;
        title = 'WICKET!';
        icon = Icons.bolt;
    }

    Widget card() {
      final nm = (_activePlayerName ?? '').trim();
      return Container(
        key: ValueKey('$_celebrationType$_celebId'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c, c.withOpacity(0.8)]),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 22, spreadRadius: 4)],
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _activePlayerImage != null ? FileImage(_activePlayerImage!) : null,
                child: _activePlayerImage == null
                    ? Text(nm.isEmpty ? '?' : nm[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold))
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 6),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic)),
                    ],
                  ),
                  Text(nm,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  if (_celebrationSub.isNotEmpty)
                    Text(_celebrationSub,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Positioned(
      top: 6,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: _celebrationType == null
              ? const SizedBox(key: ValueKey('none'), width: double.infinity)
              : card(),
        ),
      ),
    );
  }

  Widget _buildMatchEnd() {
    return Container(
      color: Colors.white.withOpacity(0.97),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _matchStage == 1 ? _winnerStage() : _summaryStage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _winnerStage() {
    final tie = _winnerName == 'TIED';
    return Column(
      key: const ValueKey('winner'),
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: const Icon(Icons.emoji_events, color: Colors.amber, size: 120),
        ),
        const SizedBox(height: 12),
        Text(tie ? 'MATCH TIED' : 'WINNER!',
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 3)),
        const SizedBox(height: 10),
        if (!tie)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
            ),
            child: Text(_winnerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.blueAccent, fontSize: 34, fontWeight: FontWeight.w900)),
          ),
        const SizedBox(height: 10),
        Text(_resultText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 16)),
      ],
    );
  }

  Widget _scoreLine(_InningsSummary s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Text(s.team,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          Text('${s.runs}/${s.wickets}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('  (${s.overs})', style: const TextStyle(color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _summaryStage() {
    final img = _motmName.isEmpty ? null : playerImages[_motmName];
    return Column(
      key: const ValueKey('summary'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.emoji_events, color: Colors.amber, size: 56),
        const SizedBox(height: 6),
        const Text('MATCH SUMMARY',
            style: TextStyle(
                color: Colors.black54,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        Text(_resultText,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.blueAccent, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        if (_inn1 != null) _scoreLine(_inn1!),
        if (_inn2 != null) _scoreLine(_inn2!),
        if (_motmName.isNotEmpty)
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 40 * (1 - v)), child: child),
            ),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.15), blurRadius: 20)],
              ),
              child: Column(
                children: [
                  const Text('MAN OF THE MATCH',
                      style: TextStyle(
                          color: Colors.orange, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: img != null ? FileImage(img) : null,
                    child: img == null
                        ? Text(_motmName[0].toUpperCase(),
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold, color: Colors.black))
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(_motmName,
                      style: const TextStyle(
                          color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (_motmLine.isNotEmpty)
                    Text(_motmLine,
                        style: const TextStyle(
                            color: Colors.green, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
                const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openPdfSheet,
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            label: const Text('Download PDF',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _showScorecard,
              icon: const Icon(Icons.table_chart_rounded),
              label: const Text('Scorecard'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              ),
              child: const Text('Back to Home',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 20),
TeamPhotoGallery(first: _TeamPhotoCard.bytes, compact: true),      ],
    );
  }
}

// ============================================================================
//  EMBEDDED TEAM PHOTO (base64 JPEG, so no asset / pubspec setup is needed)
// ============================================================================
// 🔥 এখানে আপনার আগের সেই লম্বা const String kTeamPhotoBase64 = '...'; অংশটুকু পেস্ট করুন।
const String kTeamPhotoBase64 =
    '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';
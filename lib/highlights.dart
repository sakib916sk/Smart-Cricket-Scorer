import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart'; // 👈 এই লাইনটি অবশ্যই থাকতে হবে
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class HighlightClip {
  final String path, kind, player, info;
  const HighlightClip(
      {required this.path, required this.kind, required this.player, required this.info});
}

class HighlightsScreen extends StatefulWidget {
  final List<HighlightClip> clips;
  const HighlightsScreen({super.key, required this.clips});
  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  static const _filters = ['ALL', 'SIX', 'FOUR', 'FIFTY', 'WICKET'];
  String _filter = 'ALL';
  int _i = 0;
  double _speed = 0.5;
  bool _manualSpeed = false;
  VideoPlayerController? _c;
  int _token = 0;

  List<HighlightClip> get _list =>
      _filter == 'ALL' ? widget.clips : widget.clips.where((c) => c.kind == _filter).toList();

  Color _color(String k) {
    switch (k) {
      case 'SIX':
        return Colors.deepPurpleAccent;
      case 'FOUR':
        return Colors.blueAccent;
      case 'FIFTY':
      case 'CENTURY':
        return Colors.amber;
      default:
        return Colors.redAccent;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token++;
    _c?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    final old = _c;
    setState(() => _c = null);
    await WidgetsBinding.instance.endOfFrame;
    await old?.dispose();

    final list = _list;
    if (list.isEmpty || !mounted || token != _token) return;
    if (_i >= list.length) _i = 0;
    final clip = list[_i];

    final c = VideoPlayerController.file(File(clip.path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (!mounted || token != _token) {
      await c.dispose();
      return;
    }
    if (!_manualSpeed) {
      _speed = (clip.kind == 'SIX' || clip.kind == 'FIFTY' || clip.kind == 'CENTURY') ? 0.5 : 1.0;
    }
    await c.setPlaybackSpeed(_speed);
    var done = false;
    c.addListener(() {
      if (!mounted || done) return;
      if (c.value.isCompleted) {
        done = true;
        _next(auto: true);
      }
    });
    setState(() => _c = c);
    await c.play();
  }

  void _next({bool auto = false}) {
    final n = _list.length;
    if (n == 0) return;
    if (auto && _i >= n - 1) return; // reel shesh
    _i = (_i + 1) % n;
    _load();
  }

  void _prev() {
    final n = _list.length;
    if (n == 0) return;
    _i = (_i - 1 + n) % n;
    _load();
  }

  void _setSpeed(double s) {
    _manualSpeed = true;
    _c?.setPlaybackSpeed(s);
    setState(() => _speed = s);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final clip = (list.isNotEmpty && _i < list.length) ? list[_i] : null;
    final c = _c;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Highlights  ${list.isEmpty ? 0 : _i + 1}/${list.length}'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      onSelected: (_) {
                        _filter = f;
                        _i = 0;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: (c != null && c.value.isInitialized && clip != null)
                  ? Stack(
                      alignment: Alignment.topLeft,
                      children: [
                        AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _color(clip.kind).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${clip.kind}!',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        fontStyle: FontStyle.italic)),
                                Text(clip.player,
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w700)),
                                Text(clip.info,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(list.isEmpty ? 'No clips yet' : 'Loading...',
                      style: const TextStyle(color: Colors.white54)),
            ),
          ),
          if (c != null && c.value.isInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: VideoProgressIndicator(c, allowScrubbing: true),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        iconSize: 36,
                        color: Colors.white,
                        onPressed: _prev,
                        icon: const Icon(Icons.skip_previous_rounded)),
                    if (c != null)
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: c,
                        builder: (_, v, __) => IconButton(
                          iconSize: 52,
                          color: Colors.white,
                          onPressed: () => v.isPlaying ? c.pause() : c.play(),
                          icon: Icon(v.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded),
                        ),
                      ),
                    IconButton(
                        iconSize: 36,
                        color: Colors.white,
                        onPressed: () => _next(),
                        icon: const Icon(Icons.skip_next_rounded)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final s in [0.25, 0.5, 1.0])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(s == 1.0 ? '1x' : '${s}x'),
                          selected: _speed == s,
                          onSelected: (_) => _setSpeed(s),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
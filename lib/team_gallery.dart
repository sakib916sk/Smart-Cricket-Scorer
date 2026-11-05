import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'team_photos.dart';

/// Swipeable + auto-sliding team photo card.
///
/// Usage:  TeamPhotoGallery(first: someBytes)               // normal card
///         TeamPhotoGallery(first: someBytes, compact: true) // smaller card
///
/// `first` (optional) is shown as the first slide, then the photos from
/// team_photos.dart follow.
class TeamPhotoGallery extends StatefulWidget {
  final Uint8List? first;
  final bool compact;
  const TeamPhotoGallery({super.key, this.first, this.compact = false});

  static List<Uint8List>? _decoded;
  static List<Uint8List> get _extra =>
      _decoded ??= kTeamGalleryBase64.map(base64Decode).toList();

  @override
  State<TeamPhotoGallery> createState() => _TeamPhotoGalleryState();
}

class _TeamPhotoGalleryState extends State<TeamPhotoGallery> {
  final PageController _pc = PageController();
  Timer? _timer;
  int _index = 0;

  List<Uint8List> get _photos => [
        if (widget.first != null) widget.first!,
        ...TeamPhotoGallery._extra,
      ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pc.hasClients) return;
      final n = _photos.length;
      if (n < 2) return;
      _pc.animateToPage(
        (_index + 1) % n,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Widget _slide(Uint8List bytes) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // blurred copy fills the card, the sharp photo is fully visible on top
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        Container(color: Colors.black26),
        Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ],
    );
  }

  void _openFull(BuildContext context) {
    final photos = _photos;
    final ctrl = PageController(initialPage: _index);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: PageView.builder(
                  controller: ctrl,
                  itemCount: photos.length,
                  itemBuilder: (_, i) => Container(
                    color: Colors.black,
                    child: InteractiveViewer(
                      child: Image.memory(photos[i], fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
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
    ).then((_) => ctrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final compact = widget.compact;

    return Container(
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
          SizedBox(
            height: compact ? 170 : 230,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pc,
                  itemCount: photos.length,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _startTimer(); // restart the countdown after a swipe
                  },
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openFull(context),
                    child: _slide(photos[i]),
                  ),
                ),
                // photo counter
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_index + 1}/${photos.length}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
                // caption + dots
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 22, 14, 10),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Cricket Crushers',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900)),
                          ),
                          for (int i = 0; i < photos.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.only(left: 4),
                              width: i == _index ? 14 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _index ? Colors.white : Colors.white54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('This app was designed & built by Sakib',
                      style: TextStyle(color: Colors.black54, fontSize: 12.5)),
                ),
                Icon(Icons.zoom_out_map_rounded, color: Colors.black26, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scoring_screen.dart';

class TossScreen extends StatefulWidget {
  final String teamAId;
  final String teamBId;
  final String teamAName;
  final String teamBName;
  final int totalOvers;

  const TossScreen({
    super.key,
    required this.teamAId,
    required this.teamBId,
    required this.teamAName,
    required this.teamBName,
    required this.totalOvers,
  });

  @override
  State<TossScreen> createState() => _TossScreenState();
}

class _TossScreenState extends State<TossScreen> {
  String? _tossWinner; // team id
  String? _decision; // 'Bat' | 'Bowl'

  static const Color _blue = Color(0xFF2F5BEA);

  // ------------------------------------------------------------------ helpers
  bool get _ready => _tossWinner != null && _decision != null;

  String _nameOf(String id) => id == widget.teamAId ? widget.teamAName : widget.teamBName;
  String _otherId(String id) => id == widget.teamAId ? widget.teamBId : widget.teamAId;

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, math.min(2, parts[0].length)).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // --------------------------------------------------------------- actions
  void _pickWinner(String id) {
    HapticFeedback.selectionClick();
    setState(() => _tossWinner = id);
  }

  void _pickDecision(String d) {
    HapticFeedback.selectionClick();
    setState(() => _decision = d);
  }

  void _startMatch() {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    final winner = _tossWinner!;
    final battingTeamId = _decision == 'Bat' ? winner : _otherId(winner);
    final bowlingTeamId = _decision == 'Bat' ? _otherId(winner) : winner;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${_nameOf(winner)} won the toss and chose to ${_decision == 'Bat' ? 'bat' : 'bowl'} first'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ScoringScreen(
          teamAId: widget.teamAId,
          teamBId: widget.teamBId,
          teamAName: widget.teamAName,
          teamBName: widget.teamBName,
          totalOvers: widget.totalOvers,
          battingTeamId: battingTeamId,
          bowlingTeamId: bowlingTeamId,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Toss',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _matchHeader(),
                    const SizedBox(height: 22),
                    const SizedBox(height: 4),
                    const Text('Who won the toss?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _teamCard(widget.teamAId, widget.teamAName)),
                        const SizedBox(width: 12),
                        Expanded(child: _teamCard(widget.teamBId, widget.teamBName)),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _tossWinner == null
                          ? const SizedBox(width: double.infinity)
                          : _decisionSection(),
                    ),
                  ],
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header
  Widget _matchHeader() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111B3A), Color(0xFF1F3C88)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _headerTeam(widget.teamAName, CrossAxisAlignment.start)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('VS',
                      style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                ),
                Expanded(child: _headerTeam(widget.teamBName, CrossAxisAlignment.end)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sports_cricket, color: Colors.lightGreenAccent, size: 15),
                  const SizedBox(width: 6),
                  Text('${widget.totalOvers} overs match',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerTeam(String name, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white.withOpacity(0.15),
          child: Text(_initials(name),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 6),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ------------------------------------------------------------ team select
  Widget _teamCard(String id, String name) {
    final selected = _tossWinner == id;
    return GestureDetector(
      onTap: () => _pickWinner(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300, width: 1.5),
          boxShadow: selected
              ? [BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: selected ? Colors.white24 : _blue.withOpacity(0.1),
                  child: Text(_initials(name),
                      style: TextStyle(
                          color: selected ? Colors.white : _blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: const CircleAvatar(
                      radius: 9,
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- decision part
  Widget _decisionSection() {
    final winner = _tossWinner!;
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('${_nameOf(winner)} won the toss!',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('What did they choose?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _choiceCard(
                  title: 'Batting',
                  sub: 'Bat first',
                  icon: Icons.sports_cricket,
                  selected: _decision == 'Bat',
                  onTap: () => _pickDecision('Bat'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _choiceCard(
                  title: 'Bowling',
                  sub: 'Bowl first',
                  icon: Icons.sports_baseball,
                  selected: _decision == 'Bowl',
                  onTap: () => _pickDecision('Bowl'),
                ),
              ),
            ],
          ),
          if (_decision != null) ...[
            const SizedBox(height: 16),
            _summaryCard(),
          ],
        ],
      ),
    );
  }

  Widget _choiceCard({
    required String title,
    required String sub,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300, width: 1.5),
          boxShadow: selected
              ? [BoxShadow(color: _blue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.15 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Icon(icon, color: selected ? Colors.white : Colors.grey.shade600, size: 32),
            ),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            Text(sub,
                style: TextStyle(
                    color: selected ? Colors.white60 : Colors.black38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final winner = _tossWinner!;
    final bat = _decision == 'Bat';
    final batting = bat ? winner : _otherId(winner);
    final bowling = bat ? _otherId(winner) : winner;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$winner$_decision'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
        ),
        child: Row(
          children: [
            Expanded(child: _roleTile(Icons.sports_cricket, 'BATTING FIRST', _nameOf(batting), Colors.green)),
            Container(width: 1, height: 38, color: Colors.black12),
            Expanded(child: _roleTile(Icons.sports_baseball, 'BOWLING FIRST', _nameOf(bowling), Colors.orange)),
          ],
        ),
      ),
    );
  }

  Widget _roleTile(IconData icon, String label, String team, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(team,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- start bar
  Widget _bottomBar() {
    final ready = _ready;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: GestureDetector(
        onTap: ready ? _startMatch : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: ready
                  ? const [Color(0xFF5C95FF), Color(0xFF2F5BEA)]
                  : [Colors.grey.shade300, Colors.grey.shade400],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: ready
                ? [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ready ? Icons.play_arrow_rounded : Icons.lock_outline,
                  color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                ready
                    ? 'Start Match'
                    : (_tossWinner == null ? 'Complete the toss first' : 'Choose bat or bowl'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';

class PlayerManagementScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const PlayerManagementScreen({super.key, required this.teamId, required this.teamName});

  @override
  State<PlayerManagementScreen> createState() => _PlayerManagementScreenState();
}

class _PlayerManagementScreenState extends State<PlayerManagementScreen> {
  static const int _maxPlayers = 11;
  static const List<String> _roles = ['Batsman', 'Bowler', 'All-rounder'];
  static const Color _bg = Color(0xFF0F172A);
  static const Color _panel = Color(0xFF1E293B);

  List<Map<String, dynamic>> _players = [];
  bool _isLoading = true;
  String? _filter; // null = all roles

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    try {
      final players = await AppDatabase.getPlayers(widget.teamId);
      if (!mounted) return;
      setState(() {
        _players = List<Map<String, dynamic>>.from(players);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Could not load players', Colors.red);
    }
  }

  // ------------------------------------------------------------------ helpers
  void _snack(String msg, Color color, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        action: action,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'Batsman':
        return Colors.greenAccent;
      case 'Bowler':
        return Colors.orangeAccent;
      case 'All-rounder':
        return Colors.purpleAccent;
      default:
        return Colors.blueGrey.shade200;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'Batsman':
        return Icons.sports_cricket;
      case 'Bowler':
        return Icons.sports_baseball;
      case 'All-rounder':
        return Icons.stars_rounded;
      default:
        return Icons.person_outline;
    }
  }

  int _countRole(String role) => _players.where((p) => p['role'] == role).length;

  bool _nameTaken(String name, {String? exceptId}) {
    final n = name.trim().toLowerCase();
    return _players.any((p) =>
        p['id'] != exceptId && (p['name'] ?? '').toString().trim().toLowerCase() == n);
  }

  // ------------------------------------------------------------- add / edit
  void _showAddEditPlayerDialog({Map<String, dynamic>? existingPlayer}) {
    if (existingPlayer == null && _players.length >= _maxPlayers) {
      _snack('A team cannot have more than $_maxPlayers players!', Colors.red);
      return;
    }

    final nameController =
        TextEditingController(text: (existingPlayer?['name'] ?? '').toString());
    String? selectedRole = existingPlayer?['role'];
    String? error;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> save() async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              setD(() => error = 'Enter the player name');
              return;
            }
            if (_nameTaken(name, exceptId: existingPlayer?['id'])) {
              setD(() => error = '"$name" is already in the squad');
              return;
            }
            try {
              if (existingPlayer == null) {
                await AppDatabase.insertPlayer(
                    const Uuid().v4(), widget.teamId, name, selectedRole);
              } else {
                await AppDatabase.updatePlayer(existingPlayer['id'], name, selectedRole);
              }
              HapticFeedback.lightImpact();
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadPlayers();
            } catch (e) {
              setD(() => error = 'Could not save. Try again.');
            }
          }

          return AlertDialog(
            backgroundColor: _panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                Icon(existingPlayer == null ? Icons.person_add_alt_1 : Icons.edit,
                    color: Colors.blueAccent),
                const SizedBox(width: 10),
                Text(existingPlayer == null ? 'Add Player' : 'Edit Player',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => save(),
                    onChanged: (_) {
                      if (error != null) setD(() => error = null);
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Player Name',
                      labelStyle: TextStyle(color: Colors.blueAccent),
                      prefixIcon: Icon(Icons.person_outline, color: Colors.white54),
                      enabledBorder:
                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                      focusedBorder:
                          UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Role (optional)',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _roles.map((r) {
                      final sel = selectedRole == r;
                      return _pill(
                        label: r,
                        icon: _roleIcon(r),
                        color: _roleColor(r),
                        selected: sel,
                        onTap: () => setD(() => selectedRole = sel ? null : r),
                      );
                    }).toList(),
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
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: save,
                child: const Text('Save',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  // ------------------------------------------------------------- bulk add
  void _showBulkAddDialog() {
    final remaining = _maxPlayers - _players.length;
    if (remaining <= 0) {
      _snack('Squad is full ($_maxPlayers players)', Colors.red);
      return;
    }
    final controller = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          List<String> parse() {
            final seen = <String>{};
            final out = <String>[];
            for (final raw in controller.text.split(RegExp(r'[\n,]'))) {
              final n = raw.trim();
              if (n.isEmpty) continue;
              final k = n.toLowerCase();
              if (seen.contains(k) || _nameTaken(n)) continue;
              seen.add(k);
              out.add(n);
            }
            return out;
          }

          final names = parse();
          final willAdd = names.length > remaining ? remaining : names.length;

          return AlertDialog(
            backgroundColor: _panel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.group_add, color: Colors.blueAccent),
                SizedBox(width: 10),
                Text('Add Multiple Players',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('One name per line (or comma separated). Space left: $remaining',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 5,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setD(() => error = null),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Sakib\nRahim\nKarim',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    names.isEmpty
                        ? 'No new names yet'
                        : names.length > remaining
                            ? '$willAdd of ${names.length} names will be added (squad limit)'
                            : '$willAdd player${willAdd == 1 ? "" : "s"} will be added',
                    style: TextStyle(
                        color: names.length > remaining ? Colors.orangeAccent : Colors.greenAccent,
                        fontSize: 12.5),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (willAdd == 0) {
                    setD(() => error = 'Enter at least one new name');
                    return;
                  }
                  try {
                    for (final n in names.take(willAdd)) {
                      await AppDatabase.insertPlayer(const Uuid().v4(), widget.teamId, n, null);
                    }
                    HapticFeedback.mediumImpact();
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadPlayers();
                    if (mounted) _snack('Added $willAdd player${willAdd == 1 ? "" : "s"}', Colors.green);
                  } catch (e) {
                    setD(() => error = 'Could not save. Try again.');
                  }
                },
                child: const Text('Add',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  // --------------------------------------------------------------- delete
  Future<bool> _confirmDelete(Map<String, dynamic> player) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Remove player?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('${player['name']} will be removed from ${widget.teamName}.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deletePlayer(Map<String, dynamic> player) async {
    HapticFeedback.mediumImpact();
    setState(() => _players.removeWhere((p) => p['id'] == player['id']));
    try {
      await AppDatabase.deletePlayer(player['id']);
    } catch (e) {
      await _loadPlayers();
      return;
    }
    if (!mounted) return;
    _snack(
      '${player['name']} removed',
      Colors.blueGrey.shade700,
      action: SnackBarAction(
        label: 'UNDO',
        textColor: Colors.greenAccent,
        onPressed: () async {
          await AppDatabase.insertPlayer(
            player['id'].toString(),
            widget.teamId,
            (player['name'] ?? '').toString(),
            player['role'],
          );
          await _loadPlayers();
        },
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final full = _players.length >= _maxPlayers;
    final shown =
        _filter == null ? _players : _players.where((p) => p['role'] == _filter).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(widget.teamName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Add multiple players',
            icon: const Icon(Icons.group_add),
            onPressed: _showBulkAddDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : _players.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    _summaryCard(),
                    const SizedBox(height: 14),
                    _filterRow(),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('No $_filter in the squad yet',
                              style: const TextStyle(color: Colors.white38)),
                        ),
                      )
                    else
                      for (final p in shown) _playerTile(p),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Center(
                        child: Text('Tap to edit  •  Swipe left to remove',
                            style: TextStyle(color: Colors.white24, fontSize: 11.5)),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditPlayerDialog(),
        backgroundColor: full ? Colors.grey : Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(full ? 'Squad full' : 'Add Player',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // Custom pill: always readable on the dark UI (no theme-dependent chip colors)
  Widget _pill({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : color.withOpacity(0.55), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.black87 : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black87 : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- summary card
  Widget _summaryCard() {
    final n = _players.length;
    final progress = n / _maxPlayers;
    final needMore = n < 2;
    final noBowler = n >= 2 && _countRole('Bowler') + _countRole('All-rounder') == 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A55), Color(0xFF1F3C88)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blueAccent.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: n),
                duration: const Duration(milliseconds: 500),
                builder: (context, v, _) => Text('$v',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Text(' / $_maxPlayers players',
                    style: const TextStyle(color: Colors.white60, fontSize: 15)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (n >= _maxPlayers ? Colors.greenAccent : Colors.orangeAccent)
                      .withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  n >= _maxPlayers ? 'FULL SQUAD' : '${_maxPlayers - n} SPOTS LEFT',
                  style: TextStyle(
                      color: n >= _maxPlayers ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 7,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                    n >= _maxPlayers ? Colors.greenAccent : Colors.lightBlueAccent),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final r in _roles) ...[
                Expanded(child: _roleStat(r)),
                if (r != _roles.last) const SizedBox(width: 8),
              ],
            ],
          ),
          if (needMore || noBowler) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    needMore
                        ? 'Add at least 2 players to start a match'
                        : 'Tip: add a Bowler or All-rounder so bowlers are suggested in scoring',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleStat(String role) {
    final col = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(_roleIcon(role), color: col, size: 16),
          const SizedBox(height: 2),
          Text('${_countRole(role)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          Text(role,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ filter row
  Widget _filterRow() {
    Widget chip(String label, String? value, int count) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _pill(
          label: '$label ($count)',
          icon: value == null ? Icons.groups_rounded : _roleIcon(value),
          color: value == null ? Colors.lightBlueAccent : _roleColor(value),
          selected: _filter == value,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _filter = value);
          },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All', null, _players.length),
          for (final r in _roles) chip(r, r, _countRole(r)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ player tile
  Widget _playerTile(Map<String, dynamic> player) {
    final id = player['id'].toString();
    final name = (player['name'] ?? '').toString();
    final role = player['role'] as String?;
    final col = _roleColor(role);
    final number = _players.indexWhere((p) => p['id'] == player['id']) + 1;

    return TweenAnimationBuilder<double>(
      key: ValueKey('anim-$id'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(player),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => _deletePlayer(player),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: col.withOpacity(0.18)),
          ),
          child: ListTile(
            onTap: () => _showAddEditPlayerDialog(existingPlayer: player),
            leading: CircleAvatar(
              backgroundColor: col.withOpacity(0.2),
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            title: Text(name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Icon(_roleIcon(role), size: 13, color: col),
                  const SizedBox(width: 4),
                  Text(role ?? 'No role set',
                      style: TextStyle(
                          color: role == null ? Colors.white38 : col, fontSize: 12)),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('#$number',
                    style: const TextStyle(
                        color: Colors.white30, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, color: Colors.white24, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ empty state
  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.groups_rounded, color: Colors.blueAccent, size: 56),
            ),
            const SizedBox(height: 18),
            const Text('No players added yet',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Build the ${widget.teamName} squad (up to $_maxPlayers players)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showAddEditPlayerDialog(),
                  icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                  label: const Text('Add Player',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showBulkAddDialog,
                  icon: const Icon(Icons.group_add, color: Colors.white70),
                  label: const Text('Add Multiple', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
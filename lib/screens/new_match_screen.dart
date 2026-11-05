import 'package:flutter/material.dart';
import '../app_database.dart';
import '../main.dart'; // SmokyPhotoBackground
import 'toss_screen.dart'; // টস স্ক্রিন ইমপোর্ট

class NewMatchScreen extends StatefulWidget {
  const NewMatchScreen({super.key});

  @override
  State<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends State<NewMatchScreen> {
  List<Map<String, dynamic>> _teams = [];
  String? _teamAId;
  String? _teamBId;
  final TextEditingController _oversController = TextEditingController(text: '6');
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  void _loadTeams() async {
    final teams = await AppDatabase.getTeams();
    setState(() {
      _teams = teams;
      _isLoading = false;
      if (_teams.isNotEmpty) {
        _teamAId = _teams[0]['id'];
        if (_teams.length > 1) _teamBId = _teams[1]['id'];
      }
    });
  }

  String _getTeamName(String? id) {
    if (id == null) return 'Team';
    final team = _teams.firstWhere((element) => element['id'] == id, orElse: () => {'name': 'Team'});
    return team['name'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      extendBodyBehindAppBar: true, // ছবি অ্যাপবারের পেছনেও যাবে
      appBar: AppBar(
        title: const Text('New Match Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // ধোঁয়ার মতো ছবির ব্যাকগ্রাউন্ড
      body: SmokyPhotoBackground(
        opacity: 0.28, // ছবি কম/বেশি করতে বদলান (০.২ – ০.৪৫)
        tint: const Color(0xFF0F172A),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
              : _teams.length < 2
                  ? _buildNotEnoughTeams()
                  : Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.sports_cricket, size: 80, color: Colors.greenAccent),
                          const SizedBox(height: 20),
                          const Text(
                            'Select Teams & Overs',
                            style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 30),

                          _buildDropdown('Team A', _teamAId, (val) {
                            setState(() => _teamAId = val);
                          }),

                          const SizedBox(height: 15),
                          const Center(child: Text('VS', style: TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.bold))),
                          const SizedBox(height: 15),

                          _buildDropdown('Team B', _teamBId, (val) {
                            setState(() => _teamBId = val);
                          }),

                          const SizedBox(height: 25),

                          TextField(
                            controller: _oversController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                            decoration: InputDecoration(
                              labelText: 'Enter Overs (e.g. 6)',
                              labelStyle: const TextStyle(color: Colors.white54),
                              prefixIcon: const Icon(Icons.timer, color: Colors.white),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),

                          const Spacer(),

                          ElevatedButton(
                            onPressed: () {
                              if (_teamAId == _teamBId) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Same team cannot be selected twice!'), backgroundColor: Colors.red),
                                );
                                return;
                              }

                              int overs = int.tryParse(_oversController.text) ?? 6;
                              if (overs <= 0) overs = 6;

                              // এখানে TossScreen-এ নিয়ে যাবে
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TossScreen(
                                    teamAId: _teamAId!,
                                    teamBId: _teamBId!,
                                    teamAName: _getTeamName(_teamAId),
                                    teamBName: _getTeamName(_teamBId),
                                    totalOvers: overs,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent.shade400,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Text('Proceed to Toss', style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildDropdown(String hint, String? currentValue, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          hint: Text(hint, style: const TextStyle(color: Colors.white54)),
          dropdownColor: const Color(0xFF1E1B4B),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          items: _teams.map((team) {
            return DropdownMenuItem<String>(
              value: team['id'],
              child: Text(team['name']),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildNotEnoughTeams() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.error_outline, size: 80, color: Colors.orangeAccent),
            SizedBox(height: 20),
            Text(
              'Need at least 2 teams to start a match!',
              style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              'Please go to "Team & Players" and create at least 2 teams.',
              style: TextStyle(fontSize: 14, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import 'player_management_screen.dart'; // প্লেয়ার স্ক্রিনের ইমপোর্ট

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  List<Map<String, dynamic>> _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams(); // স্ক্রিন ওপেন হলেই ডেটাবেস থেকে টিম লোড করবে
  }

  // ডেটাবেস থেকে টিম লোড করার ফাংশন
  void _loadTeams() async {
    final teams = await AppDatabase.getTeams();
    setState(() {
      _teams = teams;
      _isLoading = false;
    });
  }

  // নতুন টিম অ্যাড করার পপ-আপ (Bottom Sheet)
  void _showAddTeamSheet() {
    final TextEditingController teamNameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, // কীবোর্ড ওপেন হলে উপরে উঠবে
            left: 20, right: 20, top: 20,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1B4B), // ডার্ক থিমের ম্যাচিং কালার
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'নতুন টিম তৈরি করুন',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // টিমের নামের ইনপুট ফিল্ড
              TextField(
                controller: teamNameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'টিমের নাম লিখুন...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.group, color: Colors.blueAccent),
                ),
              ),
              const SizedBox(height: 20),
              
              // সেভ বাটন
              ElevatedButton(
                onPressed: () async {
                  final name = teamNameController.text.trim();
                  if (name.isNotEmpty) {
                    // ইউনিক আইডি জেনারেট করে ডেটাবেসে সেভ করা
                    const uuid = Uuid();
                    await AppDatabase.insertTeam(uuid.v4(), name);
                    
                    if (context.mounted) {
                      Navigator.pop(context); // পপ-আপ বন্ধ
                      _loadTeams(); // নতুন লিস্ট লোড
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$name টিম সফলভাবে তৈরি হয়েছে!'), backgroundColor: Colors.green),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('সেভ করুন', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // ডার্ক ব্যাকগ্রাউন্ড
      appBar: AppBar(
        title: const Text('টিম ও প্লেয়ার', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      
      // লোডিং বা টিম লিস্ট দেখানো
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : _teams.isEmpty
              ? _buildEmptyState()
              : _buildTeamList(),
              
      // নতুন টিম অ্যাড করার ফ্লোটিং বাটন
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTeamSheet,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('নতুন টিম', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // টিম না থাকলে যা দেখাবে
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_add, size: 80, color: Colors.blueAccent),
          ),
          const SizedBox(height: 20),
          const Text(
            'এখনো কোনো টিম তৈরি করা হয়নি',
            style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          const Text(
            'নিচের + বাটনে ক্লিক করে নতুন টিম তৈরি করুন',
            style: TextStyle(fontSize: 14, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  // টিম থাকলে সুন্দর কার্ড আকারে লিস্ট দেখাবে
  Widget _buildTeamList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teams.length,
      itemBuilder: (context, index) {
        final team = _teams[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent.withOpacity(0.2),
              radius: 25,
              child: Text(
                team['name'][0].toUpperCase(),
                style: const TextStyle(color: Colors.blueAccent, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              team['name'],
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 18),
            onTap: () {
              // টিমে ক্লিক করলে প্লেয়ার ম্যানেজমেন্ট স্ক্রিনে নিয়ে যাবে
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerManagementScreen(
                    teamId: team['id'],
                    teamName: team['name'],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'team_management_screen.dart';
import 'new_match_screen.dart'; // নতুন ম্যাচ স্ক্রিন ইমপোর্ট করা হলো
import '../main.dart'; // SmokyPhotoBackground এখান থেকে আসছে

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1B4B), // গাঢ় নীল/পার্পল
              Color(0xFF4C1D95), // হালকা পার্পল
              Color(0xFF0F172A), // ডার্ক ব্লু
            ],
          ),
        ),
        child: SmokyPhotoBackground(
          opacity: 0.35, // ছবি কতটা দেখা যাবে (০.২৫ – ০.৫০)
          tint: const Color(0xFF1E1B4B),
          child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // হেডার সেকশন
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                             'Cricket Crushers' ,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Smart Cricket Scoring',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),

                        // কাস্টম লোগো
                        Container(
                          height: 65,
                          width: 65,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.08),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purpleAccent.withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Text(
                                'C',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontStyle: FontStyle.italic,
                                  height: 1.2,
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.orangeAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.sports_cricket,
                                      size: 14, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 60),

                    // মেইন অ্যাকশন কার্ড (নতুন ম্যাচ)
                    _buildActionCard(
                      context,
                      title: 'নতুন ম্যাচ শুরু করুন',
                      subtitle: 'মাঠে বসেই স্কোর করুন',
                      icon: Icons.play_circle_fill,
                      color: Colors.greenAccent.shade400,
                      onTap: () {
                        // নতুন ম্যাচ স্ক্রিনে নিয়ে যাওয়ার লিংক
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const NewMatchScreen()),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // টিম ম্যানেজমেন্ট কার্ড
                    _buildActionCard(
                      context,
                      title: 'টিম ও প্লেয়ার',
                      subtitle: 'খেলোয়াড়দের ছবি ও নাম যুক্ত করুন',
                      icon: Icons.groups_rounded,
                      color: Colors.orangeAccent.shade400,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const TeamManagementScreen()),
                        );
                      },
                    ),

                    const Spacer(),

                    // ফুটার
                    const Center(
                      child: Text(
                        'Welcome to Cricket Crushers Team 🏏',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
          ),
        ),
      ),
    );
  }

  // সুন্দর কার্ড বানানোর ফাংশন
  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08), // গ্লাস ইফেক্ট
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }
}
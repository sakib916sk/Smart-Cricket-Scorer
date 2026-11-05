# 🏏 Cricket Crushers - Smart Cricket Scoring App

Cricket Crushers is a powerful, offline-first cricket scoring application built with Flutter. It is designed specifically for local and grassroots cricket matches, allowing scorers to seamlessly track matches directly from the field without needing an internet connection.

## ✨ Features

- **📴 Offline-First Architecture:** Powered by SQLite, allowing you to score matches anywhere without internet.
- **⚡ Live Scoring:** Ball-by-ball tracking with runs, extras (Wide, No Ball), and wickets.
- **🎉 Smart Celebrations:** Animated pop-ups and sound effects for 4s, 6s, Wickets, and Milestones (50s & 100s).
- **📊 Comprehensive Match Management:** 
  - Toss system (Bat/Bowl selection).
  - Innings break with dynamic target calculations.
  - Real-time Run Rate (CRR) and "Need X runs from Y balls" tracker.
- **👥 Team & Player Management:** Create teams, add players with roles (Batsman, Bowler, All-rounder), and capture player photos.
- **📄 PDF Scorecard:** Generate and share professional PDF scorecards at the end of the match.
- **🏆 Man of the Match:** Automatically calculates and celebrates the top scorer at the end of the game.
- **🎤 Voice Commentary:** Text-to-speech commentary for match events (Coming soon/In development).
- **🌙 Clean UI:** A sleek, user-friendly, light-themed interface optimized for one-handed use on the field.

## 🛠️ Tech Stack

- **Framework:** [Flutter](https://flutter.dev/)
- **Language:** [Dart](https://dart.dev/)
- **Local Database:** [sqflite](https://pub.dev/packages/sqflite)
- **State Management:** Stateful Widgets / Provider
- **Media & Files:** [image_picker](https://pub.dev/packages/image_picker), [audioplayers](https://pub.dev/packages/audioplayers)
- **PDF Generation:** [pdf](https://pub.dev/packages/pdf), [printing](https://pub.dev/packages/printing)

## 🚀 Getting Started

To run this project locally on your machine, follow these steps:

### Prerequisites
- Install [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Install [Android Studio](https://developer.android.com/studio) (for Android SDK and Emulator)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/c_crushers.git

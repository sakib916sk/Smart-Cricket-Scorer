import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;

class AppDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;

    final path = join(await getDatabasesPath(), 'ccrushers_v2.db'); 
    final sql = await rootBundle.loadString('assets/schema.sql');

    _db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      for (final stmt in sql.split(';')) {
        final s = stmt.trim();
        if (s.isNotEmpty) await db.execute(s);
      }
    });
    return _db!;
  }

  // টিম সেভ ও গেট
  static Future<void> insertTeam(String id, String name) async {
    final db = await instance;
    await db.insert('teams', {'id': id, 'name': name});
  }

  static Future<List<Map<String, dynamic>>> getTeams() async {
    final db = await instance;
    return await db.query('teams');
  }

  // প্লেয়ার সেভ, গেট, ডিলিট ও আপডেট
  static Future<void> insertPlayer(String id, String teamId, String name, String? role) async {
    final db = await instance;
    await db.insert('players', {
      'id': id,
      'team_id': teamId,
      'name': name,
      'role': role,
    });
  }

  static Future<List<Map<String, dynamic>>> getPlayers(String teamId) async {
    final db = await instance;
    return await db.query('players', where: 'team_id = ?', whereArgs: [teamId]);
  }

  // প্লেয়ার ডিলিট করার ফাংশন
  static Future<void> deletePlayer(String id) async {
    final db = await instance;
    await db.delete('players', where: 'id = ?', whereArgs: [id]);
  }

  // প্লেয়ার আপডেট করার ফাংশন
  static Future<void> updatePlayer(String id, String name, String? role) async {
    final db = await instance;
    await db.update('players', {'name': name, 'role': role}, where: 'id = ?', whereArgs: [id]);
  }
}
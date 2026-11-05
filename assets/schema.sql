CREATE TABLE teams (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE players (
  id TEXT PRIMARY KEY,
  team_id TEXT NOT NULL,
  name TEXT NOT NULL,
  photo_path TEXT,
  jersey_no INTEGER,
  role TEXT -- নতুন কলাম: Batsman, Bowler, All-rounder
);

CREATE TABLE matches (
  id TEXT PRIMARY KEY,
  team_a_id TEXT NOT NULL,
  team_b_id TEXT NOT NULL,
  overs INTEGER NOT NULL DEFAULT 6,
  status TEXT NOT NULL DEFAULT 'setup'
);

CREATE TABLE ball_events (
  id TEXT PRIMARY KEY,
  match_id TEXT NOT NULL,
  runs_batter INTEGER NOT NULL DEFAULT 0,
  runs_extras INTEGER NOT NULL DEFAULT 0,
  extra_type TEXT,
  is_wicket INTEGER NOT NULL DEFAULT 0
);
#!/usr/bin/env bash
# Serializes Godot runs on this project (several sessions share .godot/ and would race on imports).
# Usage: araclar/godot.sh <godot args...>   e.g. araclar/godot.sh --headless --quit-after 120
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.godot-kilit"
GODOT="/e/Godot/Godot_v4.7.2-stable_win64_console.exe"
for _ in $(seq 1 900); do
  if mkdir "$LOCK" 2>/dev/null; then break; fi
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rmdir "$LOCK" 2>/dev/null; fi
  sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
cd "$ROOT" && "$GODOT" --path . "$@"

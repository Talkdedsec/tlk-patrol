#!/usr/bin/env bash
# Renders scene presets to PNG files.
# Usage (project root): scripts/world/compare_presets.sh <out_dir> [preset ...]   (no presets = all)
# Needs a GPU window (no --headless).
OUT="${1:?out dir}"
shift
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1
mkdir -p "$OUT"
if [ "$#" -gt 0 ]; then NAMES="$*"; else NAMES="$(grep -oE '^\s+"[a-z0-9_]+": \{$' scripts/world/scene_presets.gd | tr -d ' ":{')"; fi
for n in $NAMES; do
	WS_PRESET="$n" araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/world/test_world.tscn \
		--out "$OUT/$n.png" --frames 25 --setup res://scripts/world/shot_setup.gd 2>&1 | grep -E "SCRIPT ERROR" | grep "world/"
done

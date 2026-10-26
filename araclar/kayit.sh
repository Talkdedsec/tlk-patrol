#!/usr/bin/env bash
# Records a scenario with Godot Movie Maker and converts it to mp4.
# Usage: araclar/kayit.sh <scenario-name> [fps]     -> kayit/<name>.mp4 and kayit/<name>-kareler/*.png
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOTW="$(cd "$ROOT" && pwd -W)"
name="$1"; fps="${2:-60}"
mkdir -p "$ROOT/kayit"
"$ROOT/araclar/godot.sh" --write-movie "$ROOTW/kayit/$name.avi" --fixed-fps "$fps" res://scenes/dev/scenario_main.tscn -- --scenario "$name" --out "$ROOTW/kayit/$name-kareler"
ffmpeg -v error -y -i "$ROOT/kayit/$name.avi" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac "$ROOT/kayit/$name.mp4" && echo "OK $ROOT/kayit/$name.mp4"

#!/usr/bin/env bash
# Side-by-side comparison clip: first recording on the left, second on the right.
# Usage: araclar/yanyana.sh <sol.mp4> <sag.mp4> <cikti.mp4>
ffmpeg -v error -y -i "$1" -i "$2" -filter_complex "[0:v]scale=960:540,fps=30[a];[1:v]scale=960:540,fps=30[b];[a][b]hstack=inputs=2[v]" -map "[v]" -c:v libx264 -crf 20 -pix_fmt yuv420p "$3" && echo "OK $3"

#!/bin/bash
# يصيّر الفيديو كاملاً على عمليتين متوازيتين ثم يدمجهما
set -e
cd "$(dirname "$0")"
OUT=${1:-draft_video.mp4}
N=$(python3 -c "import json,math;print(math.ceil(json.load(open('timeline.json'))['total']*30))")
H=$((N/2))
rm -f part_a.mp4 part_b.mp4
node render.js 0 $H part_a.mp4 > ra.log 2>&1 &
PA=$!
node render.js $H $N part_b.mp4 > rb.log 2>&1 &
PB=$!
wait $PA; wait $PB
printf "file 'part_a.mp4'\nfile 'part_b.mp4'\n" > parts.txt
ffmpeg -loglevel error -y -f concat -safe 0 -i parts.txt -c copy "$OUT"
ffprobe -v error -show_entries format=duration,size -of compact "$OUT"

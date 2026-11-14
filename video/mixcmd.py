# يطبع أمر الخلط الذي يُشغَّل في صندوق ElevenLabs: الصوت في مواضعه، والموسيقى تنخفض تحت الكلام.
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
tl = json.load(open(os.path.join(HERE, 'timeline.json')))
have = sys.argv[1].split(',') if len(sys.argv) > 1 else sorted(tl['start'])
total = tl['total']
starts = {k: round(tl['start'][k], 3) for k in have}
py = f'''
import subprocess, json
S = {json.dumps(starts)}
T = {total}
inp = ['-i', 'in/video.mp4', '-i', 'in/music.flac']
fc = []
labels = []
for i, (k, s) in enumerate(sorted(S.items())):
    inp += ['-i', f'in/{{k}}.mp3']
    fc.append(f'[{{i+2}}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=mono,adelay={{int(s*1000)}}:all=1,apad=whole_dur={{T}}[v{{i}}]')
    labels.append(f'[v{{i}}]')
fc.append(''.join(labels) + f'amix=inputs={{len(labels)}}:normalize=0:duration=longest,atrim=0:{{T}},highpass=f=60,acompressor=threshold=-22dB:ratio=2:attack=8:release=150,volume=4.6dB[vo]')
fc.append('[vo]asplit=2[vm][vs]')
fc.append(f"[1:a]aresample=48000,atrim=0:{{T}},volume=-9dB,volume='if(lt(t,3.0),1.7,if(gt(t,{{T-6.0}}),1.7,1))':eval=frame[mu]")
fc.append('[mu][vs]sidechaincompress=threshold=0.02:ratio=5:attack=60:release=900:makeup=1[md]')
fc.append('[vm]pan=stereo|c0=c0|c1=c0[vst]')
fc.append('[vst][md]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.93:level=disabled[out]')
cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y'] + inp + ['-filter_complex', ';'.join(fc), '-map', '0:v', '-map', '[out]',
       '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-movflags', '+faststart', '-t', str(T), 'mix.mp4']
subprocess.run(cmd, check=True)
'''
print(f"""cd /workspace && cat > mix.py <<'PYEOF'
{py}
PYEOF
python3 mix.py && ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,sample_rate,channels -of compact mix.mp4 && ffmpeg -hide_banner -i mix.mp4 -af ebur128=peak=true -f null - 2>&1 | grep -A12 Summary | grep -E 'I:|LRA:|Peak:' """)

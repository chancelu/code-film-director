#!/bin/zsh
# 母带：成片 +（可选）替换 BGM + 音效轨 → 两遍 loudnorm 归一到 −14 LUFS / −1 dBTP。
# 用法:
#   master.sh <in.mp4> <out.mp4> [--sfx sfx.wav] [--events events.json] [--bgm bgm.wav] [--bgm-db -3] [--sfx-db 0] [--lufs -14]
# 说明:
#   - 不传 --bgm：沿用 in.mp4 自带的音轨（渲染时已混入 BGM 的情况）。
#   - 传 --bgm：丢弃原音轨，改用新 BGM（自动裁到视频长度，淡入 0.33s、淡出 1.5s）。
#   - --sfx：sfx.py 生成的音效轨，与音乐轨相加；音乐在音效处做侧链闪避（约 −4dB）。
#   - --events：读取 events.json 的 silence 区间，把整条总线（音乐+音效）在这些区间压到 0，做出真静音（前后 30ms 渐变）。
#   - true peak 目标 −1.5 dBTP，给 AAC 编码留余量，编码后实测 ≤ −1。
#   - 视频流直接拷贝，不重新编码。
set -e
IN=$1; OUT=$2; shift 2 || { echo "用法: master.sh in.mp4 out.mp4 [--sfx f] [--bgm f]"; exit 1; }
SFX=""; BGM=""; EVENTS=""; BGMDB=0; SFXDB=0; LUFS=-14
while [ $# -gt 0 ]; do
  case $1 in
    --sfx) SFX=$2; shift 2;; --bgm) BGM=$2; shift 2;; --events) EVENTS=$2; shift 2;;
    --bgm-db) BGMDB=$2; shift 2;; --sfx-db) SFXDB=$2; shift 2;;
    --lufs) LUFS=$2; shift 2;; *) echo "未知参数 $1"; exit 1;;
  esac
done
# ffmpeg 查找顺序：$FFMPEG → $PY3 里的 imageio-ffmpeg → PATH 中的 ffmpeg
PY3=${PY3:-python3}
FF=${FFMPEG:-$("$PY3" -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>/dev/null || command -v ffmpeg)}
[ -z "$FF" ] && { echo "找不到 ffmpeg：设置 FFMPEG=路径，或 pip install imageio-ffmpeg"; exit 1; }
DUR=$("$FF" -i "$IN" 2>&1 | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p' | awk -F: '{print $1*3600+$2*60+$3}')
FO=$(echo "$DUR - 1.5" | bc)

# 1) 组装音乐轨 [m]
if [ -n "$BGM" ]; then
  INPUTS=(-i "$IN" -i "$BGM"); MIDX=1
  MUSIC="[1:a]atrim=0:${DUR},afade=t=in:d=0.33,afade=t=out:st=${FO}:d=1.5,volume=${BGMDB}dB,aformat=sample_rates=48000:channel_layouts=stereo[m]"
else
  INPUTS=(-i "$IN"); MIDX=0
  MUSIC="[0:a]volume=${BGMDB}dB,aformat=sample_rates=48000:channel_layouts=stereo[m]"
fi
if [ -n "$SFX" ]; then
  INPUTS+=(-i "$SFX"); SIDX=$(( ${#INPUTS[@]} / 2 - 1 ))
  GRAPH="$MUSIC;[${SIDX}:a]volume=${SFXDB}dB,aformat=sample_rates=48000:channel_layouts=stereo,apad=whole_dur=${DUR},asplit[s1][s2];[m][s1]sidechaincompress=threshold=0.05:ratio=3:attack=5:release=250[md];[md][s2]amix=inputs=2:normalize=0:duration=first[mix]"
else
  GRAPH="$MUSIC;[m]anull[mix]"
fi

# 真静音：silence 区间整条总线乘以一个 0/1 包络（30ms 渐变）
if [ -n "$EVENTS" ]; then
  GATE=$("$PY3" - "$EVENTS" <<'PY2'
import json,sys
sil=json.load(open(sys.argv[1],encoding='utf-8')).get('silence',[])
f=0.03; terms=[f"clip(max(({a}-t)/{f},(t-{b})/{f}),0,1)" for a,b in sil]
print("*".join(terms))
PY2
)
  [ -n "$GATE" ] && GRAPH="$GRAPH;[mix]volume='${GATE}':eval=frame[mixg]" && MIXOUT=mixg
fi
MIXOUT=${MIXOUT:-mix}

# 2) 第一遍：测量
TMP=$(mktemp -d)
"$FF" -hide_banner -nostats "${INPUTS[@]}" -filter_complex "$GRAPH;[${MIXOUT}]loudnorm=I=${LUFS}:TP=-1.5:LRA=11:print_format=json[o]" \
  -map "[o]" -t "$DUR" -f null - 2> "$TMP/m.txt"
read II TP LRA TH OFF <<< $("$PY3" - "$TMP/m.txt" <<'PY'
import json,re,sys
s=open(sys.argv[1]).read(); j=json.loads(s[s.rindex('{'):s.rindex('}')+1])
print(j['input_i'],j['input_tp'],j['input_lra'],j['input_thresh'],j['target_offset'])
PY
)
echo "测量: I=$II LUFS  TP=$TP  LRA=$LRA"

# 3) 第二遍：线性归一，视频流直接拷贝
"$FF" -y -hide_banner -loglevel error "${INPUTS[@]}" -filter_complex \
  "$GRAPH;[${MIXOUT}]loudnorm=I=${LUFS}:TP=-1.5:LRA=11:measured_I=${II}:measured_TP=${TP}:measured_LRA=${LRA}:measured_thresh=${TH}:offset=${OFF}:linear=true,aresample=48000[o]" \
  -map 0:v -map "[o]" -c:v copy -c:a aac -b:a 192k -t "$DUR" -movflags +faststart "$OUT"
rm -rf "$TMP"

# 4) 复测
"$FF" -hide_banner -nostats -i "$OUT" -af ebur128=peak=true -f null - 2>&1 | awk '$1=="I:"{i=$2} $1=="Peak:"{p=$2} END{print "复测: I=" i " LUFS  TP=" p " dBTP"}'
echo "OK → $OUT"

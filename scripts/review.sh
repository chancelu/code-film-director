#!/bin/zsh
# 交付前质检：联系表 + 黑/白帧 + 响度 + 开头亮度 + 静音段。
# 用法: review.sh <video.mp4> [输出目录，默认 视频同目录/review_<名>] [--every 2]（联系表抽帧间隔，单位秒）
# 判定（打印 PASS / WARN）:
#   - 前 3 帧平均亮度 YAVG < 20 → WARN（第 0 秒必须有画面，钩子不能从黑场开始）
#   - 黑帧段 ≥0.5s 或纯白段 ≥0.5s → WARN（片尾淡出可忽略）
#   - 综合响度偏离 −14±1 LUFS 或 true peak > −1 dBTP → WARN
#   - 列出静音段（≥0.8s），对照导演稿确认这些是"设计好的真静音"，而不是漏掉了声音
set -e
IN=$1; [ -z "$IN" ] && { echo "用法: review.sh video.mp4 [outdir] [--every 秒]"; exit 1; }
B=$(basename "${IN%.*}")
OD=${2:-$(dirname "$IN")/review_$B}; [[ "$OD" == --* ]] && OD=$(dirname "$IN")/review_$B
EVERY=2; [[ "$*" == *"--every"* ]] && EVERY=$(echo "$*" | sed -n 's/.*--every \([0-9.]*\).*/\1/p')
mkdir -p "$OD"
# ffmpeg 查找顺序：$FFMPEG → $PY3 里的 imageio-ffmpeg → PATH 中的 ffmpeg
PY3=${PY3:-python3}
FF=${FFMPEG:-$("$PY3" -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>/dev/null || command -v ffmpeg)}
[ -z "$FF" ] && { echo "找不到 ffmpeg：设置 FFMPEG=路径，或 pip install imageio-ffmpeg"; exit 1; }
DUR=$("$FF" -i "$IN" 2>&1 | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p' | awk -F: '{print $1*3600+$2*60+$3}')
echo "== $B  时长 ${DUR}s"

# 1) 联系表：每 EVERY 秒一帧，6 列，帧上压时间码
N=$(echo "$DUR / $EVERY + 1" | bc); ROWS=$(( (N + 5) / 6 ))
"$FF" -y -hide_banner -loglevel error -i "$IN" -vf "fps=1/$EVERY,scale=320:-1,drawtext=text='%{pts\:hms}':x=6:y=6:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6,tile=6x$ROWS:padding=4:margin=4" \
  -frames:v 1 -update 1 "$OD/contact.jpg" && echo "联系表 → $OD/contact.jpg（${N} 帧）"

# 2) 前 3 帧亮度
YAVG=$("$FF" -hide_banner -i "$IN" -vf "select='lt(n,3)',signalstats,metadata=print:key=lavfi.signalstats.YAVG" -an -f null - 2>&1 \
  | sed -n 's/.*YAVG=\([0-9.]*\).*/\1/p' | awk '{s+=$1} END{printf "%.1f", s/NR}')
if (( $(echo "$YAVG < 20" | bc) )); then echo "WARN 开头 3 帧 YAVG=$YAVG（过暗，钩子需要第 0 秒就有画面）"; else echo "PASS 开头 3 帧 YAVG=$YAVG"; fi

# 3) 黑帧 / 白帧（白帧用 negate 后再查黑）
BL=$("$FF" -hide_banner -i "$IN" -vf "blackdetect=d=0.5:pix_th=0.08" -an -f null - 2>&1 | grep -o "black_start:[0-9.]* black_end:[0-9.]*" || true)
WH=$("$FF" -hide_banner -i "$IN" -vf "negate,blackdetect=d=0.5:pix_th=0.05" -an -f null - 2>&1 | grep -o "black_start:[0-9.]* black_end:[0-9.]*" || true)
[ -z "$BL" ] && echo "PASS 无 ≥0.5s 黑场" || { echo "WARN 黑场:"; echo "$BL" | sed 's/^/     /'; }
[ -z "$WH" ] && echo "PASS 无 ≥0.5s 纯白" || { echo "WARN 纯白:"; echo "$WH" | sed 's/^/     /'; }

# 4) 响度
R=$("$FF" -hide_banner -nostats -i "$IN" -af ebur128=peak=true -f null - 2>&1)
I=$(echo "$R" | awk '$1=="I:"{v=$2} END{print v}')
P=$(echo "$R" | awk '$1=="Peak:"{v=$2} END{print v}')
[ -z "$I" ] && { echo "WARN 响度解析失败（可能无音轨）"; I=0; P=0; }
if (( $(echo "$I < -15 || $I > -13 || $P > -1" | bc) )); then echo "WARN 响度 I=${I} LUFS  TP=${P} dBTP（目标 −14±1 / ≤−1，跑 master.sh）"
else echo "PASS 响度 I=${I} LUFS  TP=${P} dBTP"; fi

# 5) 静音段
SI=$("$FF" -hide_banner -i "$IN" -af "silencedetect=n=-50dB:d=0.8" -vn -f null - 2>&1 | grep -oE "silence_(start|end): [0-9.]+" | paste - - | awk '{printf "     %.2f–%.2fs\n",$2,$4}' || true)
[ -z "$SI" ] && echo "INFO 无 ≥0.8s 静音（导演方法要求至少 2 处设计好的真静音）" || { echo "INFO 静音段（核对是否是设计的）:"; echo "$SI"; }
echo "== 完成，人工再看：联系表 + 关键动作 0.2s 逐帧 + 带声音全速看一遍"

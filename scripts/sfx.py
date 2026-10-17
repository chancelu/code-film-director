#!/usr/bin/env python
"""程序化音效合成：按事件表生成一条与成片等长的音效轨（48kHz 立体声 wav）。

用法:
  python sfx.py events.json out.wav [--duration 秒]
  python sfx.py --demo out_dir/          # 每种音效各生成一个试听文件
  python sfx.py --list                   # 列出音效类型

events.json 格式（可直接由 Remotion 时间轴导出）:
  {"duration": 95.0,
   "events": [{"t": 0.0, "type": "bell", "gain": -6, "pan": 0},
              {"t": 3.2, "type": "ink_drop"}],
   "silence": [[41.0, 42.5]]}      # 可选：真静音区间，音效轨在此强制为 0
gain 的单位是 dB，默认 0；pan 取值 -1（左）到 1（右）。
同一份 events 可同时交给 master.sh 用于 BGM 闪避（ducking）。
"""
import json, sys, os, wave
import numpy as np

SR = 48000
RNG_SEED = 7  # 固定种子：同一份事件表每次渲染出完全相同的声音


def _t(d):
    return np.arange(int(d * SR)) / SR


def _env(n, a=0.002, d=0.3):
    """指数包络：attack a 秒，衰减时间常数 d 秒。"""
    t = np.arange(n) / SR
    e = np.exp(-t / d)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def _noise(n, rng):
    return rng.standard_normal(n)


def _lp(x, cut):
    """一阶低通（足够做纸、刷子类的质感）。"""
    a = np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def _bp(x, lo, hi):
    return _lp(x, hi) - _lp(x, lo)


def _partials(freqs, amps, decays, dur):
    t = _t(dur)
    y = np.zeros_like(t)
    for f, a, d in zip(freqs, amps, decays):
        y += a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    return y


# ---------- 音色 ----------
def ink_drop(rng):
    """墨滴：下滑的正弦音头 + 轻微水声尾巴。"""
    d = 0.45
    t = _t(d)
    f = 1400 * np.exp(-t * 18) + 380
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * _env(len(t), 0.001, 0.06)
    y += 0.15 * _bp(_noise(len(t), rng), 300, 2500) * _env(len(t), 0.01, 0.15)
    return y


def brush(rng, dur=0.7):
    """毛笔刷过宣纸：带通噪声 + 起落包络。"""
    n = int(dur * SR)
    x = _bp(_noise(n, rng), 800, 6000)
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    e *= 1 + 0.25 * np.sin(np.linspace(0, 9 * np.pi, n))  # 笔压起伏
    return x * e * 0.8


def paper(rng):
    """翻纸 / 纸张展开：几簇短促的颗粒噪声。"""
    d = 0.5
    n = int(d * SR)
    y = np.zeros(n)
    for _ in range(14):
        p = rng.integers(0, n - 2000)
        L = rng.integers(300, 1800)
        y[p:p + L] += _noise(L, rng) * np.hanning(L) * rng.uniform(0.3, 1)
    return _bp(y, 1500, 9000) * np.sin(np.linspace(0, np.pi, n))


def woodfish(rng):
    """木鱼：空腔共振的两个分音，衰减很快。"""
    y = _partials([720, 1630], [1, 0.35], [0.05, 0.025], 0.3)
    y += 0.3 * _noise(len(y), rng) * _env(len(y), 0.0005, 0.004)
    return y


def gong_small(rng):
    """小锣：不和谐的分音 + 轻微音高下滑。"""
    d = 2.2
    t = _t(d)
    y = np.zeros_like(t)
    for f, a, dd in [(520, 1, 0.9), (1180, .5, .6), (1730, .35, .4), (2440, .2, .25)]:
        ff = f * (1 + 0.03 * np.exp(-t * 3))
        y += a * np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t / dd)
    y[:int(.003 * SR)] *= np.linspace(0, 1, int(.003 * SR))
    return y * 0.6


def bell(rng):
    """编钟 / 寺钟：低频长尾 + 拍频。"""
    y = _partials([196, 198.5, 392 * 1.19, 588 * 1.32, 830],
                  [1, .8, .5, .3, .15], [2.5, 2.5, 1.4, .8, .4], 4.0)
    return y * 0.5


def seal(rng):
    """印章盖下：低频闷击 + 纸面摩擦。"""
    d = 0.35
    t = _t(d)
    y = np.sin(2 * np.pi * (90 + 60 * np.exp(-t * 40)) * t) * _env(len(t), 0.001, 0.07)
    y += 0.4 * _lp(_noise(len(t), rng), 1200) * _env(len(t), 0.001, 0.03)
    return y


def guqin_pluck(rng, f=146.8):
    """古琴泛音式拨弦（Karplus-Strong 方法）。"""
    n = int(2.5 * SR)
    p = int(SR / f)
    buf = _noise(p, rng) * 0.5
    y = np.zeros(n)
    for i in range(n):
        y[i] = buf[i % p]
        buf[i % p] = 0.996 * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return y


def whoosh(rng, dur=0.8):
    """气流：截止频率上扫的噪声（用于镜头运动）。"""
    n = int(dur * SR)
    x = _noise(n, rng)
    y = np.zeros(n)
    acc = 0.0
    cuts = 300 + 4000 * np.sin(np.linspace(0, np.pi, n)) ** 2
    for i in range(n):
        a = np.exp(-2 * np.pi * cuts[i] / SR)
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y * np.sin(np.linspace(0, np.pi, n)) * 2.5


def pen_tick(rng):
    """笔尖点白板 / 落点：极短的高频滴答（科普、白板风）。"""
    y = _partials([3200, 5100], [1, .4], [.01, .006], 0.06)
    return y + 0.2 * _noise(len(y), rng) * _env(len(y), 0.0003, 0.003)


def pop(rng):
    """数据点弹出：短促上滑音（数据叙事风）。"""
    t = _t(0.12)
    f = 500 + 900 * (1 - np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * _env(len(t), 0.001, 0.03)


def low_hit(rng):
    """沉重落点 / 揭示：亚低频冲击 + 尾音。"""
    t = _t(1.5)
    y = np.sin(2 * np.pi * (45 + 80 * np.exp(-t * 25)) * t) * _env(len(t), 0.002, 0.35)
    return y + 0.15 * _lp(_noise(len(t), rng), 400) * _env(len(t), 0.001, 0.08)


SOUNDS = {
    "ink_drop": ink_drop, "brush": brush, "paper": paper, "woodfish": woodfish,
    "gong": gong_small, "bell": bell, "seal": seal, "guqin": guqin_pluck,
    "whoosh": whoosh, "pen_tick": pen_tick, "pop": pop, "low_hit": low_hit,
}


def _norm(y, peak=0.7):
    m = np.max(np.abs(y)) or 1
    return y / m * peak


def render(spec):
    rng = np.random.default_rng(RNG_SEED)
    evs = spec.get("events", [])
    dur = spec.get("duration") or (max([e["t"] for e in evs] + [0]) + 5)
    out = np.zeros((int(dur * SR) + SR, 2))
    for e in evs:
        typ = e["type"]
        if typ not in SOUNDS:
            raise SystemExit(f"未知音效类型 {typ}，可用：{', '.join(SOUNDS)}")
        fn = SOUNDS[typ]
        kw = {k: e[k] for k in ("dur", "f") if k in e}
        y = _norm(fn(rng, **kw)) * 10 ** (e.get("gain", 0) / 20)
        pan = float(e.get("pan", 0))
        l, r = np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)
        s = int(e["t"] * SR)
        y = y[: max(0, len(out) - s)]
        out[s:s + len(y), 0] += y * l * 1.414
        out[s:s + len(y), 1] += y * r * 1.414
    out = out[: int(dur * SR)]
    for a, b in spec.get("silence", []):  # 真静音：前后各留 20ms 淡变，避免爆音
        i, j = int(a * SR), int(b * SR)
        f = int(0.02 * SR)
        out[max(0, i - f):i] *= np.linspace(1, 0, min(f, i))[:, None]
        out[i:j] = 0
        k = min(f, len(out) - j)
        out[j:j + k] *= np.linspace(0, 1, k)[:, None]
    peak = np.max(np.abs(out))
    if peak > 0.98:
        out *= 0.98 / peak
    return out


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(a):
    if not a or a[0] in ("-h", "--help"):
        print(__doc__); return
    if a[0] == "--list":
        for k, f in SOUNDS.items():
            print(f"{k:10s} {f.__doc__.strip().splitlines()[0]}")
        return
    if a[0] == "--demo":
        d = a[1] if len(a) > 1 else "sfx_demo"
        os.makedirs(d, exist_ok=True)
        for k in SOUNDS:
            write_wav(os.path.join(d, f"{k}.wav"), render({"duration": 4.5, "events": [{"t": 0.1, "type": k}]}))
        print(f"已生成 {len(SOUNDS)} 个试听文件 → {d}"); return
    spec = json.load(open(a[0], encoding="utf-8"))
    if "--duration" in a:
        spec["duration"] = float(a[a.index("--duration") + 1])
    write_wav(a[1], render(spec))
    print(f"OK {a[1]}  {len(spec.get('events', []))} 个事件  {spec.get('duration')}s")


if __name__ == "__main__":
    main(sys.argv[1:])

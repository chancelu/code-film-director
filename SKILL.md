---
name: code-film-director
description: 纯代码知识短片的"导演方法 + 风格库 + 音效/母带/质检工具"。用于传统文化、哲学、科普类短视频的质量提升：选风格、写导演稿（treatment）、镜头表、卡点表、音效设计、字幕节奏、渲染后质检与母带响度。适用于 Remotion / Canvas / WebGL / Manim 等任何"画面是时间的函数"的代码视频管线。触发词：视频质量、优化视频、换风格、导演稿、分镜、镜头语言、音效、混音、响度、科普视频、哲学视频、国风视频、新系列。
---

# Code Film Director（代码短片导演）

画面、音乐、音效、字幕全部由代码生成，不用视频生成模型。评判顺序：**声音 → 节奏 → 镜头 → 导演（表演/调度/情绪弧）**，单帧好看只是起点。

本 skill 只管"怎么拍得好"，不绑定渲染引擎：你的项目继续用原来的管线（Remotion、Canvas、Manim……）出片，再用这里的方法和脚本提升质量。

## 资源索引

| 文件 | 何时读 |
|---|---|
| `references/director.md` | 每次开新片/新系列前必读：故事、钩子、节奏、镜头、声音、自检规则 |
| `references/styles.md` | 选风格时读：传统文化 / 哲学 / 科普三类内容的 12 种风格配方（材质、配色、字体、运动、镜头、声音、原生招式、坑） |
| `references/treatment-template.md` | 写导演稿时复制它 |
| `references/prompt-patterns.md` | 要"一句话出片"，或要写给其他 agent 的任务书时读 |
| `scripts/sfx.py` | 按事件表程序化合成音效（墨滴、笔刷、纸、木鱼、小锣、钟、印章、古琴、气流、笔尖、弹出、低频冲击） |
| `scripts/master.sh` | 成片 + BGM + 音效混音，音乐自动闪避，两遍 loudnorm 到 −14 LUFS |
| `scripts/review.sh` | 交付前质检：联系表、黑/白帧、响度、开头亮度、静音段 |

依赖：Python 3 + `numpy`；ffmpeg（脚本按 `$FFMPEG` → `imageio-ffmpeg` → PATH 的顺序查找）。脚本使用 zsh。

## 工作流（每一支片）

1. **接需求，只问一次**：主题、时长、平台比例、是否沿用系列风格。其余自己定。
2. **找标杆**（director.md §2）：选 1–2 部参考作品，写下"学什么 / 不学什么"。
3. **写导演稿** `TREATMENT.md`（模板在 references 里）：三种结构候选 → 选一 → logline 与起承转合 → 镜头表 → 秒级节拍表 → 卡点表 → 音效表 → 字幕设计。
4. **证明画风**：用真实渲染代码出 3 张风格帧（其中一张是招牌镜头），对照 styles.md 自查。
5. **搭时间轴**：一份时间轴同时驱动画面、字幕、音效。字幕停留 ≥ 字数÷4.5+1.5 秒，写脚本检查每一条；动画出场点跟字幕走，事件同时导出为 `events.json`。
6. **声音**：BGM 卡点之外，每个可见动作配一个音效（`sfx.py`），至少两处真静音，至少两次声音转场（J/L-cut）。
7. **渲染 → 混音**：`master.sh` 合成并归一到 −14 LUFS。
8. **质检**：跑 `review.sh`，至少看两轮联系表，关键动作按 0.2 s 逐帧检查，再带声音全速看一遍（director.md §11）。
9. **交付**：成片 mp4 + 封面；写清楚哪些内容是自加的、引用了哪些出处（经典写《书名》）。

## 硬规则

- 开场 3 秒内抛出与观众相关的问题或反差，不放片头卡；钩子必须在片中回收。
- 一支片只有一个主角（一个概念或一个物件），一个转折，结尾呼应开头。
- 每支片至少一个"原生招式"（只有这个媒介能做到的转场或动作），放在情绪高点。
- 节奏要有快有慢：至少一次明显的加速或减速，至少一处"喘息"（长镜头或停顿）。全程匀速等于失败。
- 至少 4 种镜头运动；关键时刻主体占画面高度 ≥ 1/3；字幕不能压住主体。
- 按发布平台的规范自查敏感词；健康医疗类内容不给诊断建议并加提示；陈述事实的科普片附 `FACTS.md`（每条论断 + 出处）。
- 风格只学语法，不抄角色、构图、旋律、字体设计、logo。

## 脚本速用

```bash
S=path/to/code-film-director/scripts
python $S/sfx.py --list                            # 列出 12 种音效
python $S/sfx.py --demo /tmp/sfxdemo               # 每种各出一个试听 wav
python $S/sfx.py events.json sfx.wav --duration 155   # 按事件表生成整轨（固定随机种子，结果可复现）
$S/master.sh in.mp4 out.mp4 --sfx sfx.wav --events events.json [--sfx-db -3] [--bgm new_bgm.wav]
#   混音 + 音乐闪避 + silence 区间整条总线真静音 + 两遍 loudnorm（−14 LUFS / TP ≤ −1），视频流直接拷贝
$S/review.sh out.mp4 [outdir] --every 5            # 联系表、开头亮度、黑白帧、响度、静音段
```

`events.json` 示例：

```json
{"duration": 95,
 "events": [{"t": 0.2, "type": "bell", "gain": -8},
            {"t": 3.0, "type": "ink_drop"},
            {"t": 5.0, "type": "brush", "gain": -6, "pan": -0.3}],
 "silence": [[41.0, 42.5]]}
```

- 实测经验：只混了 BGM 的成片响度常在 −10 到 −11 LUFS，true peak 超过 0 dBTP，有削波风险。过一遍 master.sh 后约为 −14.0 LUFS / −2.4 dBTP。
- 最常见的短板是"没有拟音、没有静音"，补上这两项的收益最大（styles.md 升级路线 ①）。
- zsh 坑：`$VAR:` 会被当作修饰符解析（例如 `:l` 会转小写），滤镜串里的变量一律写成 `${VAR}`。BSD grep 不支持 `\s`，用 awk 解析。

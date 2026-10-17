# code-film-director

一个给 AI Agent 用的 Skill，用来拍"纯代码知识短片"：画面、配乐卡点、音效、字幕全部由代码生成，不依赖视频生成模型。适合传统文化、哲学、科普类的 60–180 秒短视频。

它不替你渲染，而是在你已有的管线（Remotion、Canvas、WebGL、Manim……）之上，补齐"导演"这一层：

- **导演方法**：钩子、结构、节奏变速、镜头词汇、声音设计、交付前自检（`references/director.md`）
- **12 种风格配方**：水墨、皮影、纸雕灯影、剪纸、木刻、一笔画、铜版画、默片、白板、瑞士排版、数据叙事、档案灯台。每种都写了材质、配色、字幕、运动、镜头、声音、原生招式和常见坑（`references/styles.md`）
- **导演稿模板**：三种结构候选 → 镜头表 → 节拍表 → 卡点表 → 音效表 → 与上一集的差异（`references/treatment-template.md`）
- **提示词写法**：rules 块、deliverables、验证循环，以及三类内容的一句话出片模板（`references/prompt-patterns.md`）
- **三个脚本**
  - `scripts/sfx.py`：用 numpy 程序化合成 12 种音效（墨滴、笔刷、翻纸、木鱼、小锣、钟、印章、古琴、气流、笔尖、弹出、低频冲击），按事件表一次生成整条音效轨，固定种子保证可复现
  - `scripts/master.sh`：成片 + BGM + 音效混音，音乐在音效处自动闪避，可指定真静音区间，两遍 loudnorm 归一到 −14 LUFS / TP ≤ −1 dBTP，视频流直接拷贝
  - `scripts/review.sh`：交付前质检，生成联系表，检查开头亮度、黑帧/白帧、响度、静音段

## 风格怎么选

| 内容 | 首选 | 备选 |
|---|---|---|
| 传统文化 / 东方题材 | 水墨写意 | 皮影、纸雕灯影、红色剪纸、木刻 |
| 哲学 | 一笔画 | 木刻、铜版画、默片、瑞士排版 |
| 科普 | 白板讲解 / 数据叙事 | 铜版画、档案灯台、瑞士排版 |

## 安装

把整个目录放进你的 Agent 的 skills 目录：

```bash
git clone https://github.com/chancelu/code-film-director.git
cp -R code-film-director ~/.claude/skills/        # Claude Code
# 或 ~/.workbuddy/skills/、~/.codebuddy/skills/ 等支持 SKILL.md 的目录
```

依赖：Python 3 + `numpy`；ffmpeg（脚本按 `$FFMPEG` → `imageio-ffmpeg` → PATH 的顺序查找）；zsh。

## 用法

对 Agent 说"用 code-film-director 帮我把这支片的质量提上去"或"按水墨风写一份导演稿"即可。脚本也能单独用：

```bash
python scripts/sfx.py --list
python scripts/sfx.py --demo ./sfx_demo                 # 试听全部音效
python scripts/sfx.py events.json sfx.wav --duration 95
./scripts/master.sh film.mp4 film_master.mp4 --sfx sfx.wav --events events.json
./scripts/review.sh film_master.mp4 --every 2
```

`events.json`：

```json
{"duration": 95,
 "events": [{"t": 0.2, "type": "bell", "gain": -8},
            {"t": 3.0, "type": "ink_drop"},
            {"t": 5.0, "type": "brush", "gain": -6, "pan": -0.3}],
 "silence": [[41.0, 42.5]]}
```

## 致谢

方法论是在学习以下两个项目后，用中文重新整理并面向知识类短片改写的笔记，没有复制原文：

- [lemomo-ai/lemo-opuscar](https://github.com/lemomo-ai/lemo-opuscar)：51 种代码影片风格与导演/技术指南
- [yihui-dev/awesome-opus5-5-videos](https://github.com/yihui-dev/awesome-opus5-5-videos)：700+ 条代码视频提示词合集

## License

MIT

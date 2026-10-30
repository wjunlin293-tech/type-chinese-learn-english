# 更新记录

## v1.2.0 — 一键安装、一键更新、更顺手

### 一行命令装好

打开「终端」，粘贴 README 里的一行命令，回车，等 5–10 分钟就装好了。中途只会让你输入一次开机密码（用来安装输入法），不用回答任何问题。

- 不再需要 Homebrew 和 git。鼠须管直接下载官方安装包（核对 SHA-256），装好后自动加入并切换到输入法列表，不用再去系统设置里手动添加。
- 整句翻译模型不再需要在你电脑上临时装 1GB 的 PyTorch 来转换。改为下载 GitHub 上预先转好的版本（约 70MB，核对 SHA-256），由 `.github/workflows/model.yml` 自动生成。
- 动手前先检查：macOS 版本（需要 13 以上）、磁盘空间、网络，以及能否安装输入法（需要管理员账户），也不允许用 sudo 运行。不满足就用一句话说清楚原因和办法。
- 下载自动重试、断点续传。中途断了重新运行同一条命令即可，已装好的部分会跳过。
- 语法模型、整句翻译这些可选部分装不上（网络不通、没有 Python 等），不影响主体。最后会列出哪一项没装成、为什么、怎么补。
- 第一次安装前自动备份原有的 `~/Library/Rime`。
- 所有细节写进 `~/Library/Logs/cn2en.log`，出错时屏幕上显示最后几行。

### 一个命令管理：cn2en

- `cn2en update`：更新到最新版并显示更新内容。你的个人词表、你改过的外观设置都保留；新版也改了同一个配置文件时，新版本另存为 `.new`。
- `cn2en status`：逐项检查输入法、插件、翻译服务、新版本，有问题直接说怎么修。
- `cn2en fix 质量 quality, grade`：一条命令修正某个词的英文，立即生效。修正写在个人词表 `~/Library/Rime/cn2en_user.tsv` 里，更新不会覆盖；用 `cn2en fix --undo 质量` 撤销。
- `cn2en mt on|off`：开关本机翻译服务（关掉省约 250MB 内存）。
- `cn2en uninstall`：干净卸载，保留个人词表；加 `--all` 连鼠须管一起删。

### 打字时更顺手

- **Ctrl+Shift+E**：打字时随时开关英文。
- **Ctrl+Shift+回车**：直接输出英文，不上屏中文（借用雾凇自带的上屏注释功能）。
- **F4 方案选单**里新增两个开关：「中英 / 纯中」「整句 / 查词」，下次打字仍保持。

快捷键和开关都在 Linux 版 librime 1.10 + 雾凇拼音的真实引擎里测过。

## v1.1.0 — 中英意思对得上

这一版专门处理「候选旁边的英文和中文意思对不上」。先在终端里用长短不同、语境不同的输入系统地测了一遍，包括常用字、HSK 1–6 词汇、聊天用语、1500 条雾凇词库里的常用短语和整句，然后按找到的问题逐类修。

### 词表：常用字词逐个核对

CC-CEDICT 的第一个义项常常是生僻义或古义，以前直接拿来用，所以最常打的字反而错得最多。这次逐个核对了打字频率最高的 1300 个单字和 HSK 1–5 的 2500 个词。HSK 6 的 2500 个词先和参考释义自动比对，再人工核对对不上的 257 个。另外补了常见聊天/网络用语。合计在 `overrides.tsv` 里改了 1000 多条、补了 300 多条。例如：

| 词 | v1.0 | v1.1 |
|---|---|---|
| 就 / 才 / 上 / 里 | only / ability / first / li | just / only / up / in |
| 带 / 别 / 困 / 闲 | band / leave / trap / enclosure | bring / don't / sleepy / idle |
| 呢 / 页 / 奶奶 / 姥姥 | dense wool fabric / head / breasts / goody | (question particle) / page / grandma / grandma |
| 很好 / 我想 / 打印 | devastating / methinks / stamp | very good / I want / print |
| 酒店 / 先生 / 流行 | wine shop / teacher / obtain | hotel / Mr. / popular |
| 出差 / 爬山 / 截图 / 摸鱼 | （缺） | business trip / climb a mountain / screenshot / slack off |

新增 `tools/apply_overrides.py`：只改了 `overrides.tsv` 时，直接合并进 `cn2en.tsv`，不必再下载 CC-CEDICT。`overrides.tsv` 里英文写 `-` 表示删掉这个词。

### 逐词对照：分词和语境

- **按词频分词**：正向最大匹配换成最大概率分词（词频来自 jieba，新文件 `data/cn2en_freq.tsv`）。
  - 研究生命：graduate student · life → research · life
  - 很好吃：devastating · eat → very · tasty
  - 有时间：sometimes · between → have time
- **量词**：数词、指示词后的量词不再单独翻译。
  - 一部电影：single · ministry · movie → a · movie
  - 这本书：this · originally · book → this · book
- **代词**：动词、介词后用宾格，跟「的」用所有格，连词后仍是主格。
  - 帮我：help · I → help · me
  - 这是我的：this is · my → this · is · mine
  - 所以我：therefore · I
- **介词与方位词**：
  - 他对我很好：he · right · I → he · to · me
  - 我马上到：I · at once · to → I · at once · arrive
  - 市场上：market · first → market · on
- **正反问句**：要不要、好不好、有没有等直接显示 want to? / OK? / is there?
- 括号里的说明不进逐词对照，「吃了吗」这类不再出现两个问号。

### 整句：模型没把握时不显示

翻译服务加了 `?s=1`，会返回模型对这条译文的平均对数概率。低于 −1.0 视为模型在硬译、瞎猜，改用逐词对照，例如「躺平了 → Lie down.」会改显示 lie flat。

这个阈值是用真模型（就是安装时下载的那个）跑了 150 多句日常、工作、学习和网络用语后定的：通顺的译文大多在 −0.2 到 −0.9 之间。原来的长度检查改为按逐词对照里的英文单词数计算，「好久不见你还好吗」这类不再被误拦。这批句子里，只有 4 条译文被换成逐词对照。

开发时还试过一种按词典核对「实词是否都译出来了」的检查。用模拟数据测时看起来有效，但用真模型一测，它误拦了约 20 条好译文（如「我快到了 → I'm almost there.」），真正拦下的错译不到 3 条，所以没有采用。

翻译服务还加了防复读（`no_repeat_ngram_size=3`），并按原文长度限制译文长度。旧版 `cn2en.lua` 不带 `s=1`，服务照旧只返回译文，新旧版本可以混用。

### 测试

- `tools/test_cn2en.lua`：不开输入法，在终端里模拟候选菜单测试 `cn2en.lua`。
- `tools/test_cases.txt`：81 条回归用例，都是以前实际出现过的错配。v1.0 有 70 条不通过，v1.1 全部通过。
- `tools/test_cases_mt.txt`：长短、语境各不相同的整句，GitHub Actions 每次都用真模型跑一遍，日志里能看到原始译文、把握分和输入法最终显示的内容。

### 已知问题

- 模型偶尔会译错意思但用词通顺，把握分也不低，比如「我每天背二十个单词 → I'm carrying 20 words every day.」，这类拦不住。
- 半句也可能被译成别扭的整句，比如「你明天早上 → You'll be in the morning.」。
- 服务多做一次打分，单次翻译耗时会略增，尚未在 Apple M1 上实测。

## v1.0.0

首个版本：鼠须管 + 雾凇拼音 + 词表注释 + 本机 OPUS-MT 整句翻译。

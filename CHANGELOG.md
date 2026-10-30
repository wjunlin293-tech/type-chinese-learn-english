# 更新记录

## v1.1 — 中英意思对得上

这一版专门处理「候选旁边的英文和中文意思对不上」。先在终端里用长短不同、语境不同的输入系统地测了一遍（常用字、HSK 1–6 词汇、聊天用语、1500 条雾凇词库里的常用短语、整句），按找到的问题逐类修。

### 词表：常用字词逐个核对

CC-CEDICT 的第一个义项常常是生僻义或古义，以前直接拿来用，最常打的字反而错得最多。这次按打字频率逐个核对了前 1300 个单字和 HSK 1–5 的 2500 个词；HSK 6 的 2500 个词先自动比对参考释义，再人工核对对不上的 257 个；另外补了常见聊天/网络用语。合计在 `overrides.tsv` 里改了 1000 多条、补了 300 多条。例如：

| 词 | v1.0 | v1.1 |
|---|---|---|
| 就 / 才 / 上 / 里 | only / ability / first / li | just / only / up / in |
| 带 / 别 / 困 / 闲 | band / leave / trap / enclosure | bring / don't / sleepy / idle |
| 呢 / 页 / 奶奶 / 姥姥 | dense wool fabric / head / breasts / goody | (question particle) / page / grandma / grandma |
| 很好 / 我想 / 打印 | devastating / methinks / stamp | very good / I want / print |
| 酒店 / 先生 / 流行 | wine shop / teacher / obtain | hotel / Mr. / popular |
| 出差 / 爬山 / 截图 / 摸鱼 | （缺） | business trip / climb a mountain / screenshot / slack off |

新增 `tools/apply_overrides.py`：只改了 `overrides.tsv` 时直接合并进 `cn2en.tsv`，不必再下载 CC-CEDICT。`overrides.tsv` 里英文写 `-` 表示删掉这个词。

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

### 整句：模型译文先核对再显示

以前只检查译文是不是太长。现在再加两道检查，不通过就改用逐词对照：

- **把握**：翻译服务（`?s=1`）返回模型对译文的平均对数概率，低于 −1.5 视为模型在瞎猜。
- **覆盖**：原文的实词在译文里能找到对应英文的不到 40%，视为漏译或错译。对应关系来自词表释义和新文件 `data/cn2en_senses.tsv`（ECDICT 反查的同义说法），会做词形还原；每个英文词只能对应一个中文词。

翻译服务还加了防复读（`no_repeat_ngram_size=3`）和按原文长度限制译文长度，减少「you're out of the car, you're out of the car」这类输出。旧版 `cn2en.lua` 不带 `s=1`，服务照旧只返回译文，新旧版本可以混用。

### 测试

- `tools/test_cn2en.lua`：不开输入法，在终端里模拟候选菜单测试 `cn2en.lua`。
- `tools/test_cases.txt`：81 条回归用例，都是以前实际出现过的错配。v1.0 有 70 条不通过，v1.1 全部通过。
- `tools/test_cases_mt.txt`：长短、语境各不相同的整句，用来在真机上抽查模型译文和核对结果。

### 已知问题

- 整句核对的阈值是用模拟的好/坏译文定的：20 条好译文全部保留，10 条坏译文拦下 8 条。还没在真机的 OPUS-MT 输出上大量校准，见 README「已知局限」。
- 服务多做一次打分，单次翻译耗时会略增，尚未在 Apple M1 上重新实测。

## v1.0

首个版本：鼠须管 + 雾凇拼音 + 词表注释 + 本机 OPUS-MT 整句翻译。

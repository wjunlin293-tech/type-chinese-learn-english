# data/ 许可说明

| 文件 | 来源 | 许可 |
|---|---|---|
| `cn2en.tsv` | 由 CC-CEDICT 生成，并结合 ECDICT 词频排序、ECDICT 反查回退、`overrides.tsv` 手工校正 | **CC BY-SA 4.0** |
| `overrides.tsv` | 手工校正表 | CC BY-SA 4.0（随 `cn2en.tsv` 一同发布） |
| `cn2en_ecdict_reverse.tsv` | 由 ECDICT 英→中释义反向整理（`tools/build_ecdict_reverse.py`） | MIT（见下方 ECDICT 许可） |

## CC-CEDICT

`cn2en.tsv` 是 CC-CEDICT 的衍生作品，按 [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/) 发布。

- CC-CEDICT：Community maintained free Chinese-English dictionary，Published by MDBG — https://www.mdbg.net/chinese/dictionary?page=cc-cedict
- Referenced works: CEDICT - Copyright (C) 1997, 1998 Paul Andrew Denisowski
- 所做修改：只保留简体词头；清洗释义（去括号限定义项、索引条目、量词说明、动词前的 "to"）；按英文词频重新排序，每词保留 1–2 个英文；合并手工校正。

## ECDICT

英文词频与 `cn2en_ecdict_reverse.tsv` 来自 [ECDICT](https://github.com/skywind3000/ECDICT)：

```
MIT License

Copyright (c) 2025 Linwei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

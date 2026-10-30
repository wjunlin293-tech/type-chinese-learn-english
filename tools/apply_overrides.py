#!/usr/bin/env python3
"""把手工校正表直接合并进现成的 cn2en.tsv（不需要重新下载 CC-CEDICT / ECDICT）。

用法: apply_overrides.py data/cn2en.tsv data/overrides.tsv
overrides.tsv 每行 `中文<TAB>英文`，# 开头为注释；同一个词出现多次时以最后一次为准。
英文写成空字符串（`中文<TAB>-`）表示从词表里删掉这个词。
"""
import sys

TSV, OVERRIDES = sys.argv[1:3]

result = {}
with open(TSV, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip('\n')
        if '\t' in line:
            cn, en = line.split('\t', 1)
            result[cn] = en

changed = added = removed = 0
with open(OVERRIDES, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or line.startswith('#') or '\t' not in line:
            continue
        cn, en = (s.strip() for s in line.split('\t', 1))
        if en == '-':
            removed += result.pop(cn, None) is not None
            continue
        if cn not in result:
            added += 1
        elif result[cn] != en:
            changed += 1
        result[cn] = en

with open(TSV, 'w', encoding='utf-8') as f:
    for cn in sorted(result, key=lambda s: s.encode('utf-8')):
        f.write(f"{cn}\t{result[cn]}\n")
print(f"修改 {changed}，新增 {added}，删除 {removed}，共 {len(result)} 条")

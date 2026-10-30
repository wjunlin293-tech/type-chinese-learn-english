#!/usr/bin/env python3
"""生成 cn2en_freq.tsv：词表里每个词的词频，供 cn2en.lua 逐词对照时做「最大概率分词」。

正向最大匹配会把「研究生命」切成 研究生/命、「很好吃」切成 很好/吃；
按词频算整句概率最大的切法，就能得到 研究/生命、很/好吃。

词频来源：jieba 词典 dict.txt（MIT），只保留 cn2en.tsv 里有的词。
手工校正表里的词（多为常用口语短语）jieba 没收录时给一个中等词频，免得被拆开。

用法: build_freq.py jieba_dict.txt data/cn2en.tsv data/overrides.tsv data/cn2en_freq.tsv
"""
import sys

JIEBA, TSV, OVERRIDES, OUT = sys.argv[1:5]
OVERRIDE_FREQ = 300

words = set()
with open(TSV, encoding='utf-8') as f:
    for line in f:
        words.add(line.split('\t', 1)[0])

freq = {}
with open(JIEBA, encoding='utf-8') as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 2 and parts[0] in words and parts[1].isdigit():
            freq[parts[0]] = int(parts[1])

with open(OVERRIDES, encoding='utf-8') as f:
    for line in f:
        if line.startswith('#') or '\t' not in line:
            continue
        cn = line.split('\t', 1)[0].strip()
        if cn in words and len(cn) > 1:
            freq[cn] = max(freq.get(cn, 0), OVERRIDE_FREQ)

with open(OUT, 'w', encoding='utf-8') as f:
    for w in sorted(freq, key=lambda s: s.encode('utf-8')):
        f.write(f"{w}\t{freq[w]}\n")
print(f"{len(freq)} 个词有词频（词表共 {len(words)} 条）")

#!/usr/bin/env python3
"""生成 cn2en_senses.tsv：中文词 -> 多个可能的英文说法（不显示，只用来核对整句译文）。

cn2en.lua 拿到本机模型的整句译文后，会检查原文里的实词在译文里有没有「对应的英文」：
比如「我昨天去银行取钱」翻成 "I went to the bank yesterday." 漏了「取钱」，
「他把手机丢了」翻成 "He threw his phone." 意思反了——这类译文就不显示，改用逐词对照。
显示用的词表每个词只有 1~2 个英文，核对时太容易误判，所以这里从 ECDICT 反查出更多说法。

用法: build_senses.py ecdict.csv data/cn2en_freq.tsv data/cn2en_senses.tsv
只给 cn2en_freq.tsv 里的词（常用词）生成，每个词最多 12 个英文。
"""
import csv, re, sys
from collections import defaultdict

SRC, FREQ, DST = sys.argv[1:4]
MAX_RANK = 40000
MAX_LINES = 4
PER_LINE = 8
MAX_SENSES = 12
POS_RE = re.compile(r'^(?:[a-z]+\.\s*)+')
PAREN_RE = re.compile(r'[（(][^）)]*[）)]|<[^>]*>|\[[^\]]*\]')
CN_RE = re.compile(r'^[一-鿿]{1,6}$')

# ECDICT 里不是单个英文单词、或拼写带点号的常用对应，手工补上
EXTRA = {
    '下午': 'pm', '上午': 'am', '晚上': 'pm tonight', '今晚': 'tonight', '早上': 'am',
    '点': "o'clock", '我': 'my mine myself', '你': 'your yours', '他': 'his', '她': 'hers',
    '我们': 'our ours', '他们': 'their theirs', '没有': "didn't don't haven't no", '不': "don't didn't isn't won't can't",
}

common = set()
with open(FREQ, encoding='utf-8') as f:
    for line in f:
        common.add(line.split('\t', 1)[0])

def rank_of(row):
    vals = [int(row[k]) for k in ('frq', 'bnc') if row[k].isdigit() and int(row[k]) > 0]
    return min(vals) if vals else None

senses = defaultdict(dict)   # cn -> {en: score}
with open(SRC, newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        en = row['word']
        if not re.fullmatch(r'[a-z]{2,}', en):
            continue
        rank = rank_of(row)
        if rank is None or rank > MAX_RANK:
            continue
        ex = dict(p.split(':', 1) for p in row['exchange'].split('/') if ':' in p)
        if ex.get('0', en) != en:
            continue                                  # 屈折形式（went、apples）不单独收；cn2en.lua 比对时会做词形还原
        line_no = 0
        for line in row['translation'].replace('\\n', '\n').split('\n'):
            line = line.strip()
            if not line or line.startswith('[网络]'):
                continue
            if line_no >= MAX_LINES:
                break
            line = re.sub(r'^\[[^\]]*\]\s*', '', line)
            m = POS_RE.match(line)
            adj = bool(m) and m.group(0).split('.')[0].strip() in ('a', 'adj', 'ad', 'adv', 's')
            line = PAREN_RE.sub('', POS_RE.sub('', line))
            pos = 0
            for item in re.split(r'[；;，,、]', line):
                item = item.strip()
                if not CN_RE.match(item):
                    continue
                if pos >= PER_LINE:
                    break
                pos += 1
                keys = [item]
                if adj and len(item) >= 2 and item[-1] in '的地':
                    keys.append(item[:-1])
                for k in keys:
                    if k in common:
                        score = rank * (1 + 0.3 * pos + 0.5 * line_no)
                        if score < senses[k].get(en, 1e18):
                            senses[k][en] = score
            line_no += 1

with open(DST, 'w', encoding='utf-8') as f:
    for cn in sorted(set(senses) | set(EXTRA), key=lambda s: s.encode('utf-8')):
        ens = sorted(senses.get(cn, {}), key=lambda e: senses[cn][e])[:MAX_SENSES]
        ens += [e for e in EXTRA.get(cn, '').split() if e not in ens]
        if ens:
            f.write(f"{cn}\t{' '.join(ens)}\n")
print(len(senses), 'entries')

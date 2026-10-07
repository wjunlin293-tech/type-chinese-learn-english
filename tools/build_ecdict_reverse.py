#!/usr/bin/env python3
"""ECDICT (en->zh) 反向生成 cn2en.tsv (zh -> 1~2 个常用英文词)。"""
import csv, re, sys
from collections import defaultdict

SRC, DST = sys.argv[1], sys.argv[2]
MAX_RANK = 30000          # 词频排名上限（frq/bnc 取较小非零值）
MAX_LINES = 3             # 每个英文词只看前 3 行释义
PER_LINE = 3              # 每行只取前 3 个中文义项
POS_RE = re.compile(r'^(?:[a-z]+\.\s*)+')            # 去掉 "n. " "vt. " 前缀
PAREN_RE = re.compile(r'[（(][^）)]*[）)]|<[^>]*>|\[[^\]]*\]')
CN_RE = re.compile(r'^[一-鿿]{1,6}$')
SKIP_POS = ('abbr', 'pref', 'suf', 'int', 'art', 'num')

def rank_of(row):
    vals = [int(row[k]) for k in ('frq', 'bnc') if row[k].isdigit() and int(row[k]) > 0]
    return min(vals) if vals else None

best = defaultdict(list)   # cn -> [(score, en)]
with open(SRC, newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        en = row['word']
        if not re.fullmatch(r'[a-z]{2,}', en):          # 过滤短语/专有名词/含空格连字符
            continue
        rank = rank_of(row)
        if rank is None or rank > MAX_RANK:
            continue
        bonus = 0.5 if row['tag'].strip() else 1.0       # 有考试标签(中高考/四六级/雅思...)优先
        ex = dict(p.split(':', 1) for p in row['exchange'].split('/') if ':' in p)
        if ex.get('0', en) != en and not row['tag'].strip():
            bonus *= 4                                    # 屈折形式(went/apples)降权，独立词条(meeting)不受影响
        seen = set()
        line_no = 0
        for line in row['translation'].replace('\\n', '\n').split('\n'):
            line = line.strip()
            if not line or line.startswith('[网络]'):
                continue
            mult = 1.0
            if line.startswith('['):                        # [机] [医] 等专业义项：降权
                line = re.sub(r'^\[[^\]]*\]\s*', '', line)
                mult = 3.0
            m = POS_RE.match(line)
            if m and m.group(0).strip().rstrip('.').split('.')[0] in SKIP_POS:
                continue
            if line_no >= MAX_LINES:
                break
            adj = bool(m) and m.group(0).split('.')[0].strip() in ('a', 'adj', 'ad', 'adv', 's')
            line = PAREN_RE.sub('', POS_RE.sub('', line))
            pos = 0
            for item in re.split(r'[；;，,、]', line):
                item = item.strip()
                if not CN_RE.match(item):
                    continue
                if pos >= PER_LINE:
                    break
                # 行内越靠前、行越靠前、英文越常用，分越低越好
                score = rank * bonus * mult * (1 + 0.6 * pos + 0.3 * line_no)
                pos += 1
                keys = [item]
                # 重要的 -> 重要, 慢慢地 -> 慢慢：形容词/副词去尾也参与匹配
                if adj and len(item) >= 2 and item[-1] in '的地':
                    keys.append(item[:-1])
                for k in keys:
                    if k not in seen:
                        seen.add(k)
                        best[k].append((score, en))
            line_no += 1

out = []
for cn, lst in best.items():
    lst.sort()
    picks = [lst[0][1]]
    # 第二个词：分数不太差才保留，避免凑数
    if len(lst) > 1 and lst[1][0] <= lst[0][0] * 4:
        picks.append(lst[1][1])
    out.append((cn, picks))
out.sort()
with open(DST, 'w', encoding='utf-8') as f:
    for cn, picks in out:
        f.write(f"{cn}\t{', '.join(picks)}\n")
print(len(out), 'entries')

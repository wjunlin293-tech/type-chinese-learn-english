#!/usr/bin/env python3
"""生成 cn2en.tsv：中文词 -> 1~2 个常用英文释义。

主来源 CC-CEDICT（汉译英，CC BY-SA 4.0）：按中文词条编写，义项顺序可靠。
用 ECDICT（MIT）的英文词频给义项重新排序，让常用词（help）排在生僻词（assistance）前面。
CEDICT 没有的词，退回 ECDICT 反查结果（旧版 cn2en.tsv）。

用法: build_cn2en_v2.py cedict_ts.u8 ecdict.csv old_cn2en.tsv out.tsv [overrides.tsv]
手工校正表 overrides.tsv 优先级最高。
"""
import csv, math, re, sys
from collections import defaultdict

CEDICT, ECDICT, OLD, OUT = sys.argv[1:5]
OVERRIDES = sys.argv[5] if len(sys.argv) > 5 else None

# ---------- 英文词频（ECDICT frq/bnc，取较小的非零值；越小越常用） ----------
freq = {}
with open(ECDICT, newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        w = row['word'].lower()
        vals = [int(row[k]) for k in ('frq', 'bnc') if row[k].isdigit() and int(row[k]) > 0]
        if vals and (w not in freq or min(vals) < freq[w]):
            freq[w] = min(vals)

UNKNOWN_RANK = 40000

def gloss_rank(g):
    """单词看词频；短语看其中最生僻的实词。"""
    words = [w for w in re.findall(r"[a-z]+", g.lower()) if w not in STOP]
    if not words:
        return UNKNOWN_RANK
    return max(freq.get(w, UNKNOWN_RANK) for w in words)

STOP = {'a', 'an', 'the', 'of', 'to', 'sb', 'sth', 'one', 'oneself', 'be', 'is', 'it', 'or', 'and',
        'in', 'on', 'at', 'for', 'with', 'by', 'up', 'out', 'off', 'as', 'i', 'my', 'your', 'not', 'do'}

# ---------- 义项清洗 ----------
SKIP_PREFIX = re.compile(
    r"^(used in|variant of|old variant of|see |also written|surname |abbr\. |abbr\. for|"
    r"erhua variant|japanese variant|taiwan pr\.|cl:|radical |kangxi radical|"
    r"\(onom\.?\)|\(bound form\)|lit\. |fig\. |pr\. )", re.I)
PAREN = re.compile(r"\([^)]*\)|\[[^\]]*\]")
LATIN_ONLY = re.compile(r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ' .\-]*$")

def clean(sense):
    s = sense.strip()
    if not s or s.startswith('('):          # (physics) mass、(of a movie) good 等限定义项：跳过
        return []
    if SKIP_PREFIX.match(s):
        return []
    out = []
    for g in s.split(';'):
        g = PAREN.sub('', g).strip()
        g = re.sub(r"\b(sb|sth)\b", '', g)
        g = re.sub(r"\s*\.\.\.?$", '', g)            # think that ... -> think that
        g = re.sub(r"\s+", ' ', g).strip(" ,.")
        if g.lower().startswith('to '):      # to help -> help
            g = g[3:].strip()
        g = re.sub(r"\s+that$", '', g)                # think that -> think
        if (len(g.split()) > 3 or len(g) > 24) and ',' in g:
            g = g.split(',')[0].strip()                # Beijing municipality, capital of ... -> Beijing municipality
        if not g or not LATIN_ONLY.match(g):
            continue
        if len(g.split()) > 3 or len(g) > 24:  # 太长的解释性句子不要
            continue
        out.append(g)
    return out

# ---------- 读 CEDICT ----------
LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")
CJK = re.compile(r"^[一-鿿]{1,8}$")
entries = defaultdict(list)   # simp -> [(is_proper, [ [gloss...] per sense ])]
with open(CEDICT, encoding='utf-8') as f:
    for line in f:
        if line.startswith('#'):
            continue
        m = LINE.match(line)
        if not m:
            continue
        trad, simp, pinyin, defs = m.groups()
        if not CJK.match(simp):
            continue
        proper = pinyin[:1].isupper()
        senses = [clean(d) for d in defs.split('/')]
        senses = [s for s in senses if s]
        if senses:
            entries[simp].append((proper, senses))

def pick(cands_entries):
    """每个读音条目分别打分（义项越靠前、英文越常用越好），取最好的条目里前两名。"""
    best = None
    for proper, senses in cands_entries:
        scored = []
        seen = set()
        for i, sense in enumerate(senses[:4]):
            for j, g in enumerate(sense[:3]):
                k = g.lower()
                if k in seen:
                    continue
                seen.add(k)
                # 义项越靠前、英文越常用、越像单个词，分越低越好
                score = (1 + 0.6 * i + 0.2 * j) * math.log(gloss_rank(g) + 50) ** 1.5
                score *= 1 + 0.35 * (len(g.split()) - 1)
                if proper:
                    score *= 1.3
                if len(senses) == 1 and len(cands_entries) > 1:
                    score *= 1.15                     # 多音字里只有一个义项的冷门读音：降权
                scored.append((score, g))
        if not scored:
            continue
        scored.sort()
        if best is None or scored[0][0] < best[0][0]:
            best = scored
    if not best:
        return None
    picks = [best[0][1]]
    if len(best) > 1 and best[1][0] <= best[0][0] * 1.35:
        a, b = best[0][1].lower(), best[1][1].lower()
        # 去掉同根词凑数：simple/simply、fail/failure
        if not (a[:4] == b[:4] and min(len(a), len(b)) >= 4):
            picks.append(best[1][1])
    return picks

result = {}
for simp, ents in entries.items():
    p = pick(ents)
    if p:
        result[simp] = ', '.join(p)

n_cedict = len(result)
with open(OLD, encoding='utf-8') as f:
    for line in f:
        cn, en = line.rstrip('\n').split('\t', 1)
        if cn not in result:
            result[cn] = en.split(', ')[0]   # 反查结果只保留第一个，减少凑数

n_over = 0
if OVERRIDES:
    with open(OVERRIDES, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#') or '\t' not in line:
                continue
            cn, en = line.split('\t', 1)
            result[cn.strip()] = en.strip()
            n_over += 1

with open(OUT, 'w', encoding='utf-8') as f:
    for cn in sorted(result, key=lambda s: s.encode('utf-8')):
        f.write(f"{cn}\t{result[cn]}\n")
print(f"CEDICT {n_cedict} + ECDICT 回退 + 手工校正 {n_over} 条 = 共 {len(result)}")

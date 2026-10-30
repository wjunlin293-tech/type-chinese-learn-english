#!/usr/bin/env bash
# 整句组词评测：把 corpus.tsv 里每句的拼音整句打进真实的 Rime（雾凇拼音 + 本仓库配置），
# 看首选候选是否和原句完全一致。用来比较语法模型参数、纠错等配置的效果。
#
# 用法（Linux，需要 librime、librime-plugin-lua、librime-plugin-octagram 和 rime_console，见 rime_console.c）：
#   tools/ime_bench/run.sh <雾凇拼音目录> <万象 .gram 文件> [rime_ice.custom.yaml]
# 不给第三个参数时用 mac/rime_ice.custom.yaml。输出整句正确率、文字正确率，以及打错的句子。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
ice=$1; gram=$2; conf=${3:-$repo/mac/rime_ice.custom.yaml}
console=${RIME_CONSOLE:-$here/rime_console}
[ -x "$console" ] || gcc -O1 -o "$console" "$here/rime_console.c" -lrime

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
(cd "$ice" && tar --exclude=.git -cf - .) | tar -xf - -C "$work"
cp "$repo/mac/default.custom.yaml" "$repo/mac/squirrel.custom.yaml" "$work/"
cp "$conf" "$work/rime_ice.custom.yaml"
mkdir -p "$work/lua" && cp "$repo/mac/lua/cn2en.lua" "$repo/data/cn2en.tsv" "$repo/data/cn2en_freq.tsv" "$work/lua/"
ln -s "$(cd "$(dirname "$gram")" && pwd)/$(basename "$gram")" "$work/$(basename "$gram")"

cut -f2 "$here/corpus.tsv" | sed 's/^/keys /; s/$/\nclear/' | "$console" "$work" 2>/dev/null |
  awk '/^PREEDIT/ { getline; sub(/^  1\. /, ""); sub(/  \[.*$/, ""); print }' > "$work/out.txt"
paste "$here/corpus.tsv" "$work/out.txt" | python3 -c '
import sys
def lev(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (x != y))
    return d[len(b)]
n = ok = chars = err = 0
wrong = []
for l in sys.stdin:
    zh, py, got = (l.rstrip("\n").split("\t") + [""])[:3]
    n += 1; ok += zh == got; chars += len(zh); err += lev(zh, got)
    if zh != got: wrong.append(f"  {zh} → {got}")
print(f"整句正确 {ok}/{n} = {ok / n:.1%}，文字正确 {1 - err / chars:.1%}")
print("\n".join(wrong))
'

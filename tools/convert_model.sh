#!/usr/bin/env bash
# 把 Helsinki-NLP/opus-mt-zh-en (CC-BY 4.0) 转成 CTranslate2 int8，输出到 ~/Library/Rime/mt/model
# 转换环境是临时的（约 1GB，含 torch），转完自动删除。
set -euo pipefail

OUT="${1:-$HOME/Library/Rime/mt/model}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HF_HOME="$WORK/hf"   # 模型缓存也放临时目录，不留在 ~/.cache

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q --upgrade pip
"$WORK/venv/bin/pip" install -q ctranslate2 transformers sentencepiece sacremoses torch

"$WORK/venv/bin/ct2-transformers-converter" \
  --model Helsinki-NLP/opus-mt-zh-en --output_dir "$WORK/model" --quantization int8

"$WORK/venv/bin/python" - "$WORK/model" <<'EOF'
import shutil, sys
from huggingface_hub import hf_hub_download
for name in ("source.spm", "target.spm"):
    shutil.copy(hf_hub_download("Helsinki-NLP/opus-mt-zh-en", name), sys.argv[1])
EOF

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"
cp -R "$WORK/model" "$OUT"
echo "模型已输出到 $OUT"
ls -la "$OUT"

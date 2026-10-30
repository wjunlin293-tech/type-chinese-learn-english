#!/usr/bin/env python3
"""本机中译英服务：只监听 127.0.0.1，供 Rime 的 cn2en.lua 调用。
GET /t?q=<中文>&q=<中文>...       ->  text/plain，每行一条英文译文（与 q 顺序一致）
GET /t?s=1&q=<中文>&q=<中文>...   ->  每行「译文<TAB>平均对数概率」，分数越接近 0 模型越有把握
模型：Helsinki-NLP/opus-mt-zh-en (CC-BY 4.0)，CTranslate2 int8。不联网。
"""
import os, threading
from collections import OrderedDict
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

import ctranslate2
import sentencepiece as spm

HOST, PORT = "127.0.0.1", 18085
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
MAX_CHARS = 60
MAX_BATCH = 12
CACHE_SIZE = 5000

translator = ctranslate2.Translator(MODEL, device="cpu", compute_type="int8",
                                    inter_threads=1, intra_threads=4)
sp_src = spm.SentencePieceProcessor(model_file=os.path.join(MODEL, "source.spm"))
sp_tgt = spm.SentencePieceProcessor(model_file=os.path.join(MODEL, "target.spm"))
lock = threading.Lock()
cache = OrderedDict()   # 中文 -> (译文, 平均对数概率或 None)


def avg_log_prob(src_tokens, tgt_tokens):
    """模型对这条译文的平均每词对数概率；算不出来（旧版 ctranslate2 等）就返回 None。"""
    try:
        r = translator.score_batch([src_tokens], [tgt_tokens])[0]
        return sum(r.log_probs) / max(len(r.log_probs), 1)
    except Exception:
        return None


def translate_many(texts):
    with lock:
        todo = [t for t in dict.fromkeys(texts) if t not in cache]
        if todo:
            tokens = [sp_src.encode(t, out_type=str) + ["</s>"] for t in todo]
            # 译文长度上限跟着原文走，免得小模型在短句后面一直往下编；
            # no_repeat_ngram_size 防止 "you're out of the car, you're out of the car" 这类复读
            max_len = min(64, 3 * max(len(x) for x in tokens) + 8)
            results = translator.translate_batch(tokens, beam_size=1, max_decoding_length=max_len,
                                                 no_repeat_ngram_size=3)
            for t, src, r in zip(todo, tokens, results):
                hyp = r.hypotheses[0]
                text = sp_tgt.decode(hyp).replace("\n", " ").strip()
                cache[t] = (text, avg_log_prob(src, hyp) if hyp else None)
        out = []
        for t in texts:
            cache.move_to_end(t)
            out.append(cache[t])
        while len(cache) > CACHE_SIZE:
            cache.popitem(last=False)
        return out


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        params = parse_qs(url.query)
        qs = [q.strip() for q in params.get("q", [])]
        if url.path != "/t" or not qs or len(qs) > MAX_BATCH or any(not q or len(q) > MAX_CHARS for q in qs):
            self.send_response(400)
            self.end_headers()
            return
        with_score = params.get("s") == ["1"]
        lines = []
        for text, score in translate_many(qs):
            lines.append(f"{text}\t{score:.3f}" if with_score and score is not None else text)
        body = "\n".join(lines).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # 不记录任何输入内容


if __name__ == "__main__":
    translate_many(["你好"])  # 预热
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

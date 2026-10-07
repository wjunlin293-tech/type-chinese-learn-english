#!/usr/bin/env python3
"""本机中译英服务：只监听 127.0.0.1，供 Rime 的 cn2en.lua 调用。
GET /t?q=<中文>&q=<中文>...  ->  text/plain，每行一条英文译文（与 q 顺序一致）
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
cache = OrderedDict()


def translate_many(texts):
    with lock:
        todo = [t for t in dict.fromkeys(texts) if t not in cache]
        if todo:
            tokens = [sp_src.encode(t, out_type=str) + ["</s>"] for t in todo]
            results = translator.translate_batch(tokens, beam_size=1, max_decoding_length=64)
            for t, r in zip(todo, results):
                cache[t] = sp_tgt.decode(r.hypotheses[0]).replace("\n", " ").strip()
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
        qs = [q.strip() for q in parse_qs(url.query).get("q", [])]
        if url.path != "/t" or not qs or len(qs) > MAX_BATCH or any(not q or len(q) > MAX_CHARS for q in qs):
            self.send_response(400)
            self.end_headers()
            return
        body = "\n".join(translate_many(qs)).encode("utf-8")
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

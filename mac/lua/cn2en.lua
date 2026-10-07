-- cn2en.lua: 给中文候选加英文注释。
--   1) 命中 cn2en.tsv 的词：显示词表里的 1~2 个常用英文；
--   2) 首选候选（通常是整句）：按页打包请求本机翻译服务(127.0.0.1:18085)；
--      若译文明显比原文长（小模型给半句「脑补」了内容），改用逐词对照；
--   3) 其余词表没有的候选（多半是半句）：逐词对照，如「我今天下午 → I · today · afternoon」。
-- 词表在模块首次加载时读入一次（require 缓存）；翻译结果在 Lua 侧也有缓存。

local dict = nil
local mt_cache = {}
local mt_cache_size = 0

local MT_URL = "http://127.0.0.1:18085/t?"
local MT_TIMEOUT = "0.3"   -- 秒；超时就不显示译文，不卡打字
local MT_MIN_CHARS = 4     -- 首选候选至少 4 个字才整句翻译
local MT_MAX_CHARS = 60
local MAX_WORD = 6         -- 逐词对照时最长匹配 6 个字
local GLOSS_SEP = " · "

-- 逐词对照时跳过的虚词/语气词
local SKIP = {}
for _, c in ipairs({ "的", "了", "吗", "呢", "吧", "啊", "呀", "哦", "嘛", "着", "过", "地", "得", "之" }) do
  SKIP[c] = true
end

local function load_dict()
  if dict then return dict end
  dict = {}
  local path = rime_api.get_user_data_dir() .. "/lua/cn2en.tsv"
  local f = io.open(path, "r")
  if not f then
    log.error("cn2en: cannot open " .. path)
    return dict
  end
  for line in f:lines() do
    local cn, en = line:match("^([^\t]+)\t(.+)$")
    if cn then dict[cn] = en end
  end
  f:close()
  return dict
end

local function url_encode(s)
  return (s:gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function is_all_cjk(s)
  for _, cp in utf8.codes(s) do
    if cp < 0x4E00 or cp > 0x9FFF then return false end
  end
  return true
end

local function first_gloss(en)
  return (en:match("^([^,]+)") or en)
end

-- 正向最大匹配分词，返回逐词英文与实词个数；匹配不到足够内容时返回 nil
local function gloss(text, d)
  local chars = {}
  for _, cp in utf8.codes(text) do chars[#chars + 1] = utf8.char(cp) end
  local out, i, n = {}, 1, #chars
  while i <= n do
    local hit_len, hit_en = 0, nil
    for len = math.min(MAX_WORD, n - i + 1), 1, -1 do
      local w = table.concat(chars, "", i, i + len - 1)
      local en = d[w]
      if en and not (len == 1 and SKIP[w]) then
        hit_len, hit_en = len, en
        break
      end
    end
    if hit_en then
      out[#out + 1] = first_gloss(hit_en)
      i = i + hit_len
    else
      i = i + 1   -- 虚词或词表没有的字：跳过
    end
  end
  if #out < 2 then return nil, #out end
  return table.concat(out, GLOSS_SEP), #out
end

-- 一次请求翻译多条，结果写入 mt_cache（失败/超时则什么都不写）
local function translate_batch(texts)
  if #texts == 0 then return end
  local parts = {}
  for i, t in ipairs(texts) do parts[i] = "q=" .. url_encode(t) end
  local p = io.popen("/usr/bin/curl -s --fail --noproxy '*' -m " .. MT_TIMEOUT .. " '" .. MT_URL .. table.concat(parts, "&") .. "'")
  if not p then return end
  local out = p:read("*a") or ""
  p:close()
  if out == "" then return end
  local i = 0
  for raw in (out .. "\n"):gmatch("([^\n]*)\n") do
    i = i + 1
    local t = texts[i]
    if not t then break end
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      if mt_cache_size > 5000 then mt_cache, mt_cache_size = {}, 0 end
      mt_cache[t] = line
      mt_cache_size = mt_cache_size + 1
    end
  end
end

-- 译文是否可信：英文词数不应远多于原文实词数（否则多半是给半句脑补了内容）
local function mt_plausible(tr, n_words)
  local en_words = 0
  for _ in tr:gmatch("%a+") do en_words = en_words + 1 end
  return en_words <= 2.2 * math.max(n_words, 1) + 1
end

local function with_comment(cand, en)
  local comment = cand.comment ~= "" and (cand.comment .. " " .. en) or en
  return ShadowCandidate(cand, cand.type, cand.text, comment)
end

local function init(env)
  load_dict()
  local ok, size = pcall(function() return env.engine.schema.page_size end)
  -- 多取 1 个：菜单会预取下一页的首个候选来判断是否还有下一页
  env.chunk = ((ok and size and size > 0) and size or 5) + 1
end

-- buf: 本批候选；first_idx: 本批第一个候选在整个菜单里的序号
local function flush(buf, d, first_idx)
  local notes, todo = {}, {}
  for k, cand in ipairs(buf) do
    local t = cand.text
    if d[t] then
      notes[k] = d[t]
    elseif is_all_cjk(t) then
      local g, n_words = gloss(t, d)
      local len = utf8.len(t) or 0
      if first_idx + k - 1 == 1 and len >= MT_MIN_CHARS and len <= MT_MAX_CHARS then
        notes[k] = { gloss = g, n = n_words }
        if mt_cache[t] == nil then todo[#todo + 1] = t end
      else
        notes[k] = g
      end
    end
  end
  translate_batch(todo)
  for k, cand in ipairs(buf) do
    local note = notes[k]
    if type(note) == "table" then
      local tr = mt_cache[cand.text]
      if tr and mt_plausible(tr, note.n) then note = tr else note = note.gloss end
    end
    if note then yield(with_comment(cand, note)) else yield(cand) end
  end
end

local function filter(input, env)
  local d = dict or load_dict()
  local chunk = env.chunk or 6
  local buf, idx = {}, 1
  for cand in input:iter() do
    buf[#buf + 1] = cand
    if #buf >= chunk then
      flush(buf, d, idx)
      idx = idx + #buf
      buf = {}
    end
  end
  flush(buf, d, idx)
end

return { init = init, func = filter }

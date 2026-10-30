-- cn2en.lua: 给中文候选加英文注释。
--   1) 命中 cn2en.tsv 的词：显示词表里的 1~2 个常用英文；
--   2) 首选候选（通常是整句）：按页打包请求本机翻译服务(127.0.0.1:18085)；
--      译文要过两道检查，不通过就改用逐词对照：
--        · 长度：英文词数远多于原文实词数（小模型给半句「脑补」了内容）；
--        · 把握：模型自己给出的平均对数概率太低（多半是硬译、瞎猜，如「躺平了 → Lie down.」）；
--   3) 其余词表没有的候选（多半是半句）：逐词对照，如「我今天下午 → I · today · afternoon」。
-- 逐词对照用词频做最大概率分词（研究/生命，而不是 研究生/命），
-- 并处理量词（三本书 → three · book）、宾语代词（帮我 → help · me）等常见搭配。
-- 词表在模块首次加载时读入一次（require 缓存）；翻译结果在 Lua 侧也有缓存。
-- 个人词表 ~/Library/Rime/cn2en_user.tsv 优先级最高，更新时不会被覆盖（cn2en fix 命令写的就是它）。
-- 开关（在方案选单 F4 里，或按快捷键）：cn2en_off 关掉英文；cn2en_no_mt 只查词、不整句翻译。

local dict, freq = nil, nil
local log_total = 0
local mt_cache = {}
local mt_cache_size = 0

local MT_URL = "http://127.0.0.1:18085/t?s=1&"
local MT_TIMEOUT = CN2EN_MT_TIMEOUT or "0.3"   -- 秒；超时就不显示译文，不卡打字（测试脚本会放宽）
local MT_MIN_CHARS = 4     -- 首选候选至少 4 个字才整句翻译
local MT_MIN_CHARS_PARTICLE = 2  -- 带语气词的短句（你好吗、下雨了）2 个字起就整句翻译
local MT_MAX_CHARS = 60
-- 模型对译文的平均对数概率，低于此值说明模型自己也没把握。按真模型实测定的：
-- 150 句日常/工作/学习/网络用语里，通顺译文大多在 -0.2 ~ -0.9，硬译瞎猜的多在 -1 以下
local MT_MIN_SCORE = -1.0
local MAX_WORD = 6         -- 逐词对照时最长匹配 6 个字
local USER_FREQ = 300      -- 个人词表里多字词的词频
local GLOSS_SEP = " · "

local function set_of(list)
  local s = {}
  for _, c in ipairs(list) do s[c] = true end
  return s
end

-- 逐词对照时跳过的虚词/语气词
local SKIP = set_of({ "的", "了", "吗", "呢", "么", "吧", "啊", "呀", "哦", "嘛", "啦", "着", "过", "地", "得", "之", "把" })

-- 数词、指示词后面的量词不单独翻译：三本书 → three · book，这道菜 → this · dish
local CLASSIFIER = set_of({ "个", "位", "件", "本", "张", "部", "篇", "道", "家", "只", "条", "次", "台", "辆", "杯",
  "瓶", "双", "份", "句", "首", "块", "节", "门", "场", "支", "片", "层", "座", "间", "棵", "朵", "封", "头", "匹",
  "顿", "趟", "遍", "种", "样", "批", "群", "套", "项", "所", "届", "名", "口", "根", "颗", "粒", "枝", "碗", "盘",
  "盒", "包", "袋", "斤", "把", "幅", "幢", "栋", "架", "艘", "顶", "笔", "副", "封", "串", "堆", "排", "滴" })
local NUM_DEM = set_of({ "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千", "万", "两", "几",
  "这", "那", "哪", "每", "某", "半", "多", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" })

-- 代词在动词/介词后面、或在句末时用宾格：帮我 → help · me，来找我 → come · look for · me
local OBJECT = { ["我"] = "me", ["他"] = "him", ["她"] = "her", ["我们"] = "us", ["他们"] = "them", ["她们"] = "them",
  ["咱们"] = "us" }
-- 代词后面跟「的」用所有格：我的电脑 → my · computer；「的」在句末则是 mine：这是我的 → this · is · mine
local POSSESSIVE = { ["我"] = "my", ["你"] = "your", ["您"] = "your", ["他"] = "his", ["她"] = "her", ["它"] = "its",
  ["我们"] = "our", ["你们"] = "your", ["他们"] = "their", ["她们"] = "their", ["咱们"] = "our", ["大家"] = "everyone's" }
local MINE = { ["我"] = "mine", ["你"] = "yours", ["您"] = "yours", ["他"] = "his", ["她"] = "hers",
  ["我们"] = "ours", ["你们"] = "yours", ["他们"] = "theirs", ["她们"] = "theirs", ["咱们"] = "ours" }
-- 这些词后面的代词仍是主语：所以我 → therefore · I
local CONJUNCTION = set_of({ "所以", "因为", "但是", "可是", "但", "可", "然后", "如果", "要是", "虽然", "而且", "并且",
  "还是", "或者", "不过", "而", "那么", "于是", "因此", "只要", "只有", "就", "也", "都", "还", "才", "是" })
-- 名词后面的方位词：市场上 → market · on，会议中 → meeting · in，毕业后 → graduate · after
local LOCATIVE = { ["上"] = "on", ["中"] = "in", ["里"] = "in", ["下"] = "under", ["前"] = "before", ["后"] = "after",
  ["内"] = "within", ["外"] = "outside" }
local PRONOUN = set_of({ "我", "你", "您", "他", "她", "它", "我们", "你们", "他们", "她们", "咱们", "大家", "自己" })
local BEFORE_OBJECT = set_of({ "给", "跟", "和", "对", "帮", "帮助", "让", "叫", "找", "告诉", "问", "请", "陪", "带",
  "等", "爱", "喜欢", "讨厌", "骂", "打", "送", "教", "求", "谢谢", "关于", "像", "比", "被", "向", "为", "替", "相信",
  "理", "恨", "怪", "夸", "催", "喊", "骗", "通知", "提醒", "联系", "回复", "打扰", "麻烦", "原谅", "欠", "管", "看",
  "想", "想念", "见", "认识", "陪着", "跟着", "带着", "离开", "接", "选", "支持", "保护", "照顾", "关心", "了解" })

-- 句末这些语气词表示疑问，逐词对照时在末尾补一个问号
local QUESTION = set_of({ "吗", "呢", "么" })

local function data_dir()
  -- 测试脚本可以设置 CN2EN_DATA_DIR 指向仓库的 data/ 目录
  return CN2EN_DATA_DIR or (rime_api.get_user_data_dir() .. "/lua")
end

local function read_tsv(name, fn)
  local path = data_dir() .. "/" .. name
  local f = io.open(path, "r")
  if not f then return false end
  for line in f:lines() do
    local k, v = line:match("^([^\t]+)\t(.+)$")
    if k then fn(k, v) end
  end
  f:close()
  return true
end

local function load_dict()
  if dict then return dict end
  dict, freq = {}, {}
  if not read_tsv("cn2en.tsv", function(k, v) dict[k] = v end) then
    log.error("cn2en: cannot open " .. data_dir() .. "/cn2en.tsv")
  end
  -- 词频表可选：没有就退化为「切出的词越少越好」
  local total = 0
  read_tsv("cn2en_freq.tsv", function(k, v)
    local n = tonumber(v)
    if n then freq[k] = n; total = total + n end
  end)
  log_total = math.log(math.max(total, 1))
  -- 个人词表：覆盖同名词条；新加的多字词给一个中等词频，分词时不被拆开
  local user = CN2EN_USER_FILE or (rime_api.get_user_data_dir() .. "/cn2en_user.tsv")
  local f = io.open(user, "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^([^\t#][^\t]*)\t%s*(.-)%s*$")
      if k and v == "-" then
        dict[k] = nil
      elseif k and v ~= "" then
        dict[k] = v
        if (utf8.len(k) or 0) > 1 then freq[k] = math.max(freq[k] or 0, USER_FREQ) end
      end
    end
    f:close()
  end
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

local function chars_of(text)
  local chars = {}
  for _, cp in utf8.codes(text) do chars[#chars + 1] = utf8.char(cp) end
  return chars
end

-- 逐词对照只取第一个释义，并去掉括号里的说明：「a (film)」→ a，「(measure word)」→ 空
local function first_gloss(en)
  local g = (en:match("^([^,]+)") or en):gsub("%b()", ""):gsub("%s+", " ")
  return (g:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 最大概率分词：每个词的代价是 -log(词频/总词频)，取整句代价最小的切法。
-- 没有词频表时每个词代价相同，即切出的词越少越好。词表里没有的单字代价很高。
-- 词表有、词频表没有的多字词（多为 CC-CEDICT 收的短语，如「找不到」「有道理」）按一个较低的词频算，
-- 让它们仍能胜过拆成常用单字的切法；这类单字则当作只出现过 1 次。
local UNKNOWN_COST = 40
local DICT_ONLY_FREQ = 30
local function word_cost(w, len)
  local f = freq[w]
  if f then return log_total - math.log(f) end
  if log_total == 0 then return 1 end
  return log_total - (len == 1 and 0 or math.log(DICT_ONLY_FREQ))
end

local function segment(chars, d)
  local n = #chars
  local best, back = { [0] = 0 }, {}
  for i = 1, n do
    best[i] = math.huge
    for len = math.min(MAX_WORD, i), 1, -1 do
      local w = table.concat(chars, "", i - len + 1, i)
      local c
      if d[w] then c = word_cost(w, len) elseif len == 1 then c = UNKNOWN_COST + log_total end
      if c and best[i - len] + c < best[i] then
        best[i], back[i] = best[i - len] + c, len
      end
    end
  end
  local words, i = {}, n
  while i > 0 do
    table.insert(words, 1, table.concat(chars, "", i - back[i] + 1, i))
    i = i - back[i]
  end
  return words
end

local function last_char(w)
  local c
  for _, cp in utf8.codes(w) do c = cp end
  return c and utf8.char(c) or ""
end

-- 分词并给每个词挑一个放在句子里合适的英文。
-- 返回 tokens：{ w = 中文, en = 英文或 nil }，en 为 nil 的是跳过的虚词/量词或查不到的字
local function tokenize(text, d)
  local words = segment(chars_of(text), d)
  local toks, particles, unknown = {}, 0, 0
  for k, w in ipairs(words) do
    local tok = { w = w }
    local single = utf8.len(w) == 1
    local prev, next_w = words[k - 1], words[k + 1]
    if single and SKIP[w] then
      particles = particles + 1
    elseif CLASSIFIER[w] and prev and NUM_DEM[last_char(prev)] then
      -- 量词：不翻译
    elseif not d[w] then
      unknown = unknown + 1
    else
      local en = first_gloss(d[w])
      local is_last = not next_w or (SKIP[next_w] and not words[k + 2])
      if POSSESSIVE[w] and next_w == "的" then
        en = (not words[k + 2] and MINE[w]) or POSSESSIVE[w]
      elseif OBJECT[w] and prev and (BEFORE_OBJECT[prev] or (not next_w and not CONJUNCTION[prev])) then
        en = OBJECT[w]
      elseif LOCATIVE[w] and prev and is_last and not SKIP[prev] then
        en = LOCATIVE[w]
      elseif w == "对" and next_w and not SKIP[next_w] then
        en = "to"                                  -- 他对我很好 / 我对这个不感兴趣
      elseif w == "给" and prev and not PRONOUN[prev] and next_w and PRONOUN[next_w] then
        en = "to"                                  -- 发给我 / 打电话给你
      elseif w == "到" and (not next_w or next_w == "了") then
        en = "arrive"                              -- 我马上到 / 外卖到了
      end
      if en ~= "" then tok.en = en end
    end
    toks[#toks + 1] = tok
  end
  return toks, particles, unknown
end

-- 逐词对照，返回英文、实词个数、语气词个数与分词结果。
-- 若还有查不到的字且实词不足 2 个，英文为 nil（避免只露出半个意思）
local function gloss(text, d)
  local toks, particles, unknown = tokenize(text, d)
  local out = {}
  for _, t in ipairs(toks) do
    if t.en and t.en ~= out[#out] then out[#out + 1] = t.en end
  end
  if #out == 0 or (#out < 2 and unknown > 0) then return nil, #out, particles, toks end
  local g = table.concat(out, GLOSS_SEP)
  local chars = chars_of(text)
  if QUESTION[chars[#chars]] and g:sub(-1) ~= "?" then g = g .. "?" end
  return g, #out, particles, toks
end

-- 一次请求翻译多条，结果写入 mt_cache（失败/超时则什么都不写）。
-- 服务返回「译文<TAB>平均对数概率」；旧版服务只返回译文，也能用。
local function translate_batch(texts)
  if #texts == 0 or CN2EN_NO_MT then return end   -- CN2EN_NO_MT：测试脚本用，只测逐词对照
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
    local line, score = raw:match("^(.-)\t(%-?[%d%.]+)%s*$")
    line = (line or raw):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      if mt_cache_size > 5000 then mt_cache, mt_cache_size = {}, 0 end
      mt_cache[t] = { text = line, score = tonumber(score) }
      mt_cache_size = mt_cache_size + 1
    end
  end
end

-- 译文是否可信。
-- 长度：英文词数不应远多于原文实词数（否则多半是给半句脑补了内容）；
--       语气词也带意思（了吗 ≈ have ... yet?），每个放宽 1 个英文词。
-- 把握：模型给出的平均对数概率太低，说明它自己也在瞎猜。旧版服务不返回分数时跳过这一项。
local function mt_plausible(tr, note)
  local en_words, gloss_words = 0, 0
  for _ in tr.text:gmatch("%a+") do en_words = en_words + 1 end
  -- 逐词对照里一个词条可能是短语（好久不见 → long time no see），按英文单词数算更公平
  for _ in (note.gloss or ""):gmatch("%a+") do gloss_words = gloss_words + 1 end
  if en_words > 2.2 * math.max(note.n, gloss_words, 1) + 1 + (note.p or 0) then return false end
  return not (tr.score and tr.score < MT_MIN_SCORE)
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
local function flush(buf, d, first_idx, use_mt)
  local notes, todo = {}, {}
  for k, cand in ipairs(buf) do
    local t = cand.text
    if d[t] then
      notes[k] = d[t]
    elseif is_all_cjk(t) then
      local g, n_words, n_particles = gloss(t, d)
      local len = utf8.len(t) or 0
      local min_len = (n_particles or 0) > 0 and MT_MIN_CHARS_PARTICLE or MT_MIN_CHARS
      if use_mt and first_idx + k - 1 == 1 and len >= min_len and len <= MT_MAX_CHARS then
        notes[k] = { gloss = g, n = n_words, p = n_particles }
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
      if tr and mt_plausible(tr, note) then note = tr.text else note = note.gloss end
    end
    if note then yield(with_comment(cand, note)) else yield(cand) end
  end
end

local function filter(input, env)
  local ctx = env.engine.context
  if ctx:get_option("cn2en_off") then        -- 「纯中」：原样放行
    for cand in input:iter() do yield(cand) end
    return
  end
  local use_mt = not ctx:get_option("cn2en_no_mt")
  local d = dict or load_dict()
  local chunk = env.chunk or 6
  local buf, idx = {}, 1
  for cand in input:iter() do
    buf[#buf + 1] = cand
    if #buf >= chunk then
      flush(buf, d, idx, use_mt)
      idx = idx + #buf
      buf = {}
    end
  end
  flush(buf, d, idx, use_mt)
end

-- 末尾的 _test 只给 tools/test_cn2en.lua 用，Rime 只认 init / func
return { init = init, func = filter, _test = { gloss = gloss, mt_plausible = mt_plausible } }

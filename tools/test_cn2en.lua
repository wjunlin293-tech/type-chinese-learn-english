-- 不开输入法也能测试 cn2en.lua：模拟 Rime 的候选菜单，打印每个候选旁边会显示的英文。
--
-- 用法（在仓库根目录）：
--   lua tools/test_cn2en.lua tools/test_cases.txt        # 打印结果
--   lua tools/test_cn2en.lua tools/test_cases.txt --check  # 只打印与期望不符的行，有不符则退出码为 1
--   lua tools/test_cn2en.lua tools/test_cases_mt.txt       # 整句翻译（需要本机翻译服务在运行）
-- 加 --no-mt 则不请求翻译服务，只测词表和逐词对照（test_cases.txt 的期望都是按这种方式写的）。
--
-- 用例文件每行一组候选，用 | 分隔，第一个是首选；# 开头为注释。
-- 行尾可以写「=> 期望」：期望的英文里每个以 / 分隔的片段都必须出现在首选的注释里，
-- 以 ! 开头的片段则必须不出现。例如：
--   很好吃 => tasty / !devastating
-- 首选整句会请求本机翻译服务 127.0.0.1:18085；服务没开时自动退回逐词对照。
-- macOS 上没有 lua 命令的话：brew install lua

local flags = {}
for i = 2, #arg do flags[arg[i]] = true end
local root = (arg[0]:match("^(.*)/tools/[^/]+$") or ".")
CN2EN_NO_MT = flags["--no-mt"]
CN2EN_DATA_DIR = root .. "/data"
rime_api = { get_user_data_dir = function() return root end }
log = { error = function(m) io.stderr:write(m, "\n") end }
function ShadowCandidate(c, t, text, comment) return { text = text, comment = comment, type = t } end

local out
function yield(c) out[#out + 1] = c end

local mod = dofile(root .. "/mac/lua/cn2en.lua")
local env = { engine = { schema = { page_size = 5 } } }
mod.init(env)

local check = flags["--check"]
local failed = 0
for line in io.lines(arg[1] or (root .. "/tools/test_cases.txt")) do
  line = line:gsub("%s+$", "")
  if line ~= "" and not line:match("^#") then
    local cands_s, expect = line:match("^(.-)%s*=>%s*(.*)$")
    cands_s = cands_s or line
    local cands = {}
    for t in cands_s:gmatch("[^|]+") do cands[#cands + 1] = { text = t, comment = "", type = "test" } end
    out = {}
    local i = 0
    mod.func({ iter = function() return function() i = i + 1; return cands[i] end end }, env)
    local parts = {}
    for _, c in ipairs(out) do parts[#parts + 1] = c.text .. " → " .. (c.comment ~= "" and c.comment or "∅") end
    local shown = table.concat(parts, "   |   ")
    local ok = true
    if expect then
      local first = (out[1] and out[1].comment or ""):lower()
      for piece in expect:gmatch("[^/]+") do
        piece = piece:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        local neg = piece:sub(1, 1) == "!"
        if neg then piece = piece:sub(2) end
        local found = first:find(piece, 1, true) ~= nil
        if found == neg then ok = false end
      end
    end
    if not ok then
      failed = failed + 1
      print("✗ " .. shown .. "    (期望: " .. expect .. ")")
    elseif not check then
      print((expect and "✓ " or "  ") .. shown)
    end
  end
end
if failed > 0 then
  print(failed .. " 条与期望不符")
  os.exit(1)
end

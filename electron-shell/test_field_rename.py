# -*- coding: utf-8 -*-
"""合成用例:验证字段改名的行为等价性,覆盖各种危险模式。"""
import sys
sys.path.insert(0, "electron-shell")
from lua_obfuscator import obfuscate_file_enhanced, collect_field_names
from lupa.lua54 import LuaRuntime

rt = LuaRuntime()
rt.execute('''
local function ser(v, depth)
  depth = depth or 0
  local t = type(v)
  if t == "table" then
    if depth > 6 then return "<deep>" end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, ks in ipairs(keys) do
      local kv = v[ks]; if kv == nil then kv = v[tonumber(ks)] end
      parts[#parts+1] = ks .. "=" .. ser(kv, depth+1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "function" then return "<fn>"
  else return tostring(v) end
end
function RUN(c)
  local f, e = load(c)
  if not f then return "LOADERR:"..tostring(e) end
  local ok, r = pcall(f)
  if not ok then return "RUNERR:"..tostring(r):sub(1,80) end
  return ser(r)
end
''')
RUN = rt.eval("RUN")

# 每个用例: (代码, 该项目内"私有"字段集[模拟 analyze 结果])
# 危险模式覆盖
CASES = {
# 1. 方法定义+调用,同文件
"method_def_call": ('''
local M = {}
function M.add(a, b) return a + b end
function M.run() return M.add(2, 3) end
return M.run()
''', {"add", "run"}),
# 2. self 方法 + 字段
"self_method": ('''
local M = {}
M.__index = M
function M.new(v) local o = setmetatable({}, M); o.val = v; return o end
function M:get() return self.val end
function M:bump(d) self.val = self.val + d; return self end
return M.new(1):bump(4):get()
''', {"new", "get", "bump", "val"}),
# 3. 表构造器 key(数据),整表返回并同文件访问
"ctor_data_keys": ('''
local cfg = { hp = 10, mp = 20 }
return cfg.hp + cfg.mp
''', {"hp", "mp"}),
# 4. 字段名与变量名同名(不同命名空间)
"field_vs_var": ('''
local get = 100
local M = { get = function() return get end }
return M.get()
''', {"get"}),
# 5. 方法调用链 self:a():b()
"chain": ('''
local M = {} M.__index = M
function M.new() return setmetatable({n=0}, M) end
function M:inc() self.n = self.n + 1 return self end
function M:get() return self.n end
return M.new():inc():inc():get()
''', {"new","inc","get","n"}),
# 6. 私有方法只被 self 调用
"private_method": ('''
local M = {}
function M.helper(x) return x * 2 end
function M.pub(y) return M.helper(y) + 1 end
return M.pub(5)
''', {"helper","pub"}),
# 7. 字段作为回调存储
"callback_field": ('''
local M = {}
M.cb = function(x) return x + 1 end
local f = M.cb
return f(10)
''', {"cb"}),
# 8. 嵌套表字段
"nested": ('''
local M = { inner = { val = 7, getv = function(s) return s.val end } }
return M.inner.getv(M.inner)
''', {"inner","val","getv"}),
}

passed = failed = 0
for name, (code, fields) in CASES.items():
    obf, status, detail, fmap = obfuscate_file_enhanced(code, allowed_fields=fields, strip_comments=False)
    if status == "rejected":
        print("REJECT %-18s %s" % (name, detail)); failed += 1; continue
    r1 = RUN(code)
    r2 = RUN(obf)
    if r1 == r2 and not r1.startswith(("LOADERR","RUNERR")):
        passed += 1
        print("PASS   %-18s => %s  (fields: %s)" % (name, r1, dict(list(fmap.items())[:4])))
    else:
        failed += 1
        print("FAIL   %-18s" % name)
        print("   orig:", r1)
        print("   obf :", r2)
        print("   obf code:", obf.replace(chr(10)," ")[:160])

print("\n== synthetic field-rename: %d passed, %d failed ==" % (passed, failed))
sys.exit(0 if failed==0 else 1)

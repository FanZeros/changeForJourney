# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, "electron-shell")
from lua_obfuscator import obfuscate_file_safe
from lupa.lua54 import LuaRuntime

CASES = {
"local_basic": '''
local a = 1
local b = a + 2
return a + b
''',
"recursion": '''
local function fib(n)
  if n < 2 then return n end
  return fib(n-1) + fib(n-2)
end
return fib(10)
''',
"upvalue_closure": '''
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c = counter()
c(); c()
return c()
''',
"shadowing": '''
local x = "outer"
local function f()
  local x = "inner"
  return x
end
return x .. "/" .. f()
''',
"numeric_for": '''
local s = 0
for i = 1, 5 do s = s + i end
return s
''',
"generic_for": '''
local t = {a=1,b=2,c=3}
local s = 0
for k, v in pairs(t) do s = s + v end
return s
''',
"method_self": '''
local M = {}
M.__index = M
function M.new(v) local o = setmetatable({}, M); o.v = v; return o end
function M:get() return self.v end
function M:inc(d) self.v = self.v + d; return self end
return M.new(10):inc(5):get()
''',
"nested_anon": '''
local function f(a)
  return function(b)
    return function(c) return a + b + c end
  end
end
return f(1)(2)(3)
''',
"varargs": '''
local function sum(...)
  local t = {...}
  local s = 0
  for _, v in ipairs(t) do s = s + v end
  return s
end
return sum(1,2,3,4)
''',
"multiple_assign": '''
local a, b, c = 1, 2, 3
a, b = b, a
return a + b + c
''',
"repeat_until": '''
local i = 0
local s = 0
repeat
  i = i + 1
  s = s + i
until i >= 5
return s
''',
"while_do": '''
local i = 0
local s = 0
while i < 5 do i = i + 1; s = s + i end
return s
''',
"goto_label": '''
local s = 0
for i = 1, 10 do
  if i % 2 == 0 then goto continue end
  s = s + i
  ::continue::
end
return s
''',
"table_methods": '''
local M = {}
function M.Get() return 42 end
function M.GetFor(x) return x * 2 end
local m = M
return m.Get() + m.GetFor(5)
''',
"string_preserve": '''
local require = require
local mod = "config.StageConfig"
local s = "hello \\"world\\" \\'x\\' [[y]]"
local long = [[multi
line
string]]
return #mod .. #s .. #long
''',
"local_const": '''
local K <const> = 7
local x = K * 2
return x
''',
"closure_shared_upvalue": '''
local function makepair()
  local val = 0
  local function get() return val end
  local function set(v) val = v end
  return get, set
end
local get, set = makepair()
set(99)
return get()
''',
"nested_scope_reuse": '''
local total = 0
for i = 1, 3 do
  local i = i * 10
  total = total + i
end
return total
''',
"elseif_chain": '''
local function grade(n)
  if n >= 90 then return "A"
  elseif n >= 80 then return "B"
  else return "C" end
end
return grade(95) .. grade(85) .. grade(50)
''',
"do_block": '''
local x = 1
do
  local x = 2
  x = x + 10
end
return x
''',
"field_vs_local": '''
local obj = {}
obj.field = 1
local field = 2
return obj.field + field
''',
}

def run(code, runtime):
    try:
        fn = runtime.eval("function(c) return load(c)() end")
        return ("ok", fn(code))
    except Exception as e:
        return ("err", str(e)[:80])

def main():
    rt = LuaRuntime()
    passed = failed = rejected = 0
    for name, code in CASES.items():
        obf, status, detail = obfuscate_file_safe(code)
        if status == "rejected":
            print("REJECT %-24s %s" % (name, detail)); rejected += 1; continue
        r_orig = run(code, rt)
        r_obf = run(obf, rt)
        # normalize lua return of numbers
        if r_orig == r_obf and r_orig[0] == "ok":
            passed += 1
        else:
            failed += 1
            print("FAIL %-24s" % name)
            print("   orig:", r_orig)
            print("   obf :", r_obf)
            print("   code:", obf[:200].replace(chr(10), " "))
    print("\n== behavior equivalence: %d passed, %d failed, %d rejected ==" % (passed, failed, rejected))
    return 0 if failed == 0 and rejected == 0 else 1

sys.exit(main())

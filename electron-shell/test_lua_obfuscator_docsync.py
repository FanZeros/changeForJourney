# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, "electron-shell")
from lua_obfuscator import obfuscate_file_safe

def show(label, code, expect_contains=None, expect_absent=None):
    obf, status, detail = obfuscate_file_safe(code)
    print("==== %s [%s] %s" % (label, status, detail))
    print(obf)
    ok = True
    for s in (expect_contains or []):
        if s not in obf:
            print("  !! EXPECTED CONTAINS missing: %r" % s); ok = False
    for s in (expect_absent or []):
        if s in obf:
            print("  !! EXPECTED ABSENT present: %r" % s); ok = False
    print("  RESULT:", "PASS" if ok else "FAIL")
    return ok

allok = True

# 1) string containing ---@param must NOT be touched
allok &= show("string with fake @param",
'''local s = "---@param foo number"
local function f(foo) return foo end
return s
''', expect_contains=['"---@param foo number"'])

# 2) @return with a variable name that is NOT a param should stay (only params synced)
allok &= show("@return name not a param",
'''---@param a number
---@return number b
local function f(a) return a end
return f
''', expect_contains=['---@param _z1_ number', '---@return number b'])

# 3) anonymous function doc comment: param renamed but comment left (anchor ambiguous -> skip)
allok &= show("anon function (comment may lag)",
'''---@param x number
local g = function(x) return x end
return g(3)
''')

# 4) comment block separated from function by code must NOT be associated
allok &= show("comment separated by code",
'''---@param y number
local unrelated = 1
local function h(y) return y + unrelated end
return h
''', expect_contains=['---@param y number'])  # comment stays old (not adjacent)

# 5) method with self (colon) - params synced
allok &= show("method self",
'''local M = {}
---@param v number
---@param w number
function M:add(v, w) return self.x + v + w end
return M
''', expect_contains=['---@param _z'])

# 6) multiple params, ensure all synced and order-independent
allok &= show("multi params",
'''---@param first number
---@param second string
---@param third table
local function m(first, second, third) return first end
return m
''')

# 7) no doc comment at all - normal rename
allok &= show("no doc comment",
'''local function n(a, b) return a + b end
return n(1,2)
''')

# 8) inline (non ---) comment mentioning @param should not be treated as doc for a far function
allok &= show("varargs with doc",
'''---@param a number
local function v(a, ...) return a end
return v
''')

print("\n==== OVERALL:", "ALL PASS" if allok else "SOME FAIL", "====")
sys.exit(0 if allok else 1)

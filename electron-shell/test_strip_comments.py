# -*- coding: utf-8 -*-
import sys
sys.path.insert(0, "electron-shell")
from lua_obfuscator import strip_comments_code, obfuscate_file_enhanced
from lupa.lua54 import LuaRuntime

rt = LuaRuntime()

CASES = {
"line_comment": '''-- this is a comment
local x = 1  -- trailing
return x
''',
"emmylua_kept": '''---@param a number the a
---@return number
local function f(a) return a end
return f(5)
''',
"block_comment": '''--[[ block
comment ]]
local y = 2
return y
''',
"as_assert_kept": '''local z = someGlobal() --[[@as number]]
return 1
''',
"string_with_dashes": '''local s = "a -- b"
local t = '--not a comment'
local u = [[long -- string]]
return #s + #t + #u
''',
"double_dash_only": '''local a = 1
---- separator line (4 dashes, kept as annotation-ish)
return a
''',
}

allok = True
for name, code in CASES.items():
    out, edits = strip_comments_code(code)
    print("==== %s (removed %d comment regions) ====" % (name, len(edits)))
    print(out)
    # behavior: 对可运行的用例验证等价
    if name in ("line_comment","emmylua_kept","block_comment","string_with_dashes","double_dash_only"):
        try:
            r1 = rt.eval("function(c) local f=load(c) return f and select(2,pcall(f)) end")(code)
            r2 = rt.eval("function(c) local f=load(c) return f and select(2,pcall(f)) end")(out)
            ok = (r1 == r2)
        except Exception as e:
            ok = None
        print("  behavior equiv:", ok)
        if ok is False: allok = False
    print()

# 断言检查
def must_contain(name, code, needle):
    out, _ = strip_comments_code(code)
    if needle not in out:
        print("ASSERT FAIL [%s]: expected %r in output" % (name, needle)); return False
    return True
def must_not(name, code, needle):
    out, _ = strip_comments_code(code)
    if needle in out:
        print("ASSERT FAIL [%s]: unexpected %r in output" % (name, needle)); return False
    return True

allok &= must_not("line_comment", CASES["line_comment"], "this is a comment")
allok &= must_not("line_comment", CASES["line_comment"], "trailing")
allok &= must_contain("emmylua_kept", CASES["emmylua_kept"], "---@param a number")
allok &= must_not("block_comment", CASES["block_comment"], "block")
allok &= must_contain("as_assert_kept", CASES["as_assert_kept"], "--[[@as number]]")
allok &= must_contain("string_with_dashes", CASES["string_with_dashes"], "a -- b")
allok &= must_contain("string_with_dashes", CASES["string_with_dashes"], "--not a comment")
allok &= must_contain("string_with_dashes", CASES["string_with_dashes"], "long -- string")

print("== strip comments:", "ALL PASS" if allok else "SOME FAIL", "==")
sys.exit(0 if allok else 1)

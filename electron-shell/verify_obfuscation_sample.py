# -*- coding: utf-8 -*-
"""行为等价抽样：用确定性序列化（排序键、table 地址无关）比对原版与混淆版返回值。"""
import sys, glob, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa.lua54 import LuaRuntime

# 用法: python verify_obfuscation_sample.py [obfuscated_output_root] [source_root]
# 默认对比 ./scripts 与 ../obf-out/scripts（obfuscator 的 --output-root）。
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/obf-out")
SRC_ROOT = sys.argv[2] if len(sys.argv) > 2 else "."
rt = LuaRuntime()

# 一个确定性 deep-serialize，运行 chunk 并把返回值序列化成稳定字符串
SERIALIZE = r'''
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
      -- 只序列化可 tostring 回原键的（string/number 键），跳过复杂键
      local kv
      if v[ks] ~= nil then kv = v[ks] else kv = v[tonumber(ks)] end
      parts[#parts+1] = ks .. "=" .. ser(kv, depth+1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "function" then
    return "<fn>"
  else
    return tostring(v)
  end
end
function run_and_serialize(code)
  local f, err = load(code)
  if not f then return "LOADERR:" .. tostring(err) end
  local ok, r = pcall(f)
  if not ok then return "RUNERR:" .. tostring(r):sub(1,60) end
  return ser(r)
end
'''
rt.execute(SERIALIZE)
run_ser = rt.eval("run_and_serialize")

def has_engine_dep(code):
    markers = ['require(', 'Vector3(', 'Vector2(', 'cache:', 'node:', 'scene:', 'graphics',
               'renderer', 'input.', 'SubscribeToEvent', 'nvg', 'Color(', 'Quaternion(',
               'engine', 'sdk:', 'clientCloud']
    return any(m in code for m in markers)

tested = passed = 0
mismatch = []
skipped = 0
for path in sorted(glob.glob(os.path.join(SRC_ROOT, "scripts/**/*.lua"), recursive=True)):
    orig = open(path, encoding="utf-8").read()
    rel = os.path.relpath(path, SRC_ROOT)
    obf_path = os.path.join(OUT, rel)
    if not os.path.exists(obf_path):
        continue
    obf = open(obf_path, encoding="utf-8").read()
    if has_engine_dep(orig):
        skipped += 1
        continue
    try:
        r1 = run_ser(orig)
        r2 = run_ser(obf)
    except Exception as e:
        skipped += 1
        continue
    tested += 1
    if r1 == r2:
        passed += 1
    else:
        mismatch.append((path, r1[:120], r2[:120]))

for m in mismatch[:20]:
    print("MISMATCH", m[0])
    print("   orig:", m[1])
    print("   obf :", m[2])
print("behavior sample: tested=%d passed=%d mismatch=%d skipped(engine-dep)=%d" % (
    tested, passed, len(mismatch), skipped))

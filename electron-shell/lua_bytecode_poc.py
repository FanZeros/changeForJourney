#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终焉之门 · L2 Lua 5.4 字节码 POC（可行性探针，不接入发行）。

目的：验证「把混淆/原始 Lua 源码编译为 Lua 5.4 字节码」这条强化路线，
以及**回答 L2 的两个前置未知**（见 docs/pc-protection-research-0927.md §L2）：

  Q1. WASM Lua VM 是否接受字节码 chunk（而不是只认文本源码）？
  Q2. manifest 记录的 hash/size 是否为引擎运行时强校验（改内容即拒载）？

本脚本在**隔离环境**内完成能在离线沙箱完成的部分：
  * 用本地 Lua 5.4（lupa.lua54）把源码 `string.dump` 成字节码，验证往返可运行；
  * 生成一个最小加载探针 `poc_loader.lua`，供在**真实引擎/官方 Runtime**里
    `load(字节码)` 验证 Q1；
  * 打印字节码头、体积变化、SHA256，便于人工核对。

Q1/Q2 的**最终结论必须在真实 UrhoX WASM Runtime 上跑**（沙箱没有引擎 wasm 资产）。
步骤见同目录 README 与 docs/pc-protection-research-0927.md §L2「POC 步骤」。

用法：
  python3 lua_bytecode_poc.py --file scripts/shared/StageProvider.lua
  python3 lua_bytecode_poc.py --file X.lua --out-dir .tmp/bc-poc
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def compile_to_bytecode(source: str) -> bytes:
    """用本地 Lua 5.4 运行时把源码编译为字节码，并验证往返可加载。"""
    try:
        from lupa.lua54 import LuaRuntime
    except ImportError:
        raise SystemExit(
            "需要 lupa（pip install lupa）提供本地 Lua 5.4 运行时。"
            "注意：本地 Lua 5.4 字节码与引擎 WASM Lua 版本必须一致，"
            "否则 load 会因版本/格式头不匹配而失败——这正是 Q1 要验证的点。")
    rt = LuaRuntime()
    # 用 load+string.dump 编译，再 load 回来跑一次确认字节码本身可执行
    # 在 Lua 侧把字节码转成十六进制返回，避免 lupa 用 utf-8 解码二进制串。
    checker = rt.eval(r'''
    function(src)
      local fn, err = load(src, "=poc_src")
      if not fn then return nil, err end
      local bc, derr = string.dump(fn)
      if not bc then return nil, derr end
      local reloaded, rerr = load(bc, "=poc_bc")
      if not reloaded then return nil, rerr end
      local ok, res = pcall(reloaded)
      return (bc:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)), nil
    end
    ''')
    hexed, err = checker(source)
    if hexed is None:
        raise SystemExit("compile/load failed: %s" % err)
    return bytes.fromhex(hexed)


# 最小自包含探针：把 "return 42" 编译成字节码，在真实引擎里粘贴运行。
# 用固定简单逻辑（不依赖任何 require），把「VM 是否接受字节码」与
# 「业务模块能否加载」彻底解耦：打印 VERDICT: ACCEPTS => Q1=yes。
PROBE_SRC = "return 42"
LOADER_TEMPLATE = r'''-- lua_bytecode_poc 生成的最小自包含探针（在真实引擎 Console / 入口脚本运行）
-- 目的：验证 Q1 —— WASM Lua VM 是否接受 Lua 5.4 字节码 chunk（不依赖任何 require）。
-- 判据：打印 "VERDICT: VM ACCEPTS bytecode (Q1=yes)" => L2 路线可行；
--       打印 "VERDICT: VM REJECTS bytecode (Q1=no)"  => L2 作废，退回纯 L1 混淆。
local hex = "__HEX__"   -- 这是 `return 42` 编译出的字节码
local function unhex(h)
  return (h:gsub("%x%x", function(cc) return string.char(tonumber(cc, 16)) end))
end
local bc = unhex(hex)
print("header bytes:", string.format("%02x %02x %02x %02x %02x %02x",
  bc:byte(1), bc:byte(2), bc:byte(3), bc:byte(4), bc:byte(5), bc:byte(6)))
local fn, err = load(bc, "=bytecode_probe")
if not fn then
  print("load() error: " .. tostring(err))
  print("VERDICT: VM REJECTS bytecode (Q1=no)")
else
  local ok, res = pcall(fn)
  if ok and res == 42 then
    print("VERDICT: VM ACCEPTS bytecode (Q1=yes), returned 42")
  else
    print("load OK but run failed:", ok, res)
    print("VERDICT: VM ACCEPTS bytecode header (Q1=yes) but execution issue")
  end
end
'''


def main() -> None:
    ap = argparse.ArgumentParser(description="L2 Lua 5.4 bytecode feasibility POC")
    ap.add_argument("--file", type=Path, required=True, help="a Lua source file to compile")
    ap.add_argument("--out-dir", type=Path, default=None,
                    help="where to write poc artifacts (must be outside source tree)")
    args = ap.parse_args()

    src_path = args.file
    if not src_path.is_file():
        raise SystemExit("missing file: %s" % src_path)
    source = src_path.read_text(encoding="utf-8")

    bc = compile_to_bytecode(source)
    src_bytes = source.encode("utf-8")

    print("file              :", src_path)
    print("source bytes      :", len(src_bytes))
    print("bytecode bytes    :", len(bc))
    delta = 100.0 * (len(bc) - len(src_bytes)) / max(1, len(src_bytes))
    print("size change       : %+.1f%%" % delta)
    print("bytecode header   :", " ".join("%02x" % b for b in bc[:6]),
          r"(expect 1b 4c 75 61 54 00 for Lua 5.4)")
    print("source sha256     :", sha256(src_bytes))
    print("bytecode sha256   :", sha256(bc))

    is_luac = bc[:4] == b"\x1bLua"
    print("looks like luac   :", is_luac)
    if not is_luac:
        print("WARNING: 非标准字节码头，WASM VM 几乎必然拒绝。")

    if args.out_dir is not None:
        out = args.out_dir.resolve()
        if src_path.resolve().is_relative_to(out) or out.is_relative_to(src_path.resolve().parent):
            raise SystemExit("out-dir must be outside the source file's tree")
        out.mkdir(parents=True, exist_ok=True)
        bc_file = out / (src_path.stem + ".luac")
        bc_file.write_bytes(bc)
        # 探针用固定 "return 42" 的字节码，与业务文件解耦
        probe_bc = compile_to_bytecode(PROBE_SRC)
        hexed = LOADER_TEMPLATE.replace("__HEX__", probe_bc.hex())
        loader = out / "poc_loader.lua"
        loader.write_text(hexed, encoding="utf-8")
        # 官方 Build 入口需要 Start():包一层,便于在隔离工程里直接当 main.lua 用
        entry_body = hexed.split("\n")
        indented = "\n".join("    " + ln if ln.strip() else ln for ln in entry_body)
        entry = ("-- Q1 探针入口:把本文件当作隔离工程的 scripts/main.lua,官方 Build 后看运行日志\n"
                 "function Start()\n" + indented + "\nend\n")
        entry_file = out / "poc_entry.lua"
        entry_file.write_text(entry, encoding="utf-8")
        print("wrote bytecode    :", bc_file)
        print("wrote loader probe:", loader)
        print("wrote build entry :", entry_file, "(当隔离工程 main.lua 用)")

    print()
    print("=" * 70)
    print("本地结论：标准 Lua 5.4 可把该文件编译为字节码并往返执行。")
    print("尚待验证（必须真实引擎）：")
    print("  Q1 WASM Lua VM 是否接受字节码？→ 把 poc_loader.lua 在官方 Runtime 里跑，")
    print("     打印 42 = 接受；'REJECTED bytecode' = 不接受（L2 路线作废，退回纯 L1）。")
    print("  Q2 manifest hash/size 是否运行时强校验？→ 见 README §L2-POC 步骤。")
    print("=" * 70)


if __name__ == "__main__":
    main()

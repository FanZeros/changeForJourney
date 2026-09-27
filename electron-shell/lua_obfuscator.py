#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终焉之门 · L1 保守 Lua 混淆器（作用域安全重命名）。

设计目标（与 docs/pc-protection-research-0927.md 的 L1 一致）：
  * 只重命名 **局部绑定**：文件级 local、函数参数、for 循环变量、local function、
    嵌套匿名函数的 local。
  * **永不改名**：全局名（引擎 API / require 到的模块 / 未声明标识符）、
    所有字段名与方法名（`.`/`:` 之后、表构造器 key、Funcname 中 `.`/`:` 之后）、
    require 路径字符串、goto label。
  * **逐字节保留** 注释（含官方 LSP 依赖的 EmmyLua `---` 注释）、字符串、
    数字、空白与排版：改写机制只 splice NAME token 的字符区间，其余原样拷贝。

实现基础：luaparser 内置 ANTLR 语法树（保留每个 NAME 的精确 start/stop 字符偏移
与语法上下文），据此做标准 Lua 作用域解析。

安全策略：任何无法解析、含未知语法形态、或未通过全部等价校验的文件，一律
**拒绝改写并原样复制**，宁可漏混淆也不冒运行期破坏的风险。

用法：
  python3 lua_obfuscator.py --source-root . --output-root ../obf-out
  # 只处理单文件并打印诊断：
  python3 lua_obfuscator.py --file scripts/shared/StageProvider.lua
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from antlr4 import InputStream, CommonTokenStream, TerminalNode, ParserRuleContext
from luaparser.ast import LuaLexer, LuaParser

# ---------------------------------------------------------------------------
# 语法树工具
# ---------------------------------------------------------------------------

LUA_KEYWORDS = {
    "and","break","do","else","elseif","end","false","for","function","goto",
    "if","in","local","nil","not","or","repeat","return","then","true","until",
    "while","self",
}


def kids(node):
    return [node.getChild(i) for i in range(node.getChildCount())]


_SYM = LuaLexer.symbolicNames


def sym_of(tok_type):
    """安全返回 token 类型的符号名（越界/负数返回 None）。"""
    if isinstance(tok_type, int) and 0 <= tok_type < len(_SYM):
        return _SYM[tok_type]
    return None


def is_name(node):
    return isinstance(node, TerminalNode) and sym_of(node.symbol.type) == "NAME"


def build_parent_map(root):
    pm = {}
    stack = [(root, None)]
    while stack:
        n, p = stack.pop()
        pm[id(n)] = p
        if isinstance(n, ParserRuleContext):
            for c in kids(n):
                stack.append((c, n))
    return pm


def siblings_of(pm, node):
    """返回 (prev_sibling, next_sibling) —— 基于父节点的子列表。"""
    parent = pm.get(id(node))
    if parent is None or not isinstance(parent, ParserRuleContext):
        return None, None
    ch = kids(parent)
    idx = None
    for i, c in enumerate(ch):
        if c is node:
            idx = i
            break
    if idx is None:
        return None, None
    prev = ch[idx - 1] if idx > 0 else None
    nxt = ch[idx + 1] if idx < len(ch) - 1 else None
    return prev, nxt


def prev_token_text(pm, node):
    """前一个兄弟若是终端 token，返回其文本（用于检测 '.' / ':'）。"""
    prev, _ = siblings_of(pm, node)
    if isinstance(prev, TerminalNode):
        return prev.symbol.text
    return None


def ctx_name(node):
    return type(node).__name__


# ---------------------------------------------------------------------------
# 作用域分析 + 重命名规划
# ---------------------------------------------------------------------------

class Scope:
    __slots__ = ("parent", "names")

    def __init__(self, parent=None):
        self.parent = parent
        self.names = {}          # orig -> new

    def lookup(self, orig):
        s = self
        while s is not None:
            if orig in s.names:
                return s.names[orig]
            s = s.parent
        return None

    def declare(self, orig, new):
        self.names[orig] = new


class Analyzer:
    """遍历语法树，规划每个需重命名的 NAME token：[(start, stop_exclusive, new_text)]。

    遇到任何未知/不支持形态时抛 Unsupported，调用方据此拒绝改写该文件。
    """

    class Unsupported(Exception):
        pass

    def __init__(self, root, pm):
        self.root = root
        self.pm = pm
        self.edits = []           # (start, stop, new)
        self.globals_seen = set()  # 未解析到 local 的引用名（=全局/字段基名）
        self.fields_seen = set()   # 字段/方法名（永不改）
        self.counter = 0
        self.reserved = set(LUA_KEYWORDS)

    # -- 名字生成 ----------------------------------------------------------
    def _gen(self):
        while True:
            name = "_z%d_" % self.counter
            self.counter += 1
            if name not in self.reserved:
                self.reserved.add(name)
                return name

    def _record_rename(self, node, new):
        tok = node.symbol
        self.edits.append((tok.start, tok.stop + 1, new))

    # -- 声明 --------------------------------------------------------------
    def _declare(self, node, scope):
        """把一个声明用 NAME terminal 绑定进 scope，并登记改名。"""
        if not is_name(node):
            raise self.Unsupported("expected NAME declaration, got %s" % ctx_name(node))
        orig = node.symbol.text
        new = self._gen()
        scope.declare(orig, new)
        self._record_rename(node, new)

    def _resolve_ref(self, node, scope):
        """把一个引用 NAME 解析到最近的 local；解析不到则视为全局（不改）。"""
        orig = node.symbol.text
        new = scope.lookup(orig)
        if new is None:
            self.globals_seen.add(orig)
            return
        self._record_rename(node, new)

    # -- 主分派 ------------------------------------------------------------
    def visit(self, node, scope):
        if isinstance(node, TerminalNode):
            if is_name(node):
                self._generic_name(node, scope)
            return

        cn = ctx_name(node)
        handler = getattr(self, "h_" + cn, None)
        if handler is not None:
            handler(node, scope)
            return
        # 回退：泛化递归
        for c in kids(node):
            self.visit(c, scope)

    def _generic_name(self, node, scope):
        """泛化递归中遇到 NAME：按前兄弟/父上下文判定字段 vs 引用。"""
        parent = self.pm.get(id(node))
        pcn = ctx_name(parent) if parent is not None else None
        prev_txt = prev_token_text(self.pm, node)
        _, nxt = siblings_of(self.pm, node)

        # 字段/方法名：`.` 或 `:` 之后
        if prev_txt in (".", ":"):
            self.fields_seen.add(node.symbol.text)
            return
        # 表构造器 key：FieldContext 下 `NAME =`
        if pcn == "FieldContext" and isinstance(nxt, TerminalNode) and nxt.symbol.text == "=":
            self.fields_seen.add(node.symbol.text)
            return
        # goto label / target
        if pcn in ("LabelContext", "Stat_gotoContext"):
            return
        # 其余视为引用
        self._resolve_ref(node, scope)

    # -- 具体处理器 --------------------------------------------------------
    def h_ChunkContext(self, node, scope):
        for c in kids(node):
            self.visit(c, scope)

    def h_BlockContext(self, node, scope):
        inner = Scope(scope)
        for c in kids(node):
            self.visit(c, inner)

    def h_Stat_localContext(self, node, scope):
        ch = kids(node)
        # 先访问 RHS（explist）——在声明生效前的外层作用域解析
        for c in ch:
            if ctx_name(c) == "ExplistContext":
                self.visit(c, scope)
        # 再声明 attnamelist 中的名字
        for c in ch:
            if ctx_name(c) == "AttnamelistContext":
                for na in kids(c):
                    if ctx_name(na) == "NameattribContext":
                        for t in kids(na):
                            if is_name(t):
                                self._declare(t, scope)
                            # Attrib(<const>/<close>) 无 NAME，忽略

    def h_Stat_localfunctionContext(self, node, scope):
        ch = kids(node)
        # local function NAME 先声明（支持递归），再进 funcbody
        for c in ch:
            if is_name(c):
                self._declare(c, scope)
        for c in ch:
            if ctx_name(c) == "FuncbodyContext":
                self.visit(c, scope)

    def h_Stat_functionContext(self, node, scope):
        for c in kids(node):
            if ctx_name(c) == "FuncnameContext":
                self._funcname(c, scope)
            else:
                self.visit(c, scope)

    def _funcname(self, node, scope):
        """function a.b.c:d() —— 首个 NAME 是变量引用，其后（. / : 之后）都是字段。"""
        first = True
        for t in kids(node):
            if is_name(t):
                if first:
                    self._resolve_ref(t, scope)
                    first = False
                else:
                    self.fields_seen.add(t.symbol.text)
            # DOT/COL 终端忽略

    def h_FuncbodyContext(self, node, scope):
        fscope = Scope(scope)          # 参数所在作用域
        for c in kids(node):
            if ctx_name(c) == "ParlistContext":
                for nl in kids(c):
                    if ctx_name(nl) == "NamelistContext":
                        for t in kids(nl):
                            if is_name(t):
                                self._declare(t, fscope)
                    # `...` 无 NAME
            else:
                self.visit(c, fscope)  # Block 会再压一层子作用域

    def h_Stat_forContext(self, node, scope):
        ch = kids(node)
        numeric = len(ch) > 1 and is_name(ch[1])
        if numeric:
            # for NAME = exp, exp[, exp] do block end
            # 边界表达式在外层作用域求值
            for c in ch:
                if ctx_name(c) == "ExpContext":
                    self.visit(c, scope)
            fs = Scope(scope)
            self._declare(ch[1], fs)
            for c in ch:
                if ctx_name(c) == "BlockContext":
                    self.visit(c, fs)
        else:
            # for namelist in explist do block end
            for c in ch:
                if ctx_name(c) == "ExplistContext":
                    self.visit(c, scope)   # 迭代表达式在外层求值
            fs = Scope(scope)
            for c in ch:
                if ctx_name(c) == "NamelistContext":
                    for t in kids(c):
                        if is_name(t):
                            self._declare(t, fs)
            for c in ch:
                if ctx_name(c) == "BlockContext":
                    self.visit(c, fs)

    def h_Stat_repeatContext(self, node, scope):
        # repeat block until exp —— body 的 local 对 until 可见（同一作用域）
        rs = Scope(scope)
        for c in kids(node):
            if ctx_name(c) == "BlockContext":
                # 不再压新层：body 语句直接声明进 rs
                for st in kids(c):
                    self.visit(st, rs)
            elif ctx_name(c) == "ExpContext":
                self.visit(c, rs)          # until 条件在 rs 中解析
            # REPEAT / UNTIL 终端忽略

    # label / goto：NAME 不改
    def h_LabelContext(self, node, scope):
        return

    def h_Stat_gotoContext(self, node, scope):
        return

    def h_Stat_labelContext(self, node, scope):
        return


# ---------------------------------------------------------------------------
# 解析 → 分析 → splice
# ---------------------------------------------------------------------------

def parse_tree(code: str):
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    parser = LuaParser(ts)
    parser.removeErrorListeners()
    tree = parser.start_()
    if parser.getNumberOfSyntaxErrors():
        raise Analyzer.Unsupported("syntax errors")
    return tree


def plan_renames(code: str):
    tree = parse_tree(code)
    pm = build_parent_map(tree)
    an = Analyzer(tree, pm)
    # 顶层 scope=None：未解析到 local 的引用即全局
    for c in kids(tree):
        an.visit(c, None)
    return an


def apply_edits(code: str, edits) -> str:
    edits = sorted(edits, key=lambda e: e[0])
    # 校验区间不重叠
    prev_end = -1
    for s, e, _ in edits:
        if s < prev_end:
            raise Analyzer.Unsupported("overlapping edits")
        prev_end = e
    out = []
    pos = 0
    for s, e, new in edits:
        out.append(code[pos:s])
        out.append(new)
        pos = e
    out.append(code[pos:])
    return "".join(out)


def obfuscate_source(code: str) -> str:
    an = plan_renames(code)
    return apply_edits(code, an.edits)


# ---------------------------------------------------------------------------
# 安全：保留全部既有标识符，避免生成名与源码冲突
# ---------------------------------------------------------------------------

def _all_name_tokens(code: str):
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    ts.fill()
    for tok in ts.tokens:
        if sym_of(tok.type) == "NAME":
            yield tok.text


def plan_renames(code: str):
    tree = parse_tree(code)
    pm = build_parent_map(tree)
    an = Analyzer(tree, pm)
    # 预扫描：把所有已出现标识符加入 reserved，生成的新名绝不与之冲突
    for existing in _all_name_tokens(code):
        an.reserved.add(existing)
    for c in kids(tree):
        an.visit(c, None)
    return an


# ---------------------------------------------------------------------------
# token 序列指纹（用于等价校验）
# ---------------------------------------------------------------------------

def token_fingerprint(code: str):
    """返回 (非 NAME token 的类型序列, NAME token 的多重集, 字符串字面量序列)。"""
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    ts.fill()
    non_name = []
    names = []
    strings = []
    for tok in ts.tokens:
        sym = sym_of(tok.type)
        if sym is None or tok.type < 0:
            continue  # 跳过 EOF 及隐式 channel
        if sym == "NAME":
            names.append(tok.text)
        else:
            non_name.append(sym)
            if sym == "STRING":
                strings.append(tok.text)
    return non_name, names, strings


def verify_equivalence(original: str, obfuscated: str):
    """校验混淆未改变语义关键结构。返回 None 表示通过，否则抛异常。"""
    # 1) 重新解析成功
    parse_tree(obfuscated)
    o_non, o_names, o_str = token_fingerprint(original)
    n_non, n_names, n_str = token_fingerprint(obfuscated)
    # 2) 非 NAME token 序列逐一致（保证只动了标识符文本，注释/字符串/标点/排版全保留）
    if o_non != n_non:
        raise Analyzer.Unsupported("non-NAME token sequence changed")
    # 3) 字符串字面量完全一致（require 路径等绝不被破坏）
    if o_str != n_str:
        raise Analyzer.Unsupported("string literals changed")
    # 4) NAME token 数量一致
    if len(o_names) != len(n_names):
        raise Analyzer.Unsupported("NAME token count changed")
    # 5) 全局名集不变：任何原本解析为“全局”（非 local）的名字必须原样保留。
    #    通过比较：混淆后仍是全局的名字集合 == 混淆前全局名字集合。
    g_before = _global_names(original)
    g_after = _global_names(obfuscated)
    if g_before != g_after:
        raise Analyzer.Unsupported("global name set changed: %s" %
                                   str(sorted(g_before ^ g_after))[:200])
    return None


def _global_names(code: str) -> set:
    an = plan_renames(code)
    return set(an.globals_seen)


# ---------------------------------------------------------------------------
# 单文件安全混淆（失败即拒绝改写）
# ---------------------------------------------------------------------------

def obfuscate_file_safe(code: str):
    """返回 (obfuscated_code, status, detail)。status in {'changed','unchanged','rejected'}。"""
    try:
        an = plan_renames(code)
        if not an.edits:
            return code, "unchanged", "no local bindings to rename"
        result = apply_edits(code, an.edits)
        verify_equivalence(code, result)
        return result, "changed", "%d renames, %d globals kept" % (
            len(an.edits), len(an.globals_seen))
    except Analyzer.Unsupported as e:
        return code, "rejected", str(e)
    except Exception as e:  # 兜底：任何异常都拒绝改写
        return code, "rejected", "%s: %s" % (type(e).__name__, e)


def run_all(source_root: Path, output_root: Path):
    scripts = source_root / "scripts"
    files = sorted(scripts.rglob("*.lua"))
    if not files:
        raise SystemExit("no Lua scripts found under %s" % scripts)
    if output_root.exists():
        raise SystemExit("output dir already exists: %s" % output_root)
    if output_root == source_root or source_root in output_root.parents \
            or output_root in source_root.parents:
        raise SystemExit("output must be outside the source tree")

    stats = {"changed": 0, "unchanged": 0, "rejected": 0}
    in_bytes = out_bytes = 0
    rejected = []
    for src in files:
        rel = src.relative_to(source_root)
        dst = output_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        code = src.read_text(encoding="utf-8")
        obf, status, detail = obfuscate_file_safe(code)
        dst.write_text(obf, encoding="utf-8")
        stats[status] += 1
        in_bytes += len(code.encode("utf-8"))
        out_bytes += len(obf.encode("utf-8"))
        if status == "rejected":
            rejected.append((str(rel), detail))
    print("files=%d changed=%d unchanged=%d rejected=%d" %
          (len(files), stats["changed"], stats["unchanged"], stats["rejected"]))
    print("bytes: %d -> %d (%.1f%%)" %
          (in_bytes, out_bytes, 100.0 * (out_bytes - in_bytes) / max(1, in_bytes)))
    print("output=%s" % (output_root / "scripts"))
    if rejected:
        print("\nrejected (left as-is):")
        for rel, detail in rejected:
            print("  %s : %s" % (rel, detail))


def main():
    ap = argparse.ArgumentParser(description="L1 conservative Lua obfuscator (scope-safe rename)")
    ap.add_argument("--source-root", type=Path)
    ap.add_argument("--output-root", type=Path)
    ap.add_argument("--file", type=Path, help="obfuscate a single file and print diagnostics")
    args = ap.parse_args()

    if args.file:
        code = args.file.read_text(encoding="utf-8")
        obf, status, detail = obfuscate_file_safe(code)
        print("status=%s detail=%s" % (status, detail))
        if status == "changed":
            print("---- obfuscated ----")
            print(obf)
        return

    if not args.source_root or not args.output_root:
        ap.error("need --source-root and --output-root (or --file)")
    run_all(args.source_root.resolve(), args.output_root.resolve())


if __name__ == "__main__":
    main()

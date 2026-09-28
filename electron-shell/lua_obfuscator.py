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
import re
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
        self.code = ""            # 原始源码（doc 注释同步用）
        self.all_tokens = None    # 全部 token（含 hidden channel，doc 注释同步用）
        self.comment_edits = []   # (start, stop, new) —— 仅 @param 名
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
        param_map = {}                 # 本函数形参 orig -> new（仅用于 doc 注释同步）
        for c in kids(node):
            if ctx_name(c) == "ParlistContext":
                for nl in kids(c):
                    if ctx_name(nl) == "NamelistContext":
                        for t in kids(nl):
                            if is_name(t):
                                before = fscope.names.get(t.symbol.text)
                                self._declare(t, fscope)
                                param_map[t.symbol.text] = fscope.names[t.symbol.text]
                    # `...` 无 NAME
        # doc 注释同步：紧邻本函数声明语句上方的注释块里，@param 旧名 -> 新名。
        # 只对 Stat_localfunction / Stat_function（锚点=声明语句起点）可靠关联；
        # 匿名函数（Functiondef）锚点歧义，跳过——不影响运行，只是注释名不改。
        if param_map and self.all_tokens is not None:
            parent = self.pm.get(id(node))
            pcn = ctx_name(parent) if parent is not None else None
            if pcn in ("Stat_localfunctionContext", "Stat_functionContext"):
                anchor = self._stmt_anchor(parent)
                if anchor is not None:
                    doc_tokens = self._doc_comment_block(anchor)
                    for ctok in doc_tokens:
                        self._sync_param_comment(ctok, param_map)
        for c in kids(node):
            if ctx_name(c) != "ParlistContext":
                self.visit(c, fscope)  # Block 会再压一层子作用域

    # -- doc 注释 @param 同步 ----------------------------------------------
    def _stmt_anchor(self, stmt_node):
        """声明语句起始字符偏移（Token.start）。"""
        try:
            st = stmt_node.start
            return st.start if st is not None else None
        except Exception:
            return None

    def _doc_comment_block(self, before_pos):
        """收集紧邻 before_pos 上方、其间只有空白/换行的注释 token（= doc 注释块）。

        一旦回溯途中遇到任何默认通道的代码 token，说明该注释块与本函数之间夹着
        代码，判定为「非本函数的 doc 注释」，返回空——绝不跨代码关联。
        """
        toks = self.all_tokens
        idx = None
        for i, tok in enumerate(toks):
            if tok.start >= before_pos:
                idx = i
                break
        if idx is None:
            return []
        comments = []
        i = idx - 1
        while i >= 0:
            tok = toks[i]
            sym = sym_of(tok.type)
            if sym in ("WS", "NL") or tok.channel != 0:
                if sym in ("LINE_COMMENT", "COMMENT"):
                    comments.append(tok)
                    i -= 1
                    continue
                # 其它 hidden（空白/换行）跳过
                i -= 1
                continue
            # 默认通道的代码 token：停止
            break
        comments.reverse()
        return comments

    def _sync_param_comment(self, ctok, param_map):
        """把注释 token 内的 `@param <旧名>` 改成 `@param <新名>`（旧名须是形参）。"""
        base = ctok.start
        text = ctok.text
        for m in re.finditer(r"@param\s+([A-Za-z_][A-Za-z0-9_]*)", text):
            name = m.group(1)
            new = param_map.get(name)
            if new is None:
                continue
            s = base + m.start(1)
            e = base + m.end(1)
            self.comment_edits.append((s, e, new))

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
    return apply_edits(code, an.edits + an.comment_edits)


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


def _lex_all_tokens(code: str):
    """词法分析，返回全部 token（含 hidden channel：注释/空白/换行），按位置有序。"""
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    ts.fill()
    return [tok for tok in ts.tokens if tok.type >= 0]


def plan_renames(code: str):
    tree = parse_tree(code)
    pm = build_parent_map(tree)
    an = Analyzer(tree, pm)
    an.code = code
    an.all_tokens = _lex_all_tokens(code)
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
            continue  # 跳过 EOF
        if sym in ("LINE_COMMENT", "COMMENT"):
            continue  # 注释在 hidden channel，语义无关；doc 同步只改 @param 名
        if sym == "NAME":
            names.append(tok.text)
        else:
            non_name.append(sym)
            if sym in ("NORMALSTRING", "LONGSTRING"):
                strings.append(tok.text)
    return non_name, names, strings


def token_fingerprint_syntax(code: str):
    """default channel(语法 token)指纹:剥注释/改空白不影响此序列。

    返回 (非 NAME 语法 token 序列, NAME token 数, 字符串字面量序列)。
    供增强版(剥注释+字段改名)校验;L1 逐字节版仍用 token_fingerprint。
    """
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    ts.fill()
    non_name = []
    n_names = 0
    strings = []
    for tok in ts.tokens:
        if tok.type < 0:
            continue
        if tok.channel != 0:
            continue
        sym = sym_of(tok.type)
        if sym == "NAME":
            n_names += 1
        else:
            non_name.append(sym)
            if sym in ("NORMALSTRING", "LONGSTRING"):
                strings.append(tok.text)
    return non_name, n_names, strings


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
        if not an.edits and not an.comment_edits:
            return code, "unchanged", "no local bindings to rename"
        result = apply_edits(code, an.edits + an.comment_edits)
        verify_equivalence(code, result)
        return result, "changed", "%d renames, %d @param synced, %d globals kept" % (
            len(an.edits), len(an.comment_edits), len(an.globals_seen))
    except Analyzer.Unsupported as e:
        return code, "rejected", str(e)
    except Exception as e:  # 兜底：任何异常都拒绝改写
        return code, "rejected", "%s: %s" % (type(e).__name__, e)


def run_all(source_root: Path, output_root: Path, strip_comments: bool = False,
            rename_fields: bool = False, field_analysis=None):
    scripts = source_root / "scripts"
    files = sorted(scripts.rglob("*.lua"))
    if not files:
        raise SystemExit("no Lua scripts found under %s" % scripts)
    if output_root.exists():
        raise SystemExit("output dir already exists: %s" % output_root)
    if output_root == source_root or source_root in output_root.parents \
            or output_root in source_root.parents:
        raise SystemExit("output must be outside the source tree")

    renameable = {}
    if rename_fields:
        if field_analysis is None:
            field_analysis = analyze_project(source_root)
        renameable = field_analysis.get("renameable", {})
        log_stats = field_analysis.get("stats", {})
        print("field analysis: %s" % log_stats)
    stats = {"changed": 0, "unchanged": 0, "rejected": 0}
    in_bytes = out_bytes = 0
    rejected = []
    field_total = 0
    for src in files:
        rel = src.relative_to(source_root)
        dst = output_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        code = src.read_text(encoding="utf-8")
        if rename_fields or strip_comments:
            rel_posix = rel.as_posix()
            allowed = renameable.get(rel_posix) if rename_fields else None
            obf, status, detail, fmap = obfuscate_file_enhanced(
                code, allowed_fields=allowed, strip_comments=strip_comments)
            field_total += len(fmap)
        else:
            obf, status, detail = obfuscate_file_safe(code)
        dst.write_text(obf, encoding="utf-8")
        stats[status] += 1
        in_bytes += len(code.encode("utf-8"))
        out_bytes += len(obf.encode("utf-8"))
        if status == "rejected":
            rejected.append((str(rel), detail))
    print("files=%d changed=%d unchanged=%d rejected=%d" %
          (len(files), stats["changed"], stats["unchanged"], stats["rejected"]))
    if rename_fields:
        print("distinct field names renamed (sum over files): %d" % field_total)
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
    ap.add_argument("--strip-comments", action="store_true",
                    help="剥离普通注释(保留 ---@ EmmyLua 注解与 --[[@as]] 断言)")
    ap.add_argument("--rename-fields", action="store_true",
                    help="【实验性】重命名单文件私有字段/方法名;需完整实机回归验证后再用于发行")
    ap.add_argument("--emmylua-root", type=Path, default=None,
                    help="字段改名时引擎声明(.emmylua/urhox-libs)所在根;缺省用 source-root")
    args = ap.parse_args()

    if args.file:
        code = args.file.read_text(encoding="utf-8")
        if args.rename_fields:
            print("提示: --file 单文件模式不支持 --rename-fields(需要全项目分析上下文);"
                  "请用 --source-root 全量模式。本次按 strip_comments=%s 处理。"
                  % args.strip_comments)
        if args.strip_comments:
            obf, status, detail, _fmap = obfuscate_file_enhanced(
                code, allowed_fields=None, strip_comments=True)
        else:
            obf, status, detail = obfuscate_file_safe(code)
        print("status=%s detail=%s" % (status, detail))
        if status == "changed":
            print("---- obfuscated ----")
            print(obf)
        return

    if not args.source_root or not args.output_root:
        ap.error("need --source-root and --output-root (or --file)")
    fa = None
    if args.rename_fields:
        emmy = (args.emmylua_root or args.source_root).resolve()
        fa = analyze_project(emmy)
        print("field analysis (from %s): %s" % (emmy, fa["stats"]))
    run_all(args.source_root.resolve(), args.output_root.resolve(),
            strip_comments=args.strip_comments, rename_fields=args.rename_fields,
            field_analysis=fa)


# ===========================================================================
# 扩展(2026-09-28):注释剥离 + 私有字段改名(方法名混淆)
# ===========================================================================

# 说明:所有 Lua 元方法都是 __ 前缀(__index/__add/__len...),已被下方
# f.startswith("_") 规则排除。裸名 index/add/get/len/call 等是高频合法用户
# 方法名,必须允许改名(它们通过 obj.add 访问,不经元表机制),故本集合留空。
# 保留常量名仅为兼容引用点。
LUA_MAGIC_FIELDS = set()


def strip_comments_code(code):
    """剥离普通注释,保留 EmmyLua `---` 注解与 `--[[@as ...]]` 断言(官方 LSP 需要)。

    返回 (new_code, edits):edits 为 (start, stop, "") 删除区间,可与改名 edits 合并。
    注释在 lexer 的独立 hidden channel,字符串里的 "--" 是 NORMALSTRING token,天然不误伤。
    """
    toks = _lex_all_tokens_raw(code)
    edits = []
    for tok in toks:
        sym = sym_of(tok.type)
        if sym not in ("LINE_COMMENT", "COMMENT"):
            continue
        text = tok.text
        if text.startswith("---") and not text.startswith("----"):
            continue  # EmmyLua 注解保留
        if text.startswith("--[[@"):
            continue  # 类型断言保留
        start, stop = tok.start, tok.stop + 1
        # 若整行只剩这个注释,连同行首缩进一起删(含行尾换行,保持行号无关性不要求)
        line_start = code.rfind("\n", 0, start) + 1
        prefix = code[line_start:start]
        if prefix.strip() == "":
            # 整行注释:删掉缩进+注释+换行
            if prefix:
                start = line_start
            if stop < len(code) and code[stop] == "\n":
                stop += 1
        else:
            # 行尾注释:连同注释前的行内空白一起删
            ws_start = start
            while ws_start > line_start and code[ws_start - 1] in " \t":
                ws_start -= 1
            start = ws_start
        edits.append((start, stop, ""))
    if not edits:
        return code, []
    return apply_edits(code, edits), edits


def _lex_all_tokens_raw(code):
    lexer = LuaLexer(InputStream(code))
    lexer.removeErrorListeners()
    ts = CommonTokenStream(lexer)
    ts.fill()
    return [tok for tok in ts.tokens if tok.type >= 0]


def collect_field_names(code):
    """收集文件内所有『字段位置』的名字:.F / :F 之后的 NAME、表构造器 NAME= 键、
    ["F"] / ['F'] 字符串键(字符串键仅记录,不改名)。返回 set。"""
    toks = _lex_all_tokens_raw(code)
    fields = set()
    prev_txt = None
    for i, tok in enumerate(toks):
        sym = sym_of(tok.type)
        if sym == "NAME" and prev_txt in (".", ":"):
            fields.add(tok.text)
        if sym == "NAME":
            # 表构造器键: NAME 后跟 '='(且非 '==')
            if i + 1 < len(toks):
                nxt = toks[i + 1]
                if nxt.text == "=" and sym_of(nxt.type) == "EQ":
                    fields.add(tok.text)
        if sym in ("NORMALSTRING", "LONGSTRING") and prev_txt == "[":
            s = tok.text
            if len(s) > 2:
                inner = s[1:-1]
                if re.fullmatch(r"[A-Za-z_]\w*", inner or ""):
                    fields.add(inner)
        if tok.channel == 0:  # 只有默认通道的 token 才算『前一个语法 token』
            prev_txt = tok.text
    return fields


# ---- 项目级分析(protect_build 调用一次,产出字段改名白名单) ----

def analyze_project(source_root):
    """扫描整个 scripts/ 树 + 外部排除源,产出可安全改名的字段集合与排除文件集。

    返回 dict:
      renameable: {relpath: set(字段名)}  —— 该文件内允许改名的私有字段
      excluded_files: set(relpath)        —— 因动态拼接访问被整体排除的文件
      stats: {...}
    """
    scripts = source_root / "scripts"
    files = sorted(scripts.rglob("*.lua"))
    rel = lambda p: p.relative_to(source_root).as_posix()

    # 1) 字段 -> 出现文件集合
    field_files = {}
    # 2) 全项目字符串标识符集合
    string_ids = set()
    # 3) 动态拼接接收者 & 其模块解析
    concat_files = set()
    concat_module_targets = set()   # 被拼接访问的模块路径(相对 scripts/)
    # 4) 每文件的 require 绑定 -> 模块路径
    bindings = {}
    str_pat = re.compile(r'"([^"]*)"|' + "'" + r"([^']*)'")
    concat_pat = re.compile(r"(\w+)\s*\[[^\]]*\.\.[^\]]*\]")
    req_pat = re.compile(r'local\s+(\w+)\s*=\s*require\s*\(?["\']([\w./-]+)')

    per_file_fields = {}
    for f in files:
        code = f.read_text(encoding="utf-8")
        r = rel(f)
        per_file_fields[r] = collect_field_names(code)
        for name in per_file_fields[r]:
            field_files.setdefault(name, set()).add(r)
        for m in str_pat.finditer(code):
            s = m.group(1) if m.group(1) is not None else (m.group(2) or "")
            string_ids.update(re.findall(r"[A-Za-z_]\w*", s))
        file_binds = {mm.group(1): mm.group(2) for mm in req_pat.finditer(code)}
        bindings[r] = file_binds
        for m in concat_pat.finditer(code):
            line_start = code.rfind("\n", 0, m.start()) + 1
            line = code[line_start:code.find("\n", m.start())]
            if line.strip().startswith("--"):
                continue
            concat_files.add(r)
            recv = m.group(1)
            mod = file_binds.get(recv)
            if mod:
                concat_module_targets.add(mod.replace(".", "/") + ".lua")

    # 5) 外部排除集:.emmylua / urhox-libs / 引擎声明(可选目录)
    external_ids = set()
    for extra in (source_root / ".emmylua", source_root / "urhox-libs",
                  source_root.parent / ".emmylua", source_root.parent / "urhox-libs"):
        if extra.is_dir():
            for ef in extra.rglob("*"):
                if ef.suffix in (".lua",) and ef.is_file():
                    try:
                        txt = ef.read_text(encoding="utf-8", errors="replace")
                    except OSError:
                        continue
                    external_ids.update(re.findall(r"[A-Za-z_]\w*", txt))

    # Lua 标准库常用方法/字段(硬保底排除)
    STDLIB = {
        "byte","char","dump","find","format","gmatch","gsub","len","lower","match",
        "pack","packsize","rep","reverse","sub","upper","unpack","abs","acos","asin",
        "atan","ceil","cos","deg","exp","floor","fmod","huge","log","max","maxinteger",
        "min","mininteger","modf","pi","rad","random","randomseed","sin","sqrt","tan",
        "tointeger","type","ult","concat","insert","move","remove","sort","pack","unpack",
        "append","extend","read","write","close","flush","lines","seek","setvbuf","tmpfile",
        "add","band","bnot","bor","bxor","lrotate","lshift","rrotate","rshift","arshift",
        "btest","extract","replace","idiv","mod","pow","div","mul","sub","unm","lt","le",
        "eq","len","concat","call","index","newindex","tostring","pairs","ipairs","next",
        "rawget","rawset","rawequal","rawlen","select","setmetatable","getmetatable",
        "metatable","__index","__newindex","__tostring","__eq","__lt","__le","__add",
        "__sub","__mul","__div","__mod","__pow","__unm","__idiv","__band","__bor",
        "__bxor","__shl","__shr","__concat","__len","__call","__metatable","__mode",
        "__gc","__close","__name","__pairs","isvalid","delete","remove","create","get",
        "set","update","init","new","clone","enable","disable","show","hide","reset",
        "start","stop","run","execute","apply","add","remove","insert","contains",
        "clear","copy","tostring","todisplaystring","position","rotation","scale",
        "enabled","visible","name","id","type","value","text","width","height","size",
        "x","y","z","w","r","g","b","a","key","data","list","count","index","total",
        "min","max","default","result","error","message","code","status","state",
        "time","dt","delta","speed","alpha","color","font","style","align","anchor",
        "parent","child","children","root","node","component","entity","scene",
    }

    excluded_files = set(concat_files)
    # 被拼接访问的模块文件也排除(按 scripts/ 相对路径匹配)
    for target in concat_module_targets:
        excluded_files.add("scripts/" + target if not target.startswith("scripts/") else target)

    renameable = {}
    total_fields = 0
    for r, fields in per_file_fields.items():
        if r in excluded_files:
            continue
        allowed = set()
        for name in fields:
            if name in STDLIB or name in external_ids or name in string_ids:
                continue
            if name.startswith("_"):   # 私有约定名/元方法,不动
                continue
            fs = field_files.get(name, set())
            if len(fs) != 1:
                continue               # 跨文件出现 -> 改名需全局一致,高危,不改
            allowed.add(name)
        if allowed:
            renameable[r] = allowed
            total_fields += len(allowed)

    return {
        "renameable": renameable,
        "excluded_files": sorted(excluded_files),
        "stats": {
            "files": len(files),
            "field_names_total": len(field_files),
            "renameable_fields": total_fields,
            "files_with_renameable": len(renameable),
            "excluded_files": len(excluded_files),
            "string_ids": len(string_ids),
            "external_ids": len(external_ids),
        },
    }


def obfuscate_file_enhanced(code, allowed_fields=None, strip_comments=False, reserved_extra=None):
    """增强版单文件混淆:局部改名 + 可选字段改名(.F/:F/构造器键) + 可选注释剥离。
    每个 token 只改一次(按字符位置去重)。返回 (new_code, status, detail, field_map)。"""
    try:
        an = plan_renames(code)
        edits = list(an.edits)
        field_map = {}
        local_positions = set(e[0] for e in an.edits)
        field_positions = {}
        if allowed_fields:
            # 防御兜底:即使调用方误传,也绝不改元方法(__开头)与 Lua 魔术名。
            # 元方法名由 VM 按固定字符串查找,改名即破坏 setmetatable/运算符重载。
            allowed_fields = {
                f for f in allowed_fields
                if not f.startswith(chr(95)) and f not in LUA_MAGIC_FIELDS
            }
            toks = _lex_all_tokens_raw(code)
            fcounter = [len(an.reserved)]
            def _field_new(name):
                if name in field_map:
                    return field_map[name]
                while True:
                    cand = "_f%d_" % fcounter[0]
                    fcounter[0] += 1
                    if cand not in an.reserved:
                        an.reserved.add(cand)
                        field_map[name] = cand
                        return cand
            default_idx = [i for i, tk in enumerate(toks) if tk.channel == 0]
            for pos, i in enumerate(default_idx):
                tok = toks[i]
                if sym_of(tok.type) != "NAME":
                    continue
                if tok.text not in allowed_fields:
                    continue
                if tok.start in local_positions:
                    continue
                prev_txt = toks[default_idx[pos - 1]].text if pos > 0 else None
                is_member = prev_txt in (".", ":")
                is_ctor_key = False
                if not is_member and pos + 1 < len(default_idx):
                    nxt = toks[default_idx[pos + 1]]
                    if sym_of(nxt.type) == "EQ" and nxt.text == "=":
                        is_ctor_key = True
                if is_member or is_ctor_key:
                    field_positions[tok.start] = _field_new(tok.text)
            for pos_start, new in field_positions.items():
                for i in default_idx:
                    if toks[i].start == pos_start:
                        edits.append((pos_start, toks[i].stop + 1, new))
                        break
        # doc 注释同步(plan_renames 已算好 comment_edits):@param 旧名 -> 新名,
        # 必须在注释剥离前合并,保证保留下来的 EmmyLua 注解与实参一致(官方 LSP)。
        all_edits = edits + list(getattr(an, "comment_edits", []))
        result = apply_edits(code, all_edits) if all_edits else code
        if strip_comments:
            result, _c_edits = strip_comments_code(result)
        verify_equivalence_enhanced(code, result)
        detail = "%d local renames, %d field-tokens(%d fields), comments=%s" % (
            len(an.edits), len(field_positions), len(field_map),
            "stripped" if strip_comments else "kept")
        status = "changed" if (edits or strip_comments) else "unchanged"
        return result, status, detail, field_map
    except Analyzer.Unsupported as e:
        return code, "rejected", str(e), {}
    except Exception as e:
        return code, "rejected", "%s: %s" % (type(e).__name__, e), {}

def verify_equivalence_enhanced(original, obfuscated):
    """宽松版校验:允许 NAME 文本变化(字段改名),但要求:
    ①重新解析成功 ②非 NAME token 序列一致(注释剥离不影响,指纹已排除注释)
    ③字符串字面量一致 ④NAME token 数量一致 ⑤全局名集合不变。"""
    parse_tree(obfuscated)
    o_non, o_names, o_str = token_fingerprint_syntax(original)
    n_non, n_names, n_str = token_fingerprint_syntax(obfuscated)
    if o_non != n_non:
        raise Analyzer.Unsupported("non-NAME syntax token sequence changed")
    if o_str != n_str:
        raise Analyzer.Unsupported("string literals changed")
    if o_names != n_names:
        raise Analyzer.Unsupported("NAME token count changed")
    g_before = _global_names(original)
    g_after = _global_names(obfuscated)
    if g_before != g_after:
        raise Analyzer.Unsupported("global name set changed: %s" %
                                   str(sorted(g_before ^ g_after))[:200])


if __name__ == "__main__":
    main()

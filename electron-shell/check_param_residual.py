# -*- coding: utf-8 -*-
"""全量残留校验：混淆产物中，紧邻函数声明上方的 @param 名必须都在该函数实参表里。
0 残留 = doc 同步修复成功（LSP param 校验可通过）。"""
import glob, os, re, sys
sys.path.insert(0, "electron-shell")
from antlr4 import InputStream, CommonTokenStream, TerminalNode, ParserRuleContext
from luaparser.ast import LuaLexer, LuaParser
from lua_obfuscator import kids, ctx_name, is_name, sym_of

OUT = os.path.expanduser(sys.argv[1] if len(sys.argv)>1 else "~/obf-final")

def lex_tokens(code):
    lx = LuaLexer(InputStream(code)); lx.removeErrorListeners()
    ts = CommonTokenStream(lx); ts.fill()
    return [t for t in ts.tokens if t.type >= 0]

def check_file(path):
    code = open(path, encoding="utf-8").read()
    lx = LuaLexer(InputStream(code)); lx.removeErrorListeners()
    ts = CommonTokenStream(lx); psr = LuaParser(ts); psr.removeErrorListeners()
    tree = psr.start_()
    if psr.getNumberOfSyntaxErrors():
        return ("parse_fail", [])
    toks = lex_tokens(code)
    problems = []
    # 找每个 FuncbodyContext（其父为命名函数声明），拿到声明锚点与实参名集
    def walk(n):
        if isinstance(n, ParserRuleContext):
            if ctx_name(n) == "FuncbodyContext":
                parent = n  # 需要父
            for c in kids(n): walk(c)
    # 用 pm 找父
    pm = {}
    stack = [(tree, None)]
    while stack:
        node, par = stack.pop()
        pm[id(node)] = par
        if isinstance(node, ParserRuleContext):
            for c in kids(node): stack.append((c, node))
    def walk2(n):
        if isinstance(n, ParserRuleContext):
            if ctx_name(n) == "FuncbodyContext":
                par = pm.get(id(n)); pcn = ctx_name(par) if par is not None else ""
                if pcn in ("Stat_localfunctionContext", "Stat_functionContext"):
                    # 实参名集
                    params = set()
                    for c in kids(n):
                        if ctx_name(c) == "ParlistContext":
                            for nl in kids(c):
                                if ctx_name(nl) == "NamelistContext":
                                    for t in kids(nl):
                                        if is_name(t): params.add(t.symbol.text)
                    anchor = par.start.start if getattr(par, "start", None) else None
                    if anchor is None: return
                    # 紧邻上方的 doc 注释块
                    idx = next((i for i,t in enumerate(toks) if t.start >= anchor), None)
                    if idx is None: return
                    comments = []
                    i = idx-1
                    while i >= 0:
                        t = toks[i]; sym = sym_of(t.type)
                        if sym in ("WS","NL"): i -= 1; continue
                        if sym in ("LINE_COMMENT","COMMENT"): comments.append(t); i -= 1; continue
                        break
                    for ct in comments:
                        for m in re.finditer(r"@param\s+([A-Za-z_]\w*)", ct.text):
                            pn = m.group(1)
                            if pn not in params:
                                problems.append((path, pn, sorted(params)))
            for c in kids(n): walk2(c)
    walk2(tree)
    return ("ok", problems)

total = parse_fail = 0
all_problems = []
for path in sorted(glob.glob(os.path.join(OUT, "scripts/**/*.lua"), recursive=True)):
    total += 1
    st, probs = check_file(path)
    if st == "parse_fail":
        parse_fail += 1
    all_problems.extend(probs)
print("checked=%d parse_fail=%d residual_param_mismatch=%d" % (total, parse_fail, len(all_problems)))
for p in all_problems[:25]:
    print("  RESIDUAL", os.path.relpath(p[0], OUT), "param=%r not in %r" % (p[1], p[2]))

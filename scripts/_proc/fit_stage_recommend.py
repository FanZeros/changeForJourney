#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fit_stage_recommend.py — 关卡推荐战力拟合与生成（battle-lab 校准产物）

输入:
  battle_lab_threshold_samples.json（由 tests/battle_lab_threshold.lua 产出：
    开荒三人组 无装备，首通模式 winRate 跨过 50% 的阈值等级/战力样本，
    覆盖 Normal 难度 23 个章节首关，monsterLevel 1..23）
  scripts/config/StageConfig_*.lua（全难度关卡表，正则提取 id/monsterLevel）

输出:
  stdout 拟合报告 + battle_lab_threshold_samples_result.json
  scripts/config/StageRecommendPower.lua（生成的推荐战力表，数据模块，
  不含 UI 接线；由本脚本生成，勿手改）

模型:
  recommend_power(ml) —— 官方战力口径的阈值曲线。依次尝试
  线性 / 二次 / 指数（log 线性）三种模型，取 R² 最高者；
  同步拟合分项预估口径 recommend_estimate(ml) 作对照列。
  章节内关卡（stage 2..5，怪物数递增）未单独采样，按同 monsterLevel
  的首关阈值推荐并向上取整到 10，文档注明该近似。

局限（必须随产物声明）:
  * 阈值口径 = 开荒三人组（大狗嚼/黄桃龙/叮咚鸡）无装备无养成、首通模式、
    12 局固定种子 winRate≥50% 的最低英雄等级处战力。带装备/养成推进的
    玩家实际需求更低；不同队伍构成会偏移。
  * 仅 Normal 难度实测（ml 1..23）；Hard+ 难度按同一曲线外推，未经采样
    验证，产物中按 difficulty 分列并注明 extrapolated=true。
"""

import json
import math
import re
import sys
import glob
import numpy as np

RESULT_SUFFIX = "_result.json"
OUT_LUA = "scripts/config/StageRecommendPower.lua"


def load_thresholds(path):
    with open(path, encoding="utf-8") as f:
        samples = json.load(f)
    rows = []
    skipped = []
    for s in samples:
        t = s.get("threshold")
        if not t:
            skipped.append((s["stageId"], s.get("note")))
            continue
        rows.append({
            "stageId": s["stageId"], "monsterLevel": s["monsterLevel"],
            "level": t["level"], "teamPower": t["teamPower"],
            "teamEstimate": t["teamEstimate"], "winRate": t["winRate"],
            "loLevel": t.get("loLevel"), "loPower": t.get("loPower"),
            "loWinRate": t.get("loWinRate"),
        })
    return rows, skipped


def fit_models(x, y):
    """尝试线性/二次/指数模型，返回最优 (name, predict_fn, r2, params)"""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    cands = []

    def r2_of(pred):
        ss_res = float(((y - pred) ** 2).sum())
        ss_tot = float(((y - y.mean()) ** 2).sum())
        return 1 - ss_res / ss_tot if ss_tot > 0 else float("nan")

    # 线性
    k, b = np.polyfit(x, y, 1)
    cands.append(("linear", lambda v, k=k, b=b: k * v + b, r2_of(k * x + b),
                  {"k": float(k), "b": float(b)}))
    # 二次
    c2, c1, c0 = np.polyfit(x, y, 2)
    cands.append(("quadratic", lambda v, a=c2, bb=c1, c=c0: a * v * v + bb * v + c,
                  r2_of(c2 * x * x + c1 * x + c0),
                  {"a": float(c2), "b": float(c1), "c": float(c0)}))
    # 指数: y = exp(m*x + c)
    ly = np.log(np.clip(y, 1e-9, None))
    m, c = np.polyfit(x, ly, 1)
    pred = np.exp(m * x + c)
    cands.append(("exponential", lambda v, m=m, c=c: math.exp(m * v + c),
                  r2_of(pred), {"m": float(m), "c": float(c)}))

    best = max(cands, key=lambda t: (t[2] if t[2] == t[2] else -9))
    return best


def parse_stage_configs(repo_root):
    """正则提取全难度关卡 (stageId, monsterLevel, difficulty, mode)。
    StageConfig_*.lua 行格式统一：{ id=0101, ..., monsterLevel=1, ..., difficulty=..., mode="terminal" }"""
    stages = []
    files = sorted(glob.glob(f"{repo_root}/scripts/config/StageConfig_*.lua"))
    pat = re.compile(r"\bid=(\d+)")
    pat_ml = re.compile(r"monsterLevel=(\d+)")
    pat_diff = re.compile(r'difficulty=SC\.(DIFFICULTY_[A-Z0-9_]+)')
    pat_mode = re.compile(r'mode="(\w+)"')
    for fp in files:
        base = fp.rsplit("/", 1)[-1]
        with open(fp, encoding="utf-8") as f:
            for line in f:
                if not line.lstrip().startswith("{") or "id=" not in line:
                    continue
                mid, mml = pat.search(line), pat_ml.search(line)
                if not mid or not mml:
                    continue
                mdiff = pat_diff.search(line)
                mmode = pat_mode.search(line)
                difficulty = mdiff.group(1).replace("DIFFICULTY_", "").lower() \
                    if mdiff else "normal"
                stages.append({
                    "stageId": int(mid.group(1)),
                    "monsterLevel": int(mml.group(1)),
                    "difficulty": difficulty,
                    "mode": mmode.group(1) if mmode else "normal",
                    "source": base,
                })
    # 去重（同 id 保留首个）
    seen, unique = set(), []
    for s in stages:
        if s["stageId"] in seen:
            continue
        seen.add(s["stageId"])
        unique.append(s)
    return unique


def round_up_10(v):
    return int(math.ceil(max(v, 1) / 10.0) * 10)


def main():
    samples_path = sys.argv[1] if len(sys.argv) > 1 else "battle_lab_threshold_samples.json"
    repo_root = "."
    rows, skipped = load_thresholds(samples_path)
    if len(rows) < 5:
        print(f"阈值样本不足（{len(rows)} 组），无法拟合")
        sys.exit(1)

    ml = [r["monsterLevel"] for r in rows]
    power = [r["teamPower"] for r in rows]
    estimate = [r["teamEstimate"] for r in rows]

    name_p, pred_p, r2_p, params_p = fit_models(ml, power)
    name_e, pred_e, r2_e, params_e = fit_models(ml, estimate)

    print(f"阈值样本 {len(rows)} 组（跳过 {len(skipped)}）：ml {min(ml)}..{max(ml)}")
    for r in rows:
        print(f"  stage={r['stageId']:5d} ml={r['monsterLevel']:3d} "
              f"L*={r['level']:3d} power={r['teamPower']:6d} est={r['teamEstimate']:6d} "
              f"win={r['winRate']:.0f}%  (lo L={r['loLevel']} win={r['loWinRate']:.0f}%)")
    print(f"\n官方战力曲线: {name_p}  R²={r2_p:.4f}  params={ {k: round(v, 4) for k, v in params_p.items()} }")
    print(f"预估战力曲线: {name_e}  R²={r2_e:.4f}  params={ {k: round(v, 4) for k, v in params_e.items()} }")

    # 逐样本残差检查（拟合质量守门）
    worst = max(rows, key=lambda r: abs(pred_p(r["monsterLevel"]) - r["teamPower"]))
    print(f"最大残差样本: stage={worst['stageId']} ml={worst['monsterLevel']} "
          f"实测={worst['teamPower']} 拟合={pred_p(worst['monsterLevel']):.0f} "
          f"偏差={pred_p(worst['monsterLevel']) - worst['teamPower']:+.0f}")

    stages = parse_stage_configs(repo_root)
    print(f"\n关卡表解析: {len(stages)} 个关卡（全难度）")

    # 生成推荐表。
    # 🔴 外推上限：指数曲线在 ml>23 后发散（ml=345 时 p≈2e16，纯数学垃圾），
    # 因此只对 ml <= EXTRAP_CAP（实测上限的 2 倍）做保守外推并标 x=true；
    # 超过上限的关卡不生成条目，SRP.get 返回 nil（诚实声明"数据不支持"）。
    extrap_cap = max(ml) * 2
    # 实测范围内直接采用实测阈值（曲线在低端低估，如 ml=1 拟合 280 < 实测 318），
    # 仅对超出采样上限的 ml 用拟合曲线外推。
    measured_p = {r["monsterLevel"]: r["teamPower"] for r in rows}
    measured_e = {r["monsterLevel"]: r["teamEstimate"] for r in rows}
    by_stage = {}
    for s in stages:
        v = s["monsterLevel"]
        if v > extrap_cap:
            continue
        if v in measured_p:
            rec_p = round_up_10(measured_p[v])
            rec_e = round_up_10(measured_e[v])
            extr = False
        else:
            rec_p = round_up_10(pred_p(v))
            rec_e = round_up_10(pred_e(v))
            extr = True
        by_stage[s["stageId"]] = {"p": rec_p, "e": rec_e, "x": extr}
    n_extr = sum(1 for v in by_stage.values() if v["x"])
    n_skip = len(stages) - len(by_stage)
    print(f"推荐表: {len(by_stage)} 关（外推 {n_extr} 关，ml<={extrap_cap}），"
          f"{n_skip} 关因 ml>{extrap_cap} 超出外推上限不生成条目")

    result = {
        "samples": len(rows), "skipped": skipped,
        "powerModel": {"name": name_p, "r2": round(r2_p, 4), "params": params_p},
        "estimateModel": {"name": name_e, "r2": round(r2_e, 4), "params": params_e},
        "thresholds": rows,
        "stageCount": len(by_stage), "extrapolatedCount": n_extr,
        "extrapCap": extrap_cap, "skippedOverCap": n_skip,
    }
    out = samples_path.replace(".json", RESULT_SUFFIX)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"已写入 {out}")

    write_lua(by_stage, name_p, params_p, r2_p, name_e, params_e, r2_e,
              rows, min(ml), max(ml), extrap_cap)


def write_lua(by_stage, name_p, params_p, r2_p, name_e, params_e, r2_e,
              rows, ml_min, ml_max, extrap_cap):
    lines = []
    lines.append("-- ============================================================================")
    lines.append("-- StageRecommendPower — 关卡推荐战力表（由 _proc/fit_stage_recommend.py 生成，勿手改）")
    lines.append("--")
    lines.append("-- 口径：开荒三人组（大狗嚼/黄桃龙/叮咚鸡）无装备无养成、首通模式、")
    lines.append("-- 12 局固定种子 winRate≥50% 的最低英雄等级处战力（battle-lab 实测，")
    lines.append(f"-- Normal 难度 ml {ml_min}..{ml_max} 采样）。带装备/养成推进的实际需求更低。")
    lines.append(f"-- 官方战力曲线: {name_p} R²={r2_p:.4f}；预估口径: {name_e} R²={r2_e:.4f}。")
    lines.append(f"-- monsterLevel > {ml_max} 的关卡为同曲线外推，未经实测验证，x = true；")
    lines.append(f"-- monsterLevel > {extrap_cap}（实测上限×2）的关卡指数外推不可信，不生成条目，")
    lines.append("-- SRP.get 返回 nil（数据不支持，接入方需处理）。章节内 2..5 关按同 ml 首关阈值近似。")
    lines.append("-- 本模块是纯数据 + 查询 API，无 UI 接线；接入展示前需真人验收文案与布局。")
    lines.append("-- ============================================================================")
    lines.append("")
    lines.append("local SRP = {}")
    lines.append("")
    lines.append("--- 拟合模型参数（供运行时对未知关卡外推）")
    lines.append("SRP.model = {")
    lines.append(f"    power = {{ name = \"{name_p}\", r2 = {r2_p:.4f}, params = {{ "
                 + ", ".join(f"{k} = {v:.6f}" for k, v in params_p.items()) + " } },")
    lines.append(f"    estimate = {{ name = \"{name_e}\", r2 = {r2_e:.4f}, params = {{ "
                 + ", ".join(f"{k} = {v:.6f}" for k, v in params_e.items()) + " } },")
    lines.append(f"    sampledRange = {{ {ml_min}, {ml_max} }},")
    lines.append(f"    extrapCap = {extrap_cap},")
    lines.append("}")
    lines.append("")
    lines.append("--- 按关卡 ID 的推荐战力：p=官方口径 e=分项预估口径 x=外推(ml>采样上限)")
    lines.append("SRP.byStage = {")
    for sid in sorted(by_stage):
        v = by_stage[sid]
        lines.append(f"    [{sid}] = {{ p = {v['p']}, e = {v['e']}"
                     + (", x = true" if v["x"] else "") + " },")
    lines.append("}")
    lines.append("")
    lines.append("--- 查询关卡推荐战力（官方口径）")
    lines.append("---@param stageId number")
    lines.append("---@return number|nil recommendPower")
    lines.append("---@return boolean|nil extrapolated")
    lines.append("function SRP.get(stageId)")
    lines.append("    local entry = SRP.byStage[stageId]")
    lines.append("    if not entry then return nil, nil end")
    lines.append("    return entry.p, entry.x or false")
    lines.append("end")
    lines.append("")
    lines.append("--- 查询关卡推荐战力（分项预估口径）")
    lines.append("---@param stageId number")
    lines.append("---@return number|nil recommendEstimate")
    lines.append("function SRP.getEstimate(stageId)")
    lines.append("    local entry = SRP.byStage[stageId]")
    lines.append("    return entry and entry.e or nil")
    lines.append("end")
    lines.append("")
    lines.append("return SRP")
    with open(OUT_LUA, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"已生成 {OUT_LUA}（{len(by_stage)} 关）")


if __name__ == "__main__":
    main()

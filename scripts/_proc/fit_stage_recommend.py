#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fit_stage_recommend.py — 关卡推荐战力拟合与生成（battle-lab 校准产物）

输入:
  battle_lab_threshold_samples.json（由 tests/battle_lab_threshold.lua 产出：
    开荒三人组 无装备，首通模式 winRate 跨过 50% 的阈值等级/战力样本，
    覆盖 Normal + Hard 难度 46 个章节首关，monsterLevel 1..46）
  scripts/config/StageConfig_*.lua（全难度关卡表，正则提取 id/monsterLevel）

输出:
  stdout 拟合报告 + battle_lab_threshold_samples_result.json
  scripts/config/StageRecommendPower.lua（生成的推荐战力表，数据模块，
  不含 UI 接线；由本脚本生成，勿手改）

模型:
  recommend_power(ml) —— 官方战力口径的阈值曲线。依次尝试
  线性 / 二次 / 指数（log 线性）三种模型，取 R² 最高者；
  同步拟合分项预估口径 recommend_estimate(ml) 作对照列。

后处理（v2.62，玩家可读性修正）:
  1) PAVA 保序回归：实测阈值受章节怪物构成影响存在真实回落
     （ml12→13、ml16→17、ml20→21），直接展示会出现"下一章推荐更低"
     的倒挂。对首关阈值序列做等权 PAVA（相邻违反者合并取均值）。
  2) 最小章间梯度：PAVA 相等段按 ×1.02 向上取整到 10 强制严格递增，
     保证"越往后推荐战力越高"的玩家直觉。
  3) 章内梯度：stage 2..5 不再与首关同值，改为本章首关与下一章首关
     之间按权重 0.2/0.4/0.6/0.8 插值，四舍五入到 5 并夹取非降、
     不超过下一章首关（末章用外推曲线 ml+1 值作虚拟下一章）。

局限（必须随产物声明）:
  * 阈值口径 = 开荒三人组（大狗嚼/黄桃龙/叮咚鸡）无装备无养成、首通模式、
    12 局固定种子 winRate≥50% 的最低英雄等级处战力。带装备/养成推进的
    玩家实际需求更低；不同队伍构成会偏移。
  * Normal + Hard 难度实测（ml 1..46，v2.63 扩展）；Nightmare+ 难度按同一
    曲线外推到 extrapCap=92（采样上限×2）并标 x=true，超上限不生成条目。
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
    """正则提取全难度关卡 (stageId, stage, monsterLevel, difficulty, mode)。
    StageConfig_*.lua 行格式统一：{ id=0101, ..., stage=1, monsterLevel=1, ..., difficulty=..., mode="terminal" }"""
    stages = []
    files = sorted(glob.glob(f"{repo_root}/scripts/config/StageConfig_*.lua"))
    pat = re.compile(r"\bid=(\d+)")
    pat_stage = re.compile(r"\bstage=(\d+)")
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
                mst = pat_stage.search(line)
                mdiff = pat_diff.search(line)
                mmode = pat_mode.search(line)
                difficulty = mdiff.group(1).replace("DIFFICULTY_", "").lower() \
                    if mdiff else "normal"
                stages.append({
                    "stageId": int(mid.group(1)),
                    "stage": int(mst.group(1)) if mst else ((int(mid.group(1)) % 100) or 5),
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


def pava(values):
    """等权 Pool Adjacent Violators Algorithm：返回保序（非降）序列。
    相邻违反者 (y_i > y_{i+1}) 合并为块，块值取块内均值。"""
    blocks = [[float(v), 1] for v in values]  # [sum, count]
    merged = []
    for b in blocks:
        merged.append(b)
        while len(merged) > 1:
            last, prev = merged[-1], merged[-2]
            if prev[0] / prev[1] > last[0] / last[1]:
                merged.pop()
                merged.pop()
                merged.append([prev[0] + last[0], prev[1] + last[1]])
            else:
                break
    out = []
    for s, c in merged:
        out.extend([s / c] * c)
    return out


def enforce_min_growth(seq, factor=1.02):
    """PAVA 相等段强制最小增长：后项至少 = ceil10(前项*factor)。
    保证严格递增且幅度可感知（2% 起步、至少 +10）。"""
    out = [round_up_10(seq[0])]
    for v in seq[1:]:
        base = round_up_10(v)
        floor = round_up_10(out[-1] * factor)
        out.append(max(base, floor))
    return out


def interp_stage_values(chapter_first, next_chapter_first):
    """章内 5 关梯度：首关 = 本章阈值；2..5 关向下一章首关插值
    （权重 0.2/0.4/0.6/0.8），四舍五入到 5，非降且 < 下一章首关。"""
    vals = [chapter_first]
    span = next_chapter_first - chapter_first
    for w in (0.2, 0.4, 0.6, 0.8):
        v = chapter_first + span * w
        v = int(round(v / 5.0) * 5)
        v = max(v, vals[-1])                       # 章内非降
        v = min(v, next_chapter_first - 5)          # 不超过下一章首关
        v = max(v, vals[-1])
        vals.append(v)
    return vals


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

    # ---- v2.62 后处理 1/2：首关阈值 PAVA 保序 + 最小章间梯度 ----
    # 实测阈值存在怪物构成导致的真实回落（ml13<ml12、ml17<ml16、ml21<ml20），
    # 直接展示会让玩家看到"下一章推荐更低"的倒挂。保序回归压平违反段，
    # 再对相等段施加 ×1.02 最小增长，保证章间严格递增。
    rows_sorted = sorted(rows, key=lambda r: r["monsterLevel"])
    raw_p = [r["teamPower"] for r in rows_sorted]
    raw_e = [r["teamEstimate"] for r in rows_sorted]
    iso_p = pava(raw_p)
    iso_e = pava(raw_e)
    final_p = enforce_min_growth(iso_p)
    final_e = enforce_min_growth(iso_e)
    n_pooled = sum(1 for a, b in zip(raw_p, iso_p) if abs(a - b) > 1e-9)
    n_lifted = sum(1 for a, b in zip(iso_p, final_p) if b > round_up_10(a))
    print(f"保序修正: {n_pooled} 个样本被 PAVA 合并，{n_lifted} 个样本被最小梯度抬升")
    for r, a, b in zip(rows_sorted, raw_p, final_p):
        if abs(a - b) > 1e-9:
            print(f"  stage={r['stageId']:5d} ml={r['monsterLevel']:3d} 实测={a} -> 展示={b}")
    measured_p = {r["monsterLevel"]: v for r, v in zip(rows_sorted, final_p)}
    measured_e = {r["monsterLevel"]: v for r, v in zip(rows_sorted, final_e)}

    # 生成推荐表。
    # 🔴 外推上限：曲线在高 ml 段发散，因此只对 ml <= EXTRAP_CAP（实测上限的
    # 2 倍）做保守外推并标 x=true；超过上限的关卡不生成条目，SRP.get 返回 nil。
    extrap_cap = max(ml) * 2

    # 构建全 ml 段（1..extrap_cap）的"章节首关"推荐序列，保证严格单调：
    #   * 实测段（ml ≤ 采样上限）：用 PAVA + 最小梯度修正后的展示值；
    #   * 外推段（ml > 采样上限）：拟合曲线值与"前一章首关 × 最小增长"取大者。
    #     —— 单靠曲线会在衔接处倒挂（如 ml46 实测 8520 而二次曲线 pred(47)=7810），
    #        取大者确保外推段从实测终点单调续接，不出现"下一章推荐更低"。
    MIN_GROWTH = 1.02

    def build_first_series(measured, pred_fn):
        """measured: {ml -> display_value}。返回 {ml -> first_stage_value} 覆盖 1..extrap_cap。"""
        ml_max_meas = max(measured)
        series = {}
        for v in range(1, extrap_cap + 1):
            if v in measured:
                series[v] = measured[v]
            elif v <= ml_max_meas:
                # 采样区间内的缺口（理论上无，防御）：曲线 vs 前一章最小增长取大
                prev = series[v - 1]
                series[v] = max(round_up_10(pred_fn(v)), round_up_10(prev * MIN_GROWTH))
            else:
                # 外推段：曲线值 vs 前一章最小增长，取大者
                prev = series[v - 1]
                series[v] = max(round_up_10(pred_fn(v)), round_up_10(prev * MIN_GROWTH))
        return series

    first_p_series = build_first_series(measured_p, pred_p)
    first_e_series = build_first_series(measured_e, pred_e)

    def first_stage_p(v):
        """ml=v 章节首关的官方口径推荐值（实测段保序值 / 外推段单调续接）。"""
        return first_p_series.get(v, round_up_10(pred_p(v)))

    def first_stage_e(v):
        return first_e_series.get(v, round_up_10(pred_e(v)))

    # 章内梯度：stage 2..5 向"下一章首关"插值（末章用曲线外推 ml+1 作虚拟下一章）
    stage_vals_cache = {}

    def stage_values(v, key, first_fn, pred_fn):
        ck = (key, v)
        if ck in stage_vals_cache:
            return stage_vals_cache[ck]
        cur = first_fn(v)
        nxt = first_fn(v + 1)
        if nxt <= cur:  # 外推/实测衔接处防御：曲线回落时用 2% 最小增长兜底
            nxt = round_up_10(cur * 1.02)
        vals = interp_stage_values(cur, nxt)
        stage_vals_cache[ck] = vals
        return vals

    by_stage = {}
    for s in stages:
        v = s["monsterLevel"]
        if v > extrap_cap:
            continue
        st = max(1, min(5, s["stage"]))
        extr = v not in measured_p
        p_vals = stage_values(v, "p", first_stage_p, pred_p)
        e_vals = stage_values(v, "e", first_stage_e, pred_e)
        rec_p, rec_e = p_vals[st - 1], e_vals[st - 1]
        if rec_e >= rec_p:  # 全表 e<p 不变式兜底
            rec_e = rec_p - 5
        by_stage[s["stageId"]] = {"p": rec_p, "e": rec_e, "x": extr}
    n_extr = sum(1 for x in by_stage.values() if x["x"])
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
    lines.append(f"-- Normal+Hard 难度 ml {ml_min}..{ml_max} 采样）。带装备/养成推进的实际需求更低。")
    lines.append(f"-- 官方战力曲线: {name_p} R²={r2_p:.4f}；预估口径: {name_e} R²={r2_e:.4f}。")
    lines.append(f"-- monsterLevel > {ml_max} 的关卡为同曲线外推，未经实测验证，x = true；")
    lines.append(f"-- monsterLevel > {extrap_cap}（实测上限×2）的关卡指数外推不可信，不生成条目，")
    lines.append("-- SRP.get 返回 nil（数据不支持，接入方需处理）。")
    lines.append("-- v2.62 修正：首关实测阈值经 PAVA 保序 + 2% 最小梯度，章间严格递增；")
    lines.append("-- 章内 2..5 关在本章首关与下一章首关间按 0.2/0.4/0.6/0.8 权重插值（取整到 5）。")
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

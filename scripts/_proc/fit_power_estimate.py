#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fit_power_estimate.py — 分项计价战力原型的系数拟合（battle-lab 专用工具）

输入: 项目根 battle_lab_fit_samples.json（由 tests/battle_lab_fit.lua 产出）
输出: stdout 报告 + battle_lab_fit_result.json（同目录，供人工审阅，不进游戏包）

模型:
  败局中「场均总输出 = 存活时间 × 秒伤」，generic 组（HP/护甲/闪避等生存属性）
  通过拉长存活时间间接抬高总输出，直接回归总输出会让 generic 吞掉攻击组信号
  （physical 类实测 R²≈0.03、攻击组系数为负）。因此攻击系数改用 DPS 口径拟合：
    dps = avgDamage / avgSeconds  （healing 用 avgHealing / avgSeconds）
  每个伤害大类分别做岭回归：
    dps ≈ w_phys*phys + w_mag*mag + w_heal*heal + w_generic*generic + b
  - 只使用非饱和样本（winRate < 100）：全胜局伤害被怪物总血量截断，无回归信息量
  - 同时给出总输出口径的对照拟合（target=avgDamage），供审阅两种口径的差异
  - 拟合后按「本系系数」归一化：own=1.0，off = w_off / w_own，得到数据驱动的
    OFF_FACTOR 建议值；generic 同样除以 w_own 得到通用组相对权重

局限（报告中必须原样声明）:
  - 样本量小（每类 5~11 组），generic 组混杂了生存属性（HP/护甲通过拉长存活
    时间间接抬高败局总输出），线性模型只能给方向性系数，不是精确弹性
  - 单关卡（303）单等级带（Lv8/14），跨关卡泛化未验证
  - 岭回归 λ 固定，未做交叉验证调参
"""

import json
import sys
import numpy as np

RIDGE_LAMBDA = 1.0
GROUPS = ["phys", "mag", "heal", "generic"]


def fit_category(samples, category, target_fn):
    """对一个伤害大类做岭回归，返回 (系数 dict, 样本数, R²)"""
    rows = [s for s in samples if s["category"] == category
            and s["measured"]["winRate"] < 100]
    if len(rows) < 4:
        return None, len(rows), None
    X = np.array([[s["groups"][g] for g in GROUPS] for s in rows], dtype=float)
    y = np.array([target_fn(s["measured"]) for s in rows], dtype=float)
    # 岭回归： (XᵀX + λI) w = Xᵀy，带截距（截距不罚）
    n_feat = X.shape[1]
    A = np.zeros((n_feat + 1, n_feat + 1))
    A[:n_feat, :n_feat] = X.T @ X + RIDGE_LAMBDA * np.eye(n_feat)
    A[:n_feat, n_feat] = X.sum(axis=0)
    A[n_feat, :n_feat] = X.sum(axis=0)
    A[n_feat, n_feat] = len(rows)
    b = np.concatenate([X.T @ y, [y.sum()]])
    w = np.linalg.solve(A, b)
    # 非负约束：负系数截断为 0（生存属性混杂可能把 generic 拉负，不可解释）
    w_clipped = np.clip(w[:n_feat], 0, None)
    pred = X @ w_clipped + (y.mean() - (X @ w_clipped).mean())
    ss_res = float(((y - pred) ** 2).sum())
    ss_tot = float(((y - y.mean()) ** 2).sum())
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else float("nan")
    coef = {g: float(w_clipped[i]) for i, g in enumerate(GROUPS)}
    coef["_intercept"] = float(pred.mean() - (X @ w_clipped).mean())
    coef["_raw_negative_clipped"] = [GROUPS[i] for i in range(n_feat) if w[i] < 0]
    return coef, len(rows), r2


def normalize(own_key, coef):
    """按本系系数归一化，返回各组的相对权重（本系=1.0）"""
    own = coef.get(own_key, 0.0)
    if own <= 1e-9:
        return None
    return {g: round(coef[g] / own, 4) for g in GROUPS}


# R² 低于该阈值的拟合视为不可信，不参与 OFF_FACTOR 建议
R2_TRUST_THRESHOLD = 0.3


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "battle_lab_fit_samples.json"
    with open(path, encoding="utf-8") as f:
        samples = json.load(f)

    result = {"ridgeLambda": RIDGE_LAMBDA, "groups": GROUPS, "categories": {}}

    def dps_dmg(m):
        return m["avgDamage"] / m["avgSeconds"] if m["avgSeconds"] > 0 else 0.0

    def dps_heal(m):
        return m["avgHealing"] / m["avgSeconds"] if m["avgSeconds"] > 0 else 0.0

    def total_dmg(m):
        return m["avgDamage"]

    def total_heal(m):
        return m["avgHealing"]

    plan = [
        ("physical", dps_dmg, total_dmg, "phys"),
        ("magical", dps_dmg, total_dmg, "mag"),
        ("healing", dps_heal, total_heal, "heal"),
    ]
    for category, dps_fn, total_fn, own_key in plan:
        coef, n, r2 = fit_category(samples, category, dps_fn)
        coef_t, _, r2_t = fit_category(samples, category, total_fn)
        entry = {"target": "dps", "dpsTargetDesc": category, "ownGroup": own_key,
                 "samples": n}
        if coef is None:
            entry["error"] = "非饱和样本不足（<4），跳过"
            print(f"[{category}] 样本不足 n={n}，跳过")
        else:
            entry["coefficients"] = coef
            entry["r2"] = None if r2 is None else round(r2, 4)
            if coef_t is not None:
                entry["totalOutputR2"] = None if r2_t is None else round(r2_t, 4)
            norm = normalize(own_key, coef)
            entry["normalized"] = norm
            print(f"[{category}] n={n} DPS-R²={entry['r2']} "
                  f"(总输出对照 R²={entry.get('totalOutputR2')}) own={own_key}")
            for g in GROUPS:
                print(f"  w_{g:<8}= {coef[g]:10.4f}"
                      + (f"   (归一化 {norm[g]:.3f})" if norm else ""))
            if coef.get("_raw_negative_clipped"):
                print(f"  ⚠️ 负系数截断: {coef['_raw_negative_clipped']}")
        result["categories"][category] = entry

    # 汇总建议：只采信 R² ≥ 阈值的拟合；physical 的 off[heal] 来自 C20(vit+spi)
    # 单点样本与 generic 共线（vit 派生 HP 拉长败局存活），属于不可解释噪声，排除。
    offs = []
    excluded = []
    trust_plan = [("physical", "phys", ["mag"]), ("magical", "mag", ["phys"])]
    for category, own_key, off_keys in trust_plan:
        entry = result["categories"][category]
        norm = entry.get("normalized")
        r2 = entry.get("r2")
        if not norm:
            continue
        if r2 is None or r2 < R2_TRUST_THRESHOLD:
            excluded.append(f"{category}: R²={r2} < {R2_TRUST_THRESHOLD}")
            continue
        for k in off_keys:
            if norm.get(k) is not None:
                offs.append((category, k, norm[k]))
    excluded.append("physical: off[heal]=0.87 判为 C20 单点共线噪声，排除")
    excluded.append("healing: DPS/总输出 R² 均为负，模型不成立，不参与建议")
    result["excludedFromSuggestion"] = excluded
    result["r2TrustThreshold"] = R2_TRUST_THRESHOLD
    if offs:
        mean_off = sum(v for _, _, v in offs) / len(offs)
        result["suggestedOffFactor"] = round(mean_off, 3)
        print("\n可信异系归一化系数明细:")
        for category, k, v in offs:
            print(f"  {category}: off[{k}] = {v:.3f}")
        print("排除项:")
        for e in excluded:
            print(f"  - {e}")
        print(f"数据驱动 OFF_FACTOR ≈ {result['suggestedOffFactor']}（当前原型 0.25）")
        print("注：可信拟合的异系攻击系数均被非负约束截为 0——异系攻击属性对 DPS")
        print("    无贡献（其派生生存价值已计入 generic 组）。工程上建议保留小正值")
        print("    （如 0.10）防止显示战力对异系装备完全归零。")

    out = path.replace(".json", "_result.json")
    if out == path:
        out = path + ".result.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"\n已写入 {out}")


if __name__ == "__main__":
    main()

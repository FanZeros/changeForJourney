#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
inject_chapter_inheritance.py — 章节怪物继承注入（v2.62）

问题：存在与上一章怪物集合【零重叠】的章节（换章如换游戏，缺少渐进过渡）。
两类零重叠：
  A) 同一难度文件内，章 N 与章 N-1 怪物完全不同（如 Normal ch5/ch7/ch11...）
  B) 跨难度衔接点：难度链 Normal(1-23)→Hard(24-46)→...→湮灭V(323-345)
     章节编号全局连续，Hard 首章 ch24 的"上一章"是 Normal 末章 ch23，
     两者怪物集合也可能零重叠（玩家从 Normal 毕业进 Hard 的断裂感）。

本脚本对【全部】零重叠章节（含 A/B 两类）的 x-2 / x-4 关注入上一章代表怪：

  * 继承怪选取：上一章 2..4 关出场频次最高的普通怪（排除 bossId、排除
    首通附加怪），并列取 ID 小者 —— 即上一章玩家最熟悉的"面孔"。
  * 注入位置：x-2 与 x-4 关（章中与章末前，Boss 关 x-5 保持纯净）。
  * 注入方式：types < 3 → 末尾追加；types == 3 → 替换末位槽。
    （怪物总数由 firstCount 控制、出场轮换 ((i-1)%#types)+1，
     替换/追加均不改变战斗总怪数，仅改变构成 —— 平衡风险最小。）
  * 继承怪等级随关卡 monsterLevel 缩放，强度不塌方。

只修改与上一章零重叠的章节；已有重叠的章节不动。跨文件：按全局 chapter
链处理，注入写回该章所在的文件。幂等：重复运行时已产生重叠的章节自动跳过。

用法: python3 scripts/_proc/inject_chapter_inheritance.py [--dry-run]
"""

import glob
import re
import sys
from collections import Counter

PAT_ENTRY = re.compile(
    r"\{ id=(\d+),.*?chapter=(\d+),\s*stage=(\d+),\s*monsterLevel=(\d+),"
    r"\s*monsters=\{([^}]*)\}.*?bossId=(\d+)")
PAT_MONSTERS = re.compile(r"(monsters=\{)([^}]*)(\})")


def parse_line(line):
    m = PAT_ENTRY.search(line)
    if not m:
        return None
    return {
        "id": int(m.group(1)),
        "chapter": int(m.group(2)),
        "stage": int(m.group(3)),
        "ml": int(m.group(4)),
        "monsters": [int(x) for x in m.group(5).split(",") if x.strip()],
        "bossId": int(m.group(6)),
    }


def pick_inherit_monster(prev_entries):
    """上一章 2..4 关出场频次最高的普通怪（排除 boss），并列取 ID 小者。"""
    counter = Counter()
    bosses = set()
    for e in prev_entries:
        if e["bossId"] > 0:
            bosses.add(e["bossId"])
    for e in prev_entries:
        if 2 <= e["stage"] <= 4:
            for mid in e["monsters"]:
                if mid not in bosses:
                    counter[mid] += 1
    if not counter:  # 极端防御：2..4 关无普通怪，退回全章
        for e in prev_entries:
            for mid in e["monsters"]:
                if mid not in bosses:
                    counter[mid] += 1
    if not counter:
        return None
    best = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))
    return best[0][0]


def inject_into(monsters, inherit_id):
    """types<3 追加；==3 替换末位。返回新列表（无变化时返回 None）。"""
    if inherit_id in monsters:
        return None
    if len(monsters) < 3:
        return monsters + [inherit_id]
    if monsters[-1] == inherit_id:
        return None
    return monsters[:-1] + [inherit_id]


def load_all(files):
    """加载全部关卡，建立全局 chapter -> [entry(含 _fp/_li)] 映射。"""
    chapters = {}
    file_lines = {}
    for fp in files:
        with open(fp, encoding="utf-8") as f:
            lines = f.readlines()
        file_lines[fp] = lines
        for li, line in enumerate(lines):
            e = parse_line(line)
            if e:
                e["_fp"] = fp
                e["_li"] = li
                chapters.setdefault(e["chapter"], []).append(e)
    return chapters, file_lines


def main():
    dry = "--dry-run" in sys.argv
    files = sorted(glob.glob("scripts/config/StageConfig_*.lua"))
    chapters, file_lines = load_all(files)

    # 全局 chapter 链：找出所有与上一章零重叠的章（含跨难度衔接点）
    all_ch = sorted(chapters)
    zero_chapters = []
    for ch in all_ch:
        prev_ch = ch - 1
        if prev_ch not in chapters:
            continue  # 全链首章（Normal ch1）无前章
        cur_set = set(m for e in chapters[ch] for m in e["monsters"])
        prev_set = set(m for e in chapters[prev_ch] for m in e["monsters"])
        if not (cur_set & prev_set):
            zero_chapters.append(ch)

    # 计算注入（按文件分组收集 line 修改）
    line_edits = {}   # fp -> {li -> new_monsters}
    touched = []
    for ch in zero_chapters:
        prev_entries = chapters[ch - 1]
        inherit = pick_inherit_monster(prev_entries)
        if inherit is None:
            print(f"  [WARN] ch{ch}: 上一章无可继承普通怪，跳过")
            continue
        for e in chapters[ch]:
            if e["stage"] not in (2, 4):
                continue
            new_mons = inject_into(e["monsters"], inherit)
            if new_mons is None:
                continue
            line_edits.setdefault(e["_fp"], {})[e["_li"]] = new_mons
            touched.append((e["_fp"].rsplit("/", 1)[-1], ch, inherit,
                            e["id"], e["monsters"], new_mons))

    for name, ch, inherit, sid, old, new in touched:
        print(f"  [{name}] ch{ch} stage={sid} 继承上一章#{inherit}: {old} -> {new}"
              + ("  (dry-run)" if dry else ""))

    # 写回各文件
    if not dry:
        for fp, edits in line_edits.items():
            lines = file_lines[fp]
            for li, new_mons in edits.items():
                repl = "monsters={" + ",".join(str(m) for m in new_mons) + "}"
                lines[li] = PAT_MONSTERS.sub(lambda m: repl, lines[li], count=1)
            with open(fp, "w", encoding="utf-8") as f:
                f.writelines(lines)

    print(f"\n零重叠章节 {len(zero_chapters)} 个（含跨难度衔接点），"
          f"共修改 {len(touched)} 关" + ("（dry-run 未写盘）" if dry else ""))


if __name__ == "__main__":
    main()

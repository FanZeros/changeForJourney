-- 12 套装备名称与 36 条现行 2/4/6 件说明。
-- 只按完整简体原文匹配；数值、触发语义、套装归属与业务表保持不变。
-- 中文关键词交互仍由现有 KeywordText 管理，本词典不改变关键词/热区。
local D = { zh_TW = {}, en = {}, ja = {}, ko = {} }

---@param source string
---@param tw string
---@param en string
---@param ja string
---@param ko string
local function add(source, tw, en, ja, ko)
    D.zh_TW[source] = tw
    D.en[source] = en
    D.ja[source] = ja
    D.ko[source] = ko
end

-- 叠甲虫壳
add("叠甲虫壳", "疊甲蟲殼", "Stackplate Carapace", "重ね甲の虫殻", "겹갑 벌레껍질")
add("生命+6%，护甲加成+4%。", "生命+6%，護甲加成+4%。", "HP +6%, Armor Bonus +4%.", "HP+6%、防御補正+4%。", "생명 +6%, 방어 보너스 +4%.")
add("每次受击获得1层甲片（最多8）。每层受伤-1.5%。", "每次受擊獲得1層甲片（最多8）。每層受傷-1.5%。", "Each hit taken grants 1 Plate stack (max 8). Damage taken -1.5% per stack.", "被弾ごとに甲片を1層獲得（最大8層）。各層につき被ダメージ-1.5%。", "피격 시 갑편 1중첩 획득 (최대 8중첩). 중첩당 받는 피해 -1.5%.")
add("甲片满层时，下次攻击消耗全部层数，按层数×2%追加伤害并嘲讽2秒。", "甲片滿層時，下次攻擊消耗全部層數，按層數×2%追加傷害並嘲諷2秒。", "At max Plate stacks, the next attack consumes all stacks, adding stacks ×2% damage and taunting for 2s.", "甲片が最大層数になると、次の攻撃で全層を消費し、層数×2%の追加ダメージと2秒の挑発。", "갑편 최대 중첩 시 다음 공격이 모든 중첩을 소모하여 중첩 수 ×2% 추가 피해를 주고 2초간 도발.")

-- 夜行无面
add("夜行无面", "夜行無面", "Faceless Nightwalker", "夜行の無面", "밤의 무면")
add("暴击率+4%，闪避+5。", "暴擊率+4%，閃避+5。", "Crit Rate +4%, Evasion +5.", "会心率+4%、回避+5。", "치명타율 +4%, 회피 +5.")
add("攻击生命低于50%的敌人时，追加25%本次伤害。", "攻擊生命低於50%的敵人時，追加25%本次傷害。", "Attacks against enemies below 50% HP deal an extra 25% of that attack's damage.", "HP50%未満の敵を攻撃すると、その攻撃の25%を追加ダメージとして与える。", "생명 50% 미만인 적 공격 시 해당 공격 피해의 25%를 추가로 가함.")
add("击杀后4秒进入无面：清空仇恨。", "擊殺後4秒進入無面：清空仇恨。", "After a kill, enter Faceless for 4s: clear threat.", "撃破後4秒間、無面状態になる：敵視をリセット。", "처치 후 4초간 무면 상태: 위협 초기화.")

-- 裂隙水晶
add("裂隙水晶", "裂隙水晶", "Riftcrystal", "裂隙水晶", "균열 수정")
add("全伤害+4%，能量护盾加成+8%。", "全傷害+4%，能量護盾加成+8%。", "All DMG +4%, Energy Shield Bonus +8%.", "全ダメージ+4%、エネルギーシールド補正+8%。", "전체 피해 +4%, 에너지 보호막 보너스 +8%.")
add("攻击命中15%给目标1层晶蚀（最多5）。", "攻擊命中15%給目標1層晶蝕（最多5）。", "Attack hits have a 15% chance to apply 1 Crystal Erosion stack (max 5).", "攻撃命中時、15%で対象に晶蝕を1層付与（最大5層）。", "공격 명중 시 15% 확률로 대상에게 수정 침식 1중첩 부여 (최대 5중첩).")
add("晶蚀满5层碎裂：80%魔攻暗影伤害，并打断攻击进度。", "晶蝕滿5層碎裂：80%魔攻暗影傷害，並打斷攻擊進度。", "At 5 Crystal Erosion stacks, shatter for 80% Magic ATK as shadow damage and interrupt attack progress.", "晶蝕が5層で砕け、魔法攻撃力80%のシャドウダメージを与え、攻撃進行を中断。", "수정 침식 5중첩 시 파쇄: 마법 공격력 80%의 암영 피해를 주고 공격 진행을 중단.")

-- 终焉司仪袍
add("终焉司仪袍", "終焉司儀袍", "Finality Officiant's Robe", "終焉の司式者の衣", "종언 집례자의 로브")
add("治疗加成+8%，能量护盾加成+6%。", "治療加成+8%，能量護盾加成+6%。", "Heal Bonus +8%, Energy Shield Bonus +6%.", "回復補正+8%、エネルギーシールド補正+6%。", "회복 보너스 +8%, 에너지 보호막 보너스 +6%.")
add("过量治疗的20%转为能量护盾。", "過量治療的20%轉為能量護盾。", "Convert 20% of overhealing into Energy Shield.", "過剰回復の20%をエネルギーシールドに変換。", "초과 회복량의 20%를 에너지 보호막으로 전환.")
add("全队能量护盾加成+8%（不改写死亡）。", "全隊能量護盾加成+8%（不改寫死亡）。", "Team Energy Shield Bonus +8% (does not alter death).", "チーム全員のエネルギーシールド補正+8%（死亡処理は変更しない）。", "팀 전체 에너지 보호막 보너스 +8% (사망 처리는 변경하지 않음).")

-- 高压水脉
add("高压水脉", "高壓水脈", "High-pressure Tide", "高圧水脈", "고압 수맥")
add("魔法穿透+6，攻速+5%。", "魔法穿透+6，攻速+5%。", "Magic Penetration +6, Attack Speed +5%.", "魔法貫通+6、攻撃速度+5%。", "마법 관통 +6, 공격 속도 +5%.")
add("攻击主目标时30%溅射邻近1人，伤害35%。", "攻擊主目標時30%濺射鄰近1人，傷害35%。", "Attacking the main target has a 30% chance to splash 1 nearby enemy for 35% damage.", "主対象への攻撃時、30%で近くの敵1体に35%ダメージの飛沫。", "주 대상 공격 시 30% 확률로 인접한 적 1명에게 35% 피해의 광역 타격.")
add("被溅射目标3秒内攻击进度-20%。", "被濺射目標3秒內攻擊進度-20%。", "Splashed targets have attack progress -20% for 3s.", "飛沫を受けた対象は3秒間、攻撃進行-20%。", "광역 타격을 받은 대상은 3초간 공격 진행 -20%.")

-- 赛道硝烟
add("赛道硝烟", "賽道硝煙", "Racing Gunsmoke", "サーキットの硝煙", "경주로의 화약 연기")
add("攻速+8%，命中+6。", "攻速+8%，命中+6。", "Attack Speed +8%, Accuracy +6.", "攻撃速度+8%、命中+6。", "공격 속도 +8%, 명중 +6.")
add("每80点命中，连击率+2%（最多+10%）。", "每80點命中，連擊率+2%（最多+10%）。", "Every 80 Accuracy grants Combo Chance +2% (max +10%).", "命中80ごとに連撃率+2%（最大+10%）。", "명중 80마다 연격 확률 +2% (최대 +10%).")
add("连击时贯穿仇恨第二的目标（50%伤害）；仅1名敌人时自身攻速+12%持续2秒。", "連擊時貫穿仇恨第二的目標（50%傷害）；僅1名敵人時自身攻速+12%持續2秒。", "Combo hits pierce the second-highest-threat target for 50% damage; with only 1 enemy, gain Attack Speed +12% for 2s.", "連撃時、敵視が二番目の対象を貫通（50%ダメージ）。敵が1体だけなら自身の攻撃速度+12%、2秒間。", "연격 시 위협이 두 번째인 대상을 관통 (50% 피해). 적이 1명뿐이면 자신의 공격 속도 +12%, 2초 지속.")

-- 万剑门扉
add("万剑门扉", "萬劍門扉", "Myriad Sword Gate", "万剣の門扉", "만검의 문")
add("物理穿透+8，物伤+5%。", "物理穿透+8，物傷+5%。", "Physical Penetration +8, Phys. DMG +5%.", "物理貫通+8、物理ダメージ+5%。", "물리 관통 +8, 물리 피해 +5%.")
add("每6秒召唤1柄门缝飞剑，伤害=这6秒自身伤害的15%。", "每6秒召喚1柄門縫飛劍，傷害=這6秒自身傷害的15%。", "Every 6s, summon 1 Gate-gap Flying Sword; its damage equals 15% of your damage over those 6s.", "6秒ごとに門の隙間から飛剣を1本召喚。ダメージはその6秒間の自身のダメージの15%。", "6초마다 문틈 비검 1자루 소환. 피해는 해당 6초간 자신의 피해량의 15%.")
add("飞剑+1柄。穿套本人不额外飞一轮。", "飛劍+1柄。穿套本人不額外飛一輪。", "Flying Swords +1. The wearer does not gain an extra firing cycle.", "飛剣+1本。装備者本人の追加発射周期は発生しない。", "비검 +1자루. 착용자 본인의 추가 발사 주기는 발생하지 않음.")

-- 无光星图
add("无光星图", "無光星圖", "Starless Chart", "無光の星図", "빛 없는 성도")
add("魔法伤害+4%。", "魔法傷害+4%。", "Magic DMG +4%.", "魔法ダメージ+4%。", "마법 피해 +4%.")
add("魔法穿透+8。", "魔法穿透+8。", "Magic Penetration +8.", "魔法貫通+8。", "마법 관통 +8.")
add("每8秒对生命百分比最低的敌人打120%魔攻，不产生仇恨。", "每8秒對生命百分比最低的敵人打120%魔攻，不產生仇恨。", "Every 8s, deal 120% Magic ATK to the enemy with the lowest HP percentage, generating no threat.", "8秒ごとにHP割合が最も低い敵へ魔法攻撃力120%のダメージ。敵視は発生しない。", "8초마다 생명 비율이 가장 낮은 적에게 마법 공격력 120%의 피해를 가하며 위협을 생성하지 않음.")

-- 帝国铁壁
add("帝国铁壁", "帝國鐵壁", "Imperial Ironwall", "帝国の鉄壁", "제국의 철벽")
add("物理格挡+4%，生命+4%。", "物理格擋+4%，生命+4%。", "Physical Block +4%, HP +4%.", "物理ガード+4%、HP+4%。", "물리 막기 +4%, 생명 +4%.")
add("格挡成功时回复1%最大生命。", "格擋成功時回復1%最大生命。", "Successful blocks restore 1% max HP.", "ガード成功時、最大HPの1%を回復。", "막기 성공 시 최대 생명의 1% 회복.")
add("格挡成功时把挡掉伤害的30%反给攻击者（暗影，无仇恨）。", "格擋成功時把擋掉傷害的30%反給攻擊者（暗影，無仇恨）。", "Successful blocks reflect 30% of the blocked damage to the attacker (shadow, no threat).", "ガード成功時、防いだダメージの30%を攻撃者に反射（シャドウ、敵視なし）。", "막기 성공 시 막은 피해의 30%를 공격자에게 반사 (암영, 위협 없음).")

-- 巡林余烬
add("巡林余烬", "巡林餘燼", "Ember Scout", "森巡りの残り火", "숲 순찰자의 잔불")
add("命中+5，物理穿透+4。", "命中+5，物理穿透+4。", "Accuracy +5, Physical Penetration +4.", "命中+5、物理貫通+4。", "명중 +5, 물리 관통 +4.")
add("攻击施加余烬2秒：目标受伤+8%。", "攻擊施加餘燼2秒：目標受傷+8%。", "Attacks apply Ember for 2s: target takes +8% damage.", "攻撃で残り火を2秒間付与：対象の被ダメージ+8%。", "공격 시 2초간 잔불 부여: 대상이 받는 피해 +8%.")
add("余烬目标死亡时，余烬弹射到另一名敌人。", "餘燼目標死亡時，餘燼彈射到另一名敵人。", "When an Ember target dies, Ember jumps to another enemy.", "残り火を受けた対象が死亡すると、残り火が別の敵へ移る。", "잔불 대상 사망 시 잔불이 다른 적에게 전이.")

-- 赌徒残响
add("赌徒残响", "賭徒殘響", "Gambler's Echo", "賭博師の残響", "도박사의 잔향")
add("命数+4，最大伤害加成+8%。", "命數+4，最大傷害加成+8%。", "Fate +4, Max DMG Bonus +8%.", "命数+4、最大ダメージ補正+8%。", "명수 +4, 최대 피해 보너스 +8%.")
add("未暴击时下次暴击率+6%（最多叠3层，暴击清空）。", "未暴擊時下次暴擊率+6%（最多疊3層，暴擊清空）。", "Non-critical hits grant next Crit Rate +6% (max 3 stacks; critical hits clear stacks).", "非会心時、次の会心率+6%（最大3層、会心で全層解除）。", "치명타가 아닐 때 다음 치명타율 +6% (최대 3중첩, 치명타 시 초기화).")
add("暴击时额外一段30%伤害；若未暴击则回复1%已损失生命。", "暴擊時額外一段30%傷害；若未暴擊則回復1%已損失生命。", "Critical hits deal an extra 30% damage hit; non-critical hits restore 1% of missing HP.", "会心時、30%ダメージを追加。非会心なら失ったHPの1%を回復。", "치명타 시 30% 피해를 추가로 가함. 치명타가 아니면 잃은 생명의 1% 회복.")

-- 衔骨饥渴
add("衔骨饥渴", "銜骨飢渴", "Bonebite Hunger", "銜骨の飢渇", "뼈를 문 굶주림")
add("攻速+5%，攻击回血+4。", "攻速+5%，攻擊回血+4。", "Attack Speed +5%, HP on Attack +4.", "攻撃速度+5%、攻撃時HP回復+4。", "공격 속도 +5%, 공격 시 생명 회복 +4.")
add("生命低于70%时攻速再+8%。", "生命低於70%時攻速再+8%。", "Below 70% HP, gain an additional Attack Speed +8%.", "HP70%未満で攻撃速度がさらに+8%。", "생명 70% 미만일 때 공격 속도 추가 +8%.")
add("击杀回复3%最大生命。", "擊殺回復3%最大生命。", "Kills restore 3% max HP.", "撃破時、最大HPの3%を回復。", "처치 시 최대 생명의 3% 회복.")

return D

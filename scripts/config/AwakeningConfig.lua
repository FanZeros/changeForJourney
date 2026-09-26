-- ============================================================================
-- AwakeningConfig - 角色觉醒配置数据表
-- 觉醒描述按节点阶段直接展示，不在正文重复阶段名。
-- 旧 7 阶存档：1–3→新1，4–6→新2，7→新3
-- ============================================================================

local AC = {}

--- 觉醒配置表
--- AC.DATA[heroId][nodeIndex] = 觉醒效果描述文本
---@type table<number, string[]>
AC.DATA = {
    -- 1) R 拾骸者 大狗嚼
    [1] = {
        "【衔骨图鉴】：每次击杀永久生命上限+1；衔骨时物理穿透+10、伤害+10%。",
        "击杀敌人时记录其攻击属性，普攻可追加已记录属性的撕咬；衔骨时护甲+10、攻击速度+25%。",
        "生命低于35%时，衔骨效果翻倍；已记录的攻击属性可随普攻追加撕咬伤害。",
    },
    -- 2) R 裂隙使 黄桃龙
    [2] = {
        "【火葬场】：击杀燃烧中的敌人，永久魔法攻击+0.2；攻击燃烧目标时立即结算一次燃烧伤害。",
        "两名以上敌人燃烧时，魔法攻击加成+15%；燃烧可以暴击，燃烧伤害提高25%。",
        "燃烧最多叠加3层；魔法暴击率+10%、魔法暴击伤害+50%。",
    },
    -- 3) R 回响客 叮咚鸡
    [3] = {
        "【预约通知】：每次击杀永久增加0.2点物理攻击力；物理暴击率+5%。",
        "已读不回击杀会记录预存次数（最多5次）；精准命中后有25%概率使下一击继续触发已读不回。",
        "已读不回可攻击3名敌人；暴击伤害额外+50%。",
    },
    -- 4) SR 封门人 接化发掌门
    [4] = {
        "【武德银行】：格挡成功永久生命上限+0.5；格挡回复提升至5%，仇恨+50。",
        "格挡比例+10%；格挡成功时有10%概率返还本次受到的伤害。",
        "格挡成功有25%概率使攻击者眩晕1秒；化劲反击计入的格挡伤害提高50%。",
    },
    -- 5) SR 拾骸者 叠甲怪
    [5] = {
        "【焊甲】：击杀敌人后永久护甲+0.2；甲片上限+5，每层甲片额外提供0.5闪避值。",
        "甲片叠满时击杀可为下一场战斗积累开局甲片，最多保留15层；每层甲片额外提高连击伤害和物理伤害各1%。",
        "甲片满层时，甲片提供的属性效果额外提高50%。",
    },
    -- 6) SR 裂隙使 阿姨压
    [6] = {
        "【安可回路】：击杀感电目标永久魔法攻击+0.2；感电增伤提升至30%，持续3秒。",
        "感电目标攻击速度-10%；每有一名敌人感电，自身魔法攻击加成+5%。攻击后若至少两名敌人感电，会刷新其他感电目标的状态。",
        "感电目标被暴击的概率额外提高10%。",
    },
    -- 7) SR 回响客 信光机兵
    [7] = {
        "【必杀库存】：每次击杀永久连击率+0.1%；连击命中有20%概率降低目标7点魔法护甲；光线间隔缩短至每3次攻击。",
        "每次击杀记录一次预存光线（最多3次）；连击率+20%，连击必定命中。",
        "光线就绪时连击率+100%、连击伤害+30%；未就绪时无法触发连击。",
    },
    -- 8) SR 换面人 愤怒的小雀
    [8] = {
        "【仇册】：击杀标记目标永久提高全伤害0.15%；标记目标死亡后立即重新标记，攻击标记目标暴击率+15%。",
        "击杀标记目标可记录其攻击属性；攻击标记目标暴击伤害+30%，每个新标记目标的首次攻击必定暴击。",
        "攻击生命低于15%的标记目标时可触发斩杀。",
    },
    -- 9) SR 司仪 卡皮巴拉
    [9] = {
        "【温泉本金】：过量治疗永久精神+0.05；处于温泉状态的队友护甲+10，治疗暴击率+5%。",
        "处于温泉状态的队友受到的伤害降低5%；自身治疗加成+15%。",
        "温泉每秒恢复量提升至本次治疗量的25%。",
    },
    -- 17) SR 裂隙使 蓝色大肥鱼
    [17] = {
        "【水压图鉴】：潮湿目标受到的伤害加成由20%提升至30%，持续时间延长至3秒。",
        "溅射伤害由魔法攻击力的40%提升至55%；潮湿目标攻击速度-10%。",
        "场上至少3名敌人潮湿时，溅射会攻击所有潮湿目标；潮湿目标被暴击的概率额外提高10%。",
    },
    -- 10) SSR 封门人 铁憨憨
    [10] = {
        "【门板】：替队友承受的伤害导致自身阵亡时，永久生命上限+3；吸收伤害时回复2%生命（冷却3秒），仇恨翻倍、护甲+8。",
        "生命较低时护甲+12；开战生命加成提升至35%。",
        "全队单次受到的伤害不超过各自最大生命的30%（冷却8秒）。",
    },
    -- 11) SSR 拾骸者 熬夜冠军
    [11] = {
        "【斩影】：每次击杀永久物理攻击力+0.3；攻击速度+15%，通宵斩触发间隔缩短至每3次攻击。",
        "通宵斩击杀可记录斩影（最多4道）；物理暴击率+10%、暴击伤害+35%。",
        "有敌人阵亡后，调整攻击计数，使下一次攻击触发通宵斩。",
    },
    -- 12) SSR 裂隙使 雪皇
    [12] = {
        "【冰雕收藏】：每次击杀永久魔法攻击力+0.2、冰冻概率+0.05%（最高80%）；冰冻目标受到的伤害+20%。",
        "冰冻目标被击杀时生成冰雕（最多3座）；冰雕可替队友抵挡一次伤害，碎裂时冰冻敌人。首次冰冻延长2秒；自身首次低于半血时冰冻全场3秒。",
        "每冰冻一名敌人，魔法攻击加成+3%，最多20层。",
    },
    -- 13) SSR 回响客 弹弹弹
    [13] = {
        "【分裂弹】：每次击杀永久物理攻击力+0.25；物理穿透+10，弹射次数+1。",
        "弹射击杀积累分裂层，每8层额外弹射一次（最多+5）；物理攻击加成+25%、攻击速度+25%。",
        "累计40次弹射击杀后，攻击可额外命中至多两名其他敌人；弹射可重复命中同一敌人。",
    },
    -- 14) SSR 换面人 内鬼
    [14] = {
        "【抄作业簿】：每次击杀永久提高物理与魔法攻击各0.1%；闪避值+15，暴击率由15%提升至25%。",
        "开战获得10次受击免疫；敌人死亡后额外获得1至2次免疫。每次敌人死亡暴击伤害+10%，最多+100%。",
        "暴击时可斩杀生命低于15%的目标；暴击率溢出时有概率触发超暴击。",
    },
    -- 15) SSR 司仪 复活吧爱人
    [15] = {
        "【预存复活】：成功复活永久生命上限+2、复活概率+0.5%（上限80%）；治疗量+15%，被复活者5秒内受到的治疗+30%。",
        "为复活的队友留下一次濒死保护；复活概率提升至60%，复活时获得相当于最大生命20%的护盾，持续5秒。",
        "自己阵亡时按本场救援次数造成神圣范围伤害；首次阵亡必定复活，并为全队恢复20%生命。",
    },
    -- 16) UR 拾骸者 万剑归宗
    [16] = {
        "【剑冢】：每次击杀永久提高每柄飞剑伤害比例0.2%；飞剑间隔由5秒缩短至4秒，单柄伤害比例由50%提升至60%。",
        "飞剑命中时有10%概率将本柄伤害计入下次飞剑；触发间隔缩短至3秒，每轮最多7柄。",
        "飞剑命中后的飞回概率提升至50%。",
    },
    -- 20) UR 裂隙使 摘星星星人
    [20] = {
        "【星门殖民】：每次击杀永久提高星门伤害0.3%；星门随机附带冰、雷或火属性，攻击间隔由2.6秒缩短至2.2秒。",
        "星门基础伤害提升至400%，开战时开启2扇门；星门成长每累计40层额外增加1扇，总数最多3扇。角色阵亡后星门仍可攻击。",
        "星象共鸣效果提升50%。",
    },
    -- 21) SSR 拾骸者 闪电卖鸡
    [21] = {
        "【氮气赛道】：氮气击杀永久提高触发概率0.05%；命中+30，额外伤害由150%提升至180%。",
        "氮气触发后，下次攻击进度+15%；每80点命中额外获得5点护甲。",
        "氮气额外伤害享受魔法伤害加成。",
    },
    -- 22) SSR 裂隙使 小黑子
    [22] = {
        "【课时】：每次击杀永久缩短连续攻击的触发间隔；魔法伤害+10%，连续攻击次数由10次提升至12次。",
        "连续攻击期间击杀可积累预存次数；触发间隔缩短至每15次攻击，连续攻击时攻击速度+50%并积累过载。",
        "连续攻击期间每击杀一名敌人，下一轮触发所需攻击次数减少；每发连射有20%概率攻击所有敌人。",
    },
    -- 23) SSR 司仪 真布诗人
    [23] = {
        "【护盾积累】：过量治疗转盾永久提高护盾上限1点；转盾效率由100%提升至120%，全队护盾+10%。",
        "有盾队友的下次攻击可附带本次治疗量20%的额外伤害；临时护盾上限提高20%，治疗暴击率+10%。",
        "护盾清零时获得2秒无敌；每次触发后，下次触发概率减半。",
    },
    [18] = {
        "【蹲守图鉴】：每次击杀永久暴击率+0.1%。",
        "开战隐踪延长至6秒；首次攻击必定暴击，并获得额外0.08护甲克制系数。",
        "首次攻击获得的额外护甲克制系数提升至0.10。",
    },
    [19] = {
        "【功德积累】：每次击杀永久精神+0.05；治疗暴击额外获得1层功德。",
        "触发清心所需功德由5层降至4层。",
        "清心减伤提升至25%，持续时间延长至4.5秒。",
    },
    [24] = {
        "【加载条】：每次击杀永久生命上限+1；受伤时写入加载条的比例由25%提升至35%。",
        "加载条容量由最大生命的10%提升至14%；释放的伤害按粉碎属性结算。",
        "加载条闲置4秒未继续蓄能时，会释放已积累的伤害。",
    },
    [25] = {
        "【丢包补偿】：每次击杀永久增加0.3点物理攻击力；延迟伤害由原伤害的45%提升至55%。",
        "延迟结算缩短至1.2秒；结算时若目标生命比例低于出手时，该次延迟伤害提高50%。",
        "延迟结算时若目标生命低于30%，该次延迟伤害再提高25%。",
    },
}

AC.NODE_COUNT = 3

--- 旧 7 阶节点 → 新 3 阶：1–3→初醒，4–6→共鸣，7→蜕变
---@param nodeIndex number
---@return number
function AC.mapLegacyNode(nodeIndex)
    local n = tonumber(nodeIndex) or 0
    if n <= 0 then return 0 end
    if n <= 3 then return 1 end
    if n <= 6 then return 2 end
    return 3
end

--- 把旧 7 阶觉醒表压成 3 阶。
--- 未打 `_awk3Migrated` 的存档一律按旧 7 阶并档（旧 1–3 只进新 1，避免只点了前三阶被当成新三阶全开）。
---@param awakening table|nil
---@param alreadyMigrated boolean|nil 英雄级标记，防止 JSON 丢掉表内 `_awk3Migrated` 后把新 1/2/3 再压回 1
---@return table
function AC.migrateAwakening(awakening, alreadyMigrated)
    local out = {}
    if type(awakening) ~= "table" then
        out._awk3Migrated = true
        return out
    end
    if alreadyMigrated or awakening._awk3Migrated then
        for i = 1, AC.NODE_COUNT do
            if awakening[i] or awakening[tostring(i)] then
                out[i] = true
            end
        end
        out._awk3Migrated = true
        return out
    end
    if awakening[1] or awakening[2] or awakening[3]
        or awakening["1"] or awakening["2"] or awakening["3"] then
        out[1] = true
    end
    if awakening[4] or awakening[5] or awakening[6]
        or awakening["4"] or awakening["5"] or awakening["6"] then
        out[2] = true
    end
    if awakening[7] or awakening["7"] then
        out[3] = true
    end
    out._awk3Migrated = true
    return out
end

--- 是否已点指定节点（旧 1–7 会映射到新 1/2/3）
---@param awakening table|nil
---@param nodeIndex number
---@return boolean
function AC.hasNode(awakening, nodeIndex)
    local mapped = AC.mapLegacyNode(nodeIndex)
    if mapped <= 0 then return false end
    return AC.migrateAwakening(awakening)[mapped] == true
end

--- 已点亮的新 3 阶数量（忽略 `_awk3Migrated` 标记）
---@param awakening table|nil
---@return number
function AC.countActivated(awakening)
    local migrated = AC.migrateAwakening(awakening)
    local n = 0
    for i = 1, AC.NODE_COUNT do
        if migrated[i] then
            n = n + 1
        end
    end
    return n
end

--- 是否满觉醒（3 阶全开）
---@param awakening table|nil
---@return boolean
function AC.isFullyAwakened(awakening)
    return AC.countActivated(awakening) >= AC.NODE_COUNT
end

--- 获取指定角色的觉醒配置
---@param heroId number 英雄 ID (1~19, 20~25)
---@return string[]|nil 3个觉醒效果描述，索引1~3
function AC.get(heroId)
    return AC.DATA[heroId]
end

--- 获取指定角色指定觉醒节点的效果描述
---@param heroId number
---@param nodeIndex number 1~3
---@return string|nil
function AC.getNodeEffect(heroId, nodeIndex)
    local data = AC.DATA[heroId]
    if data then
        return data[nodeIndex]
    end
    return nil
end

-- ======================== 觉醒碎片消耗 ========================
-- 3 阶合计仍为 280（原 10+20+30+40+50+60+70）
AC.SHARD_COST = { 60, 90, 130 }

--- 获取指定节点的碎片消耗
---@param nodeIndex number 1~3
---@return number
function AC.getShardCost(nodeIndex)
    return AC.SHARD_COST[nodeIndex] or 0
end

--- 获取全部觉醒节点的碎片总消耗
---@return number
function AC.getTotalShardCost()
    local total = 0
    for _, cost in ipairs(AC.SHARD_COST) do
        total = total + cost
    end
    return total
end

-- ======================== 觉醒节点战力值 ========================
-- 3 阶合计与原 7 阶相同
AC.COMBAT_POWER = {
    [1] = { 18, 30, 20 },  -- R   合计68
    [2] = { 28, 45, 30 },  -- SR  合计103
    [3] = { 42, 65, 40 },  -- SSR 合计147
    [4] = { 52, 82, 50 },  -- UR  合计184
}

--- 计算指定角色已点亮觉醒节点的总战力
---@param heroId number 英雄ID (1~19, 20~25)
---@param awakening table|nil 觉醒状态
---@return number 觉醒总战力
function AC.calcTotalCombatPower(heroId, awakening)
    if not awakening then return 0 end
    local HeroConfig = require("config.HeroConfig")
    local hero = HeroConfig.get(heroId)
    if not hero then return 0 end
    local powerTable = AC.COMBAT_POWER[hero.quality]
    if not powerTable then return 0 end
    local migrated = AC.migrateAwakening(awakening)
    local total = 0
    for i = 1, AC.NODE_COUNT do
        if migrated[i] then
            total = total + (powerTable[i] or 0)
        end
    end
    return total
end

return AC

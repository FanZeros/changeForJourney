-- ============================================================================
-- AwakeningConfig - 角色觉醒配置数据表
-- 3 阶：1 粗暴永久层 / 2 机制 / 3 形态进化
-- 旧 7 阶存档：1–3→新1，4–6→新2，7→新3
-- ============================================================================

local AC = {}

--- 觉醒配置表
--- AC.DATA[heroId][nodeIndex] = 觉醒效果描述文本
---@type table<number, string[]>
AC.DATA = {
    -- 1) R 战士 大狗嚼
    [1] = {
        "粗暴【衔骨图鉴】：每击杀永久生命上限+1，立刻回1。衔骨时物穿+10、伤害+10%",
        "机制：每8杀咬进一种敌人攻击属性，普攻附带该系撕咬。衔骨时护甲+10、攻速+25%",
        "进化：8系齐了普攻变全系撕咬；生命低于35%时衔骨效果翻倍",
    },
    -- 2) R 法师 黄桃龙
    [2] = {
        "粗暴【火葬场】：燃烧击杀永久魔攻+0.2。打燃烧目标立即结算一次燃烧伤",
        "机制：每5层燃烧击杀，下场开场多种1个火种（最多4）。燃烧可暴击，伤害+25%",
        "进化：20层后燃烧击杀会炸着跳；燃烧最多叠3层，自带魔暴+10%/暴伤+50%",
    },
    -- 3) R 游侠 叮咚鸡
    [3] = {
        "粗暴【预约通知】：击杀永久物攻+0.2。物理暴击率+5%",
        "机制：精准击杀下场存1发已读不回（最多5发），开场先打。命中25%连锁下一次",
        "进化：预存精准开场改散射；已读不回触发时朝3个敌人散射，暴击额外+50%",
    },
    -- 4) SR 骑士 接化发掌门
    [4] = {
        "粗暴【武德银行】：格挡成功永久生命上限+0.5。格挡回复提升至5%，仇恨+50",
        "机制：挡掉的伤害存进银行，下场开场砸地。格挡比例+10%，10%完美格挡",
        "进化：格挡击杀后下次格挡必化劲反击（×1.5）；格挡可眩晕攻击者",
    },
    -- 5) SR 战士 叠甲怪
    [5] = {
        "粗暴【焊甲】：击杀永久护甲+0.2。[甲片]最大层数+5，每层+0.5闪避",
        "机制：满层征服击杀→下场开场自带1层甲片（最多15）。每层+1%连击增伤/物伤",
        "进化：每15次满层杀可蜕甲炸圈；满层效果再+50%",
    },
    -- 6) SR 法师 阿姨压
    [6] = {
        "粗暴【安可回路】：感电击杀永久魔攻+0.2。感电增伤30%、持续3秒",
        "机制：感电不散并可跳邻（最多4跳）。感电目标攻速-10%，每有一个感电魔攻+5%",
        "进化：3人同时感电→下次打所有感电目标；感电额外10%受暴击",
    },
    -- 7) SR 游侠 信光机兵
    [7] = {
        "粗暴【必杀库存】：击杀永久连击率+0.1%。连击命中20%永久降7护盾，间隔缩短为每3刀",
        "机制：击杀攒光线槽，下场开场先打贯穿光线（最多3道）。连击率+20%，连击必中",
        "进化：必杀触发时连击+100%、连击增伤+30%；开场光线改散射",
    },
    -- 8) SR 刺客 愤怒的小雀
    [8] = {
        "粗暴【仇册】：标记击杀永久全伤害+0.15%。标记死亡立即转标，打标记暴击+15%",
        "机制：击杀种类写入仇册；开场必标记仇人并多1发追踪。对标记暴伤+30%，首次必暴",
        "进化：仇册收满8种后标记死亡传染；残血15%斩杀",
    },
    -- 9) SR 牧师 卡皮巴拉
    [9] = {
        "粗暴【温泉本金】：溢出治疗永久精神+0.05。有温泉的队友护甲+10，治疗暴击+5%",
        "机制：溢出处留泉眼（最多3个）；泉眼里下次攻击附带治疗量神圣伤。受伤-5%，治疗+15%",
        "进化：3个泉眼同时在→全队齐射一次；温泉恢复比例提升至25%",
    },
    -- 17) SR 法师 蓝色大肥鱼
    [17] = {
        "粗暴【水压图鉴】：溅射击杀永久魔攻+0.2。潮湿增伤20%→30%，持续3秒",
        "机制：潮湿目标被击杀时水花跳到邻敌。溅射伤害40%→55%，潮湿目标攻速-10%",
        "进化：场上3人同时潮湿→下次喷水打所有潮湿目标；潮湿额外10%受暴击",
    },
    -- 10) SSR 骑士 铁憨憨
    [10] = {
        "粗暴【门板】：分摊致命伤永久生命上限+3。吸收回血2%（3秒CD），仇恨×2、护甲+8",
        "机制：每8次分摊→下场多1扇驻留门挡弹道（最多3）。低血护甲+12，生命加成+35%",
        "进化：当场砸门AOE；全队单次受伤不超过最大生命30%（8秒冷却）",
    },
    -- 11) SSR 战士 熬夜冠军
    [11] = {
        "粗暴【斩影】：击杀永久物攻+0.3（自己死保留50%本场层）。攻速+15%，间隔缩为每3刀",
        "机制：通宵斩击杀留下斩影，下场开场先劈（最多4道）。物暴+10%、暴伤+35%",
        "进化：自己死改由队友劈出斩影；通宵斩击杀立即刷新计数",
    },
    -- 12) SSR 法师 雪皇
    [12] = {
        "粗暴【冰雕收藏】：击杀永久魔攻+0.2、冰冻率+0.05%（软帽60%）。冰冻目标受伤+20%，冰冻率50%",
        "机制：冰冻结杀变冰雕挡弹道（最多3座），碎时冻场。首次冰冻+2秒，半血冻全场3秒",
        "进化：30层周围变冰面（走进攻速暂停）；每冰冻一名敌人魔攻+3%，最多20层",
    },
    -- 13) SSR 游侠 弹弹弹
    [13] = {
        "粗暴【分裂弹】：击杀永久物攻+0.25。物穿+10，弹射次数+1",
        "机制：弹射击杀计分裂层，每8层额外弹射+1（最多+5）。物攻+25%、攻速+25%",
        "进化：40次分裂后普攻进化为环绕弹；弹射可重复同一敌人",
    },
    -- 14) SSR 刺客 内鬼
    [14] = {
        "粗暴【抄作业簿】：击杀偷目标0.1%双攻（快照）。闪避+15，暴击率15%→25%",
        "机制：技能槽抄3条敌人行为。开场10次免疫，击杀再+1~2；击杀暴伤+10%最多100%",
        "进化：抄到「多目标+短间隔+异常」后，暴击击杀对残血即死；超暴击保留",
    },
    -- 15) SSR 牧师 复活吧爱人
    [15] = {
        "粗暴【预存复活】：成功复活永久生命上限+2、复活率+0.5%（软帽80%）。治疗+15%，被救5秒内治疗+30%",
        "机制：给被救者存一张「下场必死也活」的票。复活率60%，复活给20%HP护盾5秒",
        "进化：自己阵亡按发卡数放神圣核爆；自身首次死亡必定复活并全队回20%HP",
    },
    -- 16) UR 战士 万剑归宗
    [16] = {
        "粗暴【剑冢】：击杀永久飞剑系数+0.2%。间隔5秒→4秒，单柄伤害50%→60%",
        "机制：击杀处留驻留剑（最多8柄）。10%伤害记入下次飞剑；间隔3秒、上限4~7柄",
        "进化：50层定时丢剑→环绕护体持续索敌；飞回概率50%",
    },
    -- 20) UR 法师 摘星星星人
    [20] = {
        "粗暴【星门殖民】：星门击杀也算刀，永久星门伤害+0.3%。随机冰/雷/火，间隔2.6→2.2秒",
        "机制：星门本场不关；永久多1门（最多3）。基础伤害400%；开战2门，死后仍打",
        "进化：吸进去的敌人下一波当陨石砸出；星象共鸣继承+50%",
    },
    -- 21) SSR 战士 闪电卖鸡
    [21] = {
        "粗暴【氮气赛道】：银光击杀永久触发率+0.05%。命中+30，额外伤害150%→180%",
        "机制：留赛道（踩了加速+下次必银光，最多3条）。触发后进度+15%；每80命中+5护甲",
        "进化：每4次银光杀→下场开场贯穿冲刺；氮气享受魔法伤害加成",
    },
    -- 22) SSR 法师 小黑子
    [22] = {
        "粗暴【课时】：击杀永久机关枪阈值-0.05（下限8），每40层连打+1。魔伤+10%，连射10→12",
        "机制：机关枪期间击杀→下场开场先打半段（最多10连）。间隔缩为每15刀，连射攻速+50%并叠过载",
        "进化：越杀本段越短；连射每下20%概率打全体",
    },
    -- 23) SSR 牧师 即兴说唱王 真布诗人
    [23] = {
        "粗暴【护盾本金】：溢出转盾永久护盾上限+1。转盾效率100%→120%，全队护盾+10%",
        "机制：有盾的人下次攻击附带神圣伤；盾爆击退。临时盾上限+20%，治疗暴击+10%",
        "进化：3人同时有盾→全队齐射一次；护盾清零无敌2秒（概率递减）",
    },
}

AC.NODE_COUNT = 3

--- 旧 7 阶节点 → 新 3 阶：1–3→1 粗暴，4–6→2 机制，7→3 进化
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
---@param heroId number 英雄 ID (1~15, 16, 20~23)
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
---@param heroId number 英雄ID (1~15, 16, 20~23)
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

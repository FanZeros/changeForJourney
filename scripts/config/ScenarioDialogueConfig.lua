-- ============================================================================
-- ScenarioDialogueConfig.lua — 情景对话数据配置（玩梗版 v2.0 · 梗味拉满）
-- 对应策划配置: docs/配置文件/剧情-情景对话.txt
-- characterId: 立绘编号 (UI_DLH_X.png 中的 X)
-- mode: "large" = 大情景(全屏覆盖), "small" = 小情景(弹窗)
-- 人设规则: 主角台词贴合玩梗形象; NPC/假角色(黑暗镜像)保留原剧情功能
-- ============================================================================

local ScenarioDialogueConfig = {}

--- 情景 1：新手过场动画结束后触发
--- 出现条件: 结束新手剧情过场动画时接上该情景
--- 结束后衔接角色选择界面
ScenarioDialogueConfig.SCENARIO_1 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    eyeOpen = true,
    steps = {
        { characterId = 1, name = "大狗嚼", text = "远征长！别睡懒觉啦！叫！今天有出发的通知！" },
        { characterId = 1, name = "大狗嚼", text = "有我在前面开路，什么怪物都闻风而逃！嘿嘿，尾巴已经摇起来了！" },
        { characterId = 2, name = "黄桃龙", text = "哇！今天天气真好！最适合黄桃龙出来玩耍了！" },
        { characterId = 2, name = "黄桃龙", text = "远征长放心！黄桃龙的火焰魔法状态超好！...大概！只要别再把地图烧掉就没问题！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风向通知：正常，适合赶路。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~补给通知：水和干粮已备齐。不是担心你们，只是通知要发。" },
        { characterId = 1, name = "大狗嚼", text = "全员就位！叫！远征长，你想让谁打头阵？" },
    },
}

--- 情景 2：选择大狗嚼后的小情景对话
--- 出现条件: 初始角色选择了大狗嚼（战士）
ScenarioDialogueConfig.SCENARIO_2 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "选我？叫！好嘞！骨头……不对，功劳包在我身上！" },
        { characterId = 1, name = "大狗嚼", text = "远征长就跟在我后面，前面的敌人我一口一个！出发！" },
    },
}

--- 情景 3：选择黄桃龙后的小情景对话
--- 出现条件: 初始角色选择了黄桃龙（法师）
ScenarioDialogueConfig.SCENARIO_3 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "诶？！选黄桃龙当先锋吗？好耶！" },
        { characterId = 2, name = "黄桃龙", text = "看我的！火焰魔法，发射！...这次绝对不会烧到自己人的！大概！" },
    },
}

--- 情景 4：选择叮咚鸡后的小情景对话
--- 出现条件: 初始角色选择了叮咚鸡（射手）
ScenarioDialogueConfig.SCENARIO_4 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~收到通知。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~侦查通知：我在前方。有情况的话，箭比声音先到。" },
    },
}

--- 情景 5：大狗嚼首通1-1 后的小情景对话（获得武器奖励：优质 练习用大剑）
--- 出现条件: 初始角色为大狗嚼时首通1-1
ScenarioDialogueConfig.SCENARIO_5 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "赢了！叫！远征长你看到了吗，我刚才那一口——啊等等我踩到什么了？" },
        { characterId = 1, name = "大狗嚼", text = "诶？！是把大剑！埋在草丛里了...比我这把好太多了！远征长我能用这把吗！叫！" },
    },
    rewards = {
        { type = "equip", templateId = "W7", quality = 2, level = 1 },
    },
}

--- 情景 6：黄桃龙首通1-1 后的小情景对话（获得武器奖励：优质 学徒木杖）
--- 出现条件: 初始角色为黄桃龙时首通1-1
ScenarioDialogueConfig.SCENARIO_6 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "炸、炸到了！等等这次居然没炸到自己？！诶，怪物堆里有东西在发光！" },
        { characterId = 2, name = "黄桃龙", text = "是根法杖！一定是黄桃龙的火球炸出来的！黄桃龙果然是天才！...大概！" },
    },
    rewards = {
        { type = "equip", templateId = "W25", quality = 2, level = 1 },
    },
}

--- 情景 7：叮咚鸡首通1-1 后的小情景对话（获得武器奖励：优质 木质短弓）
--- 出现条件: 初始角色为叮咚鸡时首通1-1
ScenarioDialogueConfig.SCENARIO_7 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：全部命中。回收箭矢时发现一把短弓。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：木质短弓，比现在的顺手。已回收。不是特意捡的。" },
    },
    rewards = {
        { type = "equip", templateId = "W37", quality = 2, level = 1 },
    },
}

--- 情景 8：大狗嚼首通1-2 后的小情景对话（获得护甲奖励：优质 硬铁重衣）
--- 出现条件: 初始角色为大狗嚼时首通1-2
ScenarioDialogueConfig.SCENARIO_8 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "呼...这些家伙打得好疼！衣服都裂了...没问题的，只是毛乱了！叫！" },
        { characterId = 1, name = "大狗嚼", text = "啊！远征长你看！一件硬铁重衣！穿上就不怕挨打了！我试试——嘿，刚好合身！" },
    },
    rewards = {
        { type = "equip", templateId = "A25", quality = 2, level = 1 },
    },
}

--- 情景 9：黄桃龙首通1-2 后的小情景对话（获得护甲奖励：优质 粗布长袍）
--- 出现条件: 初始角色为黄桃龙时首通1-2
ScenarioDialogueConfig.SCENARIO_9 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "刚才那个火球有点大了...又把自己衣服烧了个洞...呜呜远征长你不要看！" },
        { characterId = 2, name = "黄桃龙", text = "诶？角落有件粗布长袍！摸着好像不怕火烧？太好了换上换上！" },
    },
    rewards = {
        { type = "equip", templateId = "A49", quality = 2, level = 1 },
    },
}

--- 情景 10：叮咚鸡首通1-2 后的小情景对话（获得护甲奖励：优质 破烂鳞甲）
--- 出现条件: 初始角色为叮咚鸡时首通1-2
ScenarioDialogueConfig.SCENARIO_10 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：敌人变强，手臂被蹭到。需要防护。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：鳞甲已拾取并穿上。不要看我。换衣服而已。" },
    },
    rewards = {
        { type = "equip", templateId = "A19", quality = 2, level = 1 },
    },
}

--- 情景 11：大狗嚼首通1-3 后的大情景对话（获得角色奖励：随机获得黄桃龙或叮咚鸡）
--- 出现条件: 初始角色为大狗嚼时首通1-3
ScenarioDialogueConfig.SCENARIO_11 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "呼——终于打完了！叫！话说回来...黄桃龙和叮咚鸡怎么还没跟上来？" },
        { characterId = 1, name = "大狗嚼", text = "不会是迷路了吧？还是被怪物缠住了？远征长，我们先等等——叫！那边有动静！" },
    },
    rewards = {
        { type = "hero", heroPool = { 2, 3 } },
    },
}

--- 情景 12：黄桃龙首通1-3 后的大情景对话（获得角色奖励：随机获得大狗嚼或叮咚鸡）
--- 出现条件: 初始角色为黄桃龙时首通1-3
ScenarioDialogueConfig.SCENARIO_12 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "赢了赢了！...诶，等一下，大狗嚼和叮咚鸡呢？她们不是说跟在后面的吗？" },
        { characterId = 2, name = "黄桃龙", text = "呜呜，不会出什么事了吧...远征长，我们等一下她们好不好？...啊！那边有人过来了！" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 3 } },
    },
}

--- 情景 13：叮咚鸡首通1-3 后的大情景对话（获得角色奖励：随机获得大狗嚼或黄桃龙）
--- 出现条件: 初始角色为叮咚鸡时首通1-3
ScenarioDialogueConfig.SCENARIO_13 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：战斗结束，清点物资——只有我们两个。大狗嚼和黄桃龙没有跟上。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：不用担心，她们不会有事。...有脚步声，从后方来的。" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 2 } },
    },
}

--- 情景 14：获得大狗嚼后的跟上对话
--- 出现条件: 通过情景11-13获得大狗嚼
ScenarioDialogueConfig.SCENARIO_14 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "哈...哈...终于追上你们了！刚才那群怪物太黏人了，啃了半天才脱身！叫！我来了就万事大吉！" },
    },
}

--- 情景 15：获得黄桃龙后的跟上对话
--- 出现条件: 通过情景11-13获得黄桃龙
ScenarioDialogueConfig.SCENARIO_15 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "等、等等我！呼...差点就追丢了！刚才有只怪突然窜出来，黄桃龙一个火球把它炸飞了...顺便把路标也炸了...但黄桃龙还是找到你们了！" },
    },
}

--- 情景 16：获得叮咚鸡后的跟上对话
--- 出现条件: 通过情景11-13获得叮咚鸡
ScenarioDialogueConfig.SCENARIO_16 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~道歉通知：来晚了。路上的麻烦已处理。...从现在起，我会跟紧的。" },
    },
}

--- 情景 17：大狗嚼首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为大狗嚼时首通0104
ScenarioDialogueConfig.SCENARIO_17 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "远征长！看我找到了什么！是我们丢掉的日志！叫！" },
    },
}

--- 情景 18：黄桃龙首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为黄桃龙时首通0104
ScenarioDialogueConfig.SCENARIO_18 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "远征长，日……日志找到了！差点就用火球烧掉了！" },
    },
}

--- 情景 19：叮咚鸡首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为叮咚鸡时首通0104
ScenarioDialogueConfig.SCENARIO_19 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：已找到之前丢失的日志。" },
    },
}

--- 情景 20：大狗嚼首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为大狗嚼时首通0105
ScenarioDialogueConfig.SCENARIO_20 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "呼呼！真是一场恶战！叫！不过还好……没受伤，毛都没掉几根。" },
        { characterId = 1, name = "大狗嚼", text = "这边过去好像就到城镇了，我们要不去城镇里逛一逛。" },
    },
}

--- 情景 21：黄桃龙首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为黄桃龙时首通0105
ScenarioDialogueConfig.SCENARIO_21 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "成……成功了！黄桃龙们成功了！远征长！" },
        { characterId = 2, name = "黄桃龙", text = "好累！前面好像是城镇！我们要不要去逛一逛。" },
    },
}

--- 情景 22：叮咚鸡首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为叮咚鸡时首通0105
ScenarioDialogueConfig.SCENARIO_22 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~战报：森之巨灵，击破。不过如此。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：前方发现聚集地，去补给一下吧。" },
    },
}

--- 情景 23：首次进入城镇
--- 出现条件: 首次进入城镇
ScenarioDialogueConfig.SCENARIO_23 = {
    mode = "small",
    steps = {
        { characterId = 11, name = "卫兵", text = "站住！你们是哪里来的！" },
    },
}

--- 情景 24：大狗嚼结束情景23后
--- 出现条件: 初始角色为大狗嚼时结束情景23
ScenarioDialogueConfig.SCENARIO_24 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "大狗嚼", text = "哈喽！叫！我们是路过的冒险家，这位是我们远征长！" },
        { characterId = 11, name = "卫兵", text = "又是新来的冒险家？每一位外来者必须要先去教堂后才可自由活动，请跟我来" },
    },
}

--- 情景 25：黄桃龙结束情景23后
--- 出现条件: 初始角色为黄桃龙时结束情景23
ScenarioDialogueConfig.SCENARIO_25 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "黄桃龙", text = "呜！黄桃龙们是路过的冒险家…！是…正义的伙伴！" },
        { characterId = 11, name = "卫兵", text = "又是自诩正义伙伴的家伙么？每一位外来者必须要先去教堂后才可自由活动，请跟我来" },
    },
}

--- 情景 26：叮咚鸡结束情景23后
--- 出现条件: 初始角色为叮咚鸡时结束情景23
ScenarioDialogueConfig.SCENARIO_26 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~通知：没有恶意，只是路过，看看有没有补给。" },
        { characterId = 11, name = "卫兵", text = "每一位外来者必须要先去教堂后才可自由活动，请跟我来" },
    },
}

--- 情景 27：初次进入教堂
--- 出现条件: 初次进入教堂
ScenarioDialogueConfig.SCENARIO_27 = {
    mode = "small",
    steps = {
        { characterId = 21, name = "圣女", text = "又是新来的嘛？想要得到祝福的话，请抬头看向天空吧……" },
    },
}

--- 情景 28：大狗嚼首次离开教堂
--- 出现条件: 初始角色为大狗嚼时首次离开教堂
ScenarioDialogueConfig.SCENARIO_28 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "大狗嚼", text = "叫！感觉全身充满了力量！好像变强了！" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 1,  name = "大狗嚼", text = "走吧远征长！我们去酒馆看看！叫！" },
    },
}

--- 情景 29：黄桃龙首次离开教堂
--- 出现条件: 初始角色为黄桃龙时首次离开教堂
ScenarioDialogueConfig.SCENARIO_29 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "黄桃龙", text = "远征长远征长！黄桃龙的火焰魔法，好像更强大了！" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 2,  name = "黄桃龙", text = "酒馆！一定有很多好吃的吧！好想吃炸薯条、烤肉片、芝士鸡肉汉堡、甜奶昔……" },
    },
}

--- 情景 30：叮咚鸡首次离开教堂
--- 出现条件: 初始角色为叮咚鸡时首次离开教堂
ScenarioDialogueConfig.SCENARIO_30 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~通知：获得了神明的祝福。也许有点意思……" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~出发通知：走吧，去看看。" },
    },
}

--- 情景 31：首次进入酒馆
--- 出现条件: 首次进入酒馆
ScenarioDialogueConfig.SCENARIO_31 = {
    mode = "small",
    steps = {
        { characterId = 13, name = "老板娘", text = "呀！欢迎！是新来的远征队嘛？要不要来喝一杯呀~" },
    },
    rewards = {
        { type = "scroll", count = 10 },
    },
}

--- 情景 32：大狗嚼首次离开酒馆
--- 出现条件: 初始角色为大狗嚼时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_32 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！看来我们招募到新伙伴了！团队的骨头……不对，实力又变强了！" },
    },
}

--- 情景 33：黄桃龙首次离开酒馆
--- 出现条件: 初始角色为黄桃龙时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_33 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "交到新朋友啦！接下来黄桃龙们要一起努力哦！" },
    },
}

--- 情景 34：叮咚鸡首次离开酒馆
--- 出现条件: 初始角色为叮咚鸡时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_34 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~评估通知：新伙伴还不赖……希望不会拖我们后腿…" },
    },
}

--- 情景 35：大狗嚼首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为大狗嚼时首通0201
ScenarioDialogueConfig.SCENARIO_35 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 1,  name = "大狗嚼", text = "叫！前方有声音，远征长！我们快去看看发生了什么！" },
    },
}

--- 情景 36：黄桃龙首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为黄桃龙时首通0201
ScenarioDialogueConfig.SCENARIO_36 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 2,  name = "黄桃龙", text = "远征长！有人在叫！黄桃龙们快去看看！" },
    },
}

--- 情景 37：叮咚鸡首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为叮咚鸡时首通0201
ScenarioDialogueConfig.SCENARIO_37 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~求助通知：有人需要帮助……加快脚步吧。" },
    },
}


--- 情景 38：大狗嚼首次全体阵亡失败的大情景
--- 出现条件: 初始角色为大狗嚼时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_38 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 1,  name = "大狗嚼",   text = "远征长……我们就要……在这里倒下了吗？叫……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 1,  name = "大狗嚼",   text = "什么情况！远征长？我怎么活过来了！？叫！刚刚发生了什么？" },
    },
}

--- 情景 39：黄桃龙首次全体阵亡失败的大情景
--- 出现条件: 初始角色为黄桃龙时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_39 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 2,  name = "黄桃龙",   text = "呜呜远征长！黄…黄桃龙…要坚持不住了…" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 2,  name = "黄桃龙",   text = "呜呜远征长！黄桃龙以为再也见不到你了！" },
    },
}

--- 情景 40：叮咚鸡首次全体阵亡失败的大情景
--- 出现条件: 初始角色为叮咚鸡时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_40 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 3,  name = "叮咚鸡",   text = "叮……咚……远征长……你先走……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 3,  name = "叮咚鸡",   text = "叮咚~通知：还……活着吗？" },
    },
}

--- 情景 41：大狗嚼首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为大狗嚼时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_41 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 1,  name = "大狗嚼",      text = "叫！你认错人了吧！我们是来救你的！" },
    },
}

--- 情景 42：黄桃龙首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为黄桃龙时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_42 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 2,  name = "黄桃龙",      text = "什么？！喂喂！黄桃龙们只是路过的冒险家啊！" },
    },
}

--- 情景 43：叮咚鸡首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为叮咚鸡时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_43 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 3,  name = "叮咚鸡",      text = "叮咚~澄清通知：认错人了吧。不过你想打就陪你打……" },
    },
}

--- 情景 44：大狗嚼首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为大狗嚼时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_44 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的剑上没有黑色的气息。" },
        { characterId = 1,  name = "大狗嚼", text = "本来就不是啊……叫！你一上来就打，都没给我们解释的机会！" },
        { characterId = 10, name = "铁匠", text = "很抱歉，但刚刚确实有一伙儿和你们很像的……算了，先不说这个了，作为补偿请来我的铁匠铺吧，我为你们进行装备强化" },
    },
}

--- 情景 45：黄桃龙首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为黄桃龙时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_45 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的火焰魔法中没有邪恶的气息。" },
        { characterId = 2,  name = "黄桃龙", text = "都说了不是！你怎么就听不进去话呢！哼！挨打了吧！" },
        { characterId = 10, name = "铁匠", text = "很抱歉，但刚刚确实有一伙儿和你们很像的……算了，先不说这个了，作为补偿请来我的铁匠铺吧，我为你们进行装备强化" },
    },
}

--- 情景 46：叮咚鸡首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为叮咚鸡时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_46 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的箭矢中没有暗黑的回响" },
        { characterId = 3,  name = "叮咚鸡", text = "叮咚~疑问：暗黑的回响？这是怎么回事？" },
        { characterId = 10, name = "铁匠", text = "很抱歉，但刚刚确实有一伙儿和你们很像的……算了，先不说这个了，作为补偿请来我的铁匠铺吧，我为你们进行装备强化" },
    },
}

--- 情景 47：首次进入铁匠铺
--- 出现条件: 首次进入铁匠铺
ScenarioDialogueConfig.SCENARIO_47 = {
    mode = "small",
    steps = {
        { characterId = 10, name = "铁匠", text = "欢迎来到我的铁匠铺，让我来看看你的武器" },
    },
    rewards = {
        { type = "scroll", count = 20 },
    },
}

--- 情景 48：大狗嚼首次离开铁匠铺
--- 出现条件: 初始角色为大狗嚼时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_48 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！感觉不错，剑身更加锋利了！" },
    },
}

--- 情景 49：黄桃龙首次离开铁匠铺
--- 出现条件: 初始角色为黄桃龙时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_49 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "唔，法杖的魔力更加充裕了！" },
    },
}

--- 情景 50：叮咚鸡首次离开铁匠铺
--- 出现条件: 初始角色为叮咚鸡时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_50 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~装备通知：箭矢更加锋利了，还不错……" },
    },
}

--- 情景 51：大狗嚼首次通关关卡0205
--- 出现条件: 初始角色为大狗嚼时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_51 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "总感觉有些吃力了……叫！听说城镇里新开放了一个竞技场，要不我们去看看？" },
    },
}

--- 情景 52：黄桃龙首次通关关卡0205
--- 出现条件: 初始角色为黄桃龙时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_52 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "呜！好强的怪物，黄桃龙的实力好像跟不上了，需要多磨练一下才行！" },
    },
}

--- 情景 53：叮咚鸡首次通关关卡0205
--- 出现条件: 初始角色为叮咚鸡时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_53 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "咳咳……有点吃力了。叮咚~建议通知：去竞技场磨练一下。" },
    },
}

--- 情景 54：首次进入竞技场
--- 出现条件: 首次进入竞技场
ScenarioDialogueConfig.SCENARIO_54 = {
    mode = "small",
    steps = {
        { characterId = 9,  name = "村长",  text = "就按照这样办吧，你办事我还是放心的" },
        { characterId = 20, name = "黑衣人", text = "就交给我吧，我会让你满意的（离开）" },
        { characterId = 9,  name = "村长",  text = "哦！是新来的冒险家啊，请这边来，登记后就可以参加竞技场比赛了！" },
    },
}

-- 情景 55：大狗嚼首次通关关卡1305
-- 出现条件: 初始角色为大狗嚼时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_55 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "叫！刚刚好像掉落了什么好东西！快来看看！" },
    },
}

-- 情景 56：黄桃龙首次通关关卡1305
-- 出现条件: 初始角色为黄桃龙时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_56 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "这是什么！上面还有血迹！黄桃龙闻起来…是其他冒险家留下的遗物吗？" },
    },
}

-- 情景 57：叮咚鸡首次通关关卡1305
-- 出现条件: 初始角色为叮咚鸡时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_57 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：发现其他冒险家留下的遗物。" },
    },
}

--- 情景 58：大狗嚼首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为大狗嚼时首通0305
ScenarioDialogueConfig.SCENARIO_58 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "报告！叫！发现一个金矿洞穴！我们可以去啃……哦不，探查一番！" },
    },
}

--- 情景 59：黄桃龙首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为黄桃龙时首通0305
ScenarioDialogueConfig.SCENARIO_59 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "黄桃龙", text = "哇！远征长，这下面有好多的黄金呀！黄桃龙眼睛都亮了！" },
    },
}

--- 情景 60：叮咚鸡首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为叮咚鸡时首通0305
ScenarioDialogueConfig.SCENARIO_60 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风险通知：洞穴可能有危险……但通知未禁止进入。" },
    },
}

--- 情景 61：首次进入终端关卡0999
--- 出现条件: 首次进入关卡0999
ScenarioDialogueConfig.SCENARIO_61 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "哦？有趣，竟然又抵达这里了？" },
        { characterId = 1, name = "大狗嚼", text = "叫！你是？一切的元凶？" },
        { characterId = 2, name = "黄桃龙", text = "大魔王！受死吧！黄桃龙代表月亮消灭你！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~开战通知：看我的利箭！" },
    },
}

--- 情景 62：通关关卡0999（轮回前播放）
--- 出现条件: 通关关卡0999，在进入轮回前播放
ScenarioDialogueConfig.SCENARIO_62 = {
    mode = "small",
    steps = {
        { characterId = 4, name = "？？？", text = "实力不错嘛~小家伙们~不过……该重新上路了！" },
    },
}

--- 情景 63：首次进入困难模式关卡2401
--- 出现条件: 首次进入关卡2401
ScenarioDialogueConfig.SCENARIO_63 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "大狗嚼", text = "远征长！别睡懒觉啦！叫！我们要开始出发了！" },
        { characterId = 1, name = "大狗嚼", text = "有我在前面开路，什么怪物都不怕！嘿嘿，就是有点小激动！" },
        { characterId = 2, name = "黄桃龙", text = "哇，今天天气真不错！最适合黄桃龙冒险了！" },
        { characterId = 2, name = "黄桃龙", text = "远征长放心！黄桃龙的火焰魔法今天状态超好！...大概！只要别再把地图烧掉就没问题！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~风向通知：正常，适合赶路。" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~补给通知：水和干粮已备齐。不是担心你们，只是通知要发。" },
        { characterId = 1, name = "大狗嚼", text = "全员就位！叫！一起出发！" },
    },
}

--- 情景 64：首次进入关卡2505（假大狗嚼遭遇）
--- 出现条件: 首次进入关卡2505
ScenarioDialogueConfig.SCENARIO_64 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长……你怎么一个人走了啊？我们不是打败大魔王了吗……" },
        { characterId = 1, name = "大狗嚼", text = "叫?!什么情况！远征长？这是……我？" },
        { characterId = 6, name = "大狗嚼？", text = "远征长找到新的大狗嚼了嘛？不允许！" },
        { characterId = 6, name = "大狗嚼？", text = "远征长只能属于我！" },
        { characterId = 1, name = "大狗嚼", text = "不知道你是从哪来的！叫！远征长我们上！一起击败她！" },
    },
}

--- 情景 65：首次进入关卡2705（假黄桃龙遭遇）
--- 出现条件: 首次进入关卡2705
ScenarioDialogueConfig.SCENARIO_65 = {
    mode = "large",
    background = "image/关卡地图/MAP_4.png",
    steps = {
        { characterId = 7, name = "黄桃龙？", text = "远征长……人家等你好久了，我们刚刚拯救了世界哦~" },
        { characterId = 2, name = "黄桃龙", text = "这难道是？另一个黄桃龙吗？" },
        { characterId = 7, name = "黄桃龙？", text = "呜呜呜！远征长难道不要人家了~" },
        { characterId = 7, name = "黄桃龙？", text = "说好的要组一辈子远征队的！既然如此，那就死吧！" },
        { characterId = 2, name = "黄桃龙", text = "远征长小心！她虽然和黄桃龙长得很像，但绝对不是黄桃龙！" },
    },
}

--- 情景 67：首次进入关卡2905（假叮咚鸡遭遇）
--- 出现条件: 首次进入关卡2905
ScenarioDialogueConfig.SCENARIO_67 = {
    mode = "large",
    background = "image/关卡地图/MAP_6.png",
    steps = {
        { characterId = 8, name = "叮咚鸡？", text = "远征长……你来了，不要再……继续前进了" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~疑问：什么意思？" },
        { characterId = 8, name = "叮咚鸡？", text = "只要一直前进的话，就永远都停不下来……" },
        { characterId = 8, name = "叮咚鸡？", text = "快杀了我……" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：……收到" },
    },
}

--- 情景 68：首次进入困难终端关卡1999
--- 出现条件: 首次进入关卡1999
ScenarioDialogueConfig.SCENARIO_68 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "又来了么？真有意思" },
        { characterId = 4, name = "？？？", text = "这位「远征长」，亲手杀死过去的伙伴是什么感受呢？" },
        { characterId = 4, name = "？？？", text = "一路上的「馈赠」，可还喜欢？" },
        { characterId = 1, name = "大狗嚼", text = "叫！你在说什么！不过只是几只拟态怪！不要在这里扰乱心智！" },
        { characterId = 2, name = "黄桃龙", text = "大魔王！受死吧！" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~开战通知：看我的利箭！" },
        { characterId = 4, name = "？？？", text = "哼哼，真的只是拟态怪吗？" },
    },
}

--- 情景 69：通关关卡1999（轮回前播放）
--- 出现条件: 通关关卡1999，在进入轮回前播放
ScenarioDialogueConfig.SCENARIO_69 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "真是有趣，你们好像越来越强了" },
        { characterId = 4, name = "？？？", text = "不过……还是请继续上路吧！" },
        { characterId = 4, name = "？？？", text = "期待更多的「礼物」吧……" },
    },
}

--- 情景 70：首次进入噩梦模式关卡4701
--- 出现条件: 首次进入关卡4701
ScenarioDialogueConfig.SCENARIO_70 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长！别做白日梦了！我们要开始出发了！" },
        { characterId = 6, name = "大狗嚼？", text = "有我在前面开路，什么士兵都不怕！嘿嘿，就是有点小激动！" },
        { characterId = 7, name = "黄桃龙？", text = "哇，今天天气真不错！最适合猎杀了！" },
        { characterId = 7, name = "黄桃龙？", text = "远征长放心！我的火焰魔法今天状态超好的！...大概！只要别再把你的头发烧掉就行！" },
        { characterId = 8, name = "叮咚鸡？", text = "...风向正常。适合行动。" },
        { characterId = 8, name = "叮咚鸡？", text = "...没带多少东西。身上全是那些冒险家的遗物，要装不下了。" },
        { characterId = 6, name = "大狗嚼？", text = "好了大家都准备好了！走吧！狩猎开始！" },
        { characterId = 1, name = "大狗嚼", text = "远征长！远征长！你怎么一直在发呆啊，叫？还没睡醒嘛？" },
        { characterId = 2, name = "黄桃龙", text = "远征长今天怎么感觉怪怪的……" },
        { characterId = 3, name = "叮咚鸡", text = "叮咚~通知：打起精神……走吧，该出发了。" },
    },
}

--- 情景 71：首次进入关卡4705（假大狗嚼独白）
--- 出现条件: 首次进入关卡4705
ScenarioDialogueConfig.SCENARIO_71 = {
    mode = "small",
    steps = {
        { characterId = 6, name = "大狗嚼？", text = "远征长……我们不是说好一起狩猎的么？" },
    },
}

--- 情景 72：首次进入关卡4805（假黄桃龙独白）
--- 出现条件: 首次进入关卡4805
ScenarioDialogueConfig.SCENARIO_72 = {
    mode = "small",
    steps = {
        { characterId = 7, name = "黄桃龙？", text = "远征长……今天又干掉了好多冒险家，可是还是没有你有意思呢……" },
    },
}

--- 情景 73：首次进入关卡4905（假叮咚鸡独白）
--- 出现条件: 首次进入关卡4905
ScenarioDialogueConfig.SCENARIO_73 = {
    mode = "small",
    steps = {
        { characterId = 8, name = "叮咚鸡？", text = "远征长……你身边的人好碍眼……" },
    },
}

return ScenarioDialogueConfig

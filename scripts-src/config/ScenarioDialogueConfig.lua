-- ============================================================================
-- ScenarioDialogueConfig.lua — 情景对话数据配置
-- 对应策划配置: docs/配置文件/剧情-情景对话.txt
-- characterId: 立绘编号 (UI_DLH_X.png 中的 X)
-- mode: "large" = 大情景(全屏覆盖), "small" = 小情景(弹窗)
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
        { characterId = 1, name = "卡琳", text = "团长！别睡懒觉啦！我们要开始出发了！" },
        { characterId = 1, name = "卡琳", text = "有我在前面开路，什么怪物都不怕！嘿嘿，就是有点小激动！" },
        { characterId = 2, name = "麦琪", text = "哇，今天天气真不错！最适合冒险了！" },
        { characterId = 2, name = "麦琪", text = "团长放心！我的火焰魔法今天状态超好的！...大概！只要别再把地图烧掉就没问题！" },
        { characterId = 3, name = "琳达", text = "...风向正常。适合赶路。" },
        { characterId = 3, name = "琳达", text = "...多带了水和干粮。不是担心你们。只是背包还有空间。" },
        { characterId = 1, name = "卡琳", text = "好了大家都准备好了！团长，你想让谁打头阵？" },
    },
}

--- 情景 2：选择卡琳后的小情景对话
--- 出现条件: 初始角色选择了卡琳（战士）
ScenarioDialogueConfig.SCENARIO_2 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "选我？好嘞！包在我身上！" },
        { characterId = 1, name = "卡琳", text = "团长就跟在我后面，前面的敌人交给我来解决！出发！" },
    },
}

--- 情景 3：选择麦琪后的小情景对话
--- 出现条件: 初始角色选择了麦琪（法师）
ScenarioDialogueConfig.SCENARIO_3 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "诶？！选我当先锋吗？没问题！" },
        { characterId = 2, name = "麦琪", text = "看我的！火焰魔法，启动！...这次绝对不会烧到自己人的！大概！" },
    },
}

--- 情景 4：选择琳达后的小情景对话
--- 出现条件: 初始角色选择了琳达（射手）
ScenarioDialogueConfig.SCENARIO_4 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "...收到。" },
        { characterId = 3, name = "琳达", text = "...我会在前方侦查。有情况的话，箭比声音先到。" },
    },
}

--- 情景 5：卡琳首通1-1 后的小情景对话（获得武器奖励：优质 练习用大剑）
--- 出现条件: 初始角色为卡琳时首通1-1
ScenarioDialogueConfig.SCENARIO_5 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "赢了！没问题的吧！团长你看到了吗，我刚才那一剑——啊等等我踩到什么了？" },
        { characterId = 1, name = "卡琳", text = "诶？！是把大剑！埋在草丛里了...虽然只是把练习用的，但比我这把好太多了！团长我能用这把吗！" },
    },
    rewards = {
        { type = "equip", templateId = "W7", quality = 2, level = 1 },
    },
}

--- 情景 6：麦琪首通1-1 后的小情景对话（获得武器奖励：优质 学徒木杖）
--- 出现条件: 初始角色为麦琪时首通1-1
ScenarioDialogueConfig.SCENARIO_6 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "炸、炸到了！等等这次居然没炸到自己？！诶，那边怪物堆里有什么东西在发光！" },
        { characterId = 2, name = "麦琪", text = "是根法杖！学徒用的木杖...比我现在这根好多了！一定是我的火球炸出来的！我果然是天才！...大概！" },
    },
    rewards = {
        { type = "equip", templateId = "W25", quality = 2, level = 1 },
    },
}

--- 情景 7：琳达首通1-1 后的小情景对话（获得武器奖励：优质 木质短弓）
--- 出现条件: 初始角色为琳达时首通1-1
ScenarioDialogueConfig.SCENARIO_7 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "...全部命中。回收箭矢时发现了一把短弓。" },
        { characterId = 3, name = "琳达", text = "...木质短弓。弦还没断，弓臂有弹性。比我现在这把顺手。放进背包了。不是特意捡的。" },
    },
    rewards = {
        { type = "equip", templateId = "W37", quality = 2, level = 1 },
    },
}

--- 情景 8：卡琳首通1-2 后的小情景对话（获得护甲奖励：优质 硬铁重衣）
--- 出现条件: 初始角色为卡琳时首通1-2
ScenarioDialogueConfig.SCENARIO_8 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "呼...这些家伙打得好疼！之前的衣服都裂了...没问题的，只是小伤！" },
        { characterId = 1, name = "卡琳", text = "啊！团长你看！那边掉了一件硬铁重衣！虽然有点重，但穿上就不怕挨打了！我试试——嘿，刚好合身！" },
    },
    rewards = {
        { type = "equip", templateId = "A25", quality = 2, level = 1 },
    },
}

--- 情景 9：麦琪首通1-2 后的小情景对话（获得护甲奖励：优质 粗布长袍）
--- 出现条件: 初始角色为麦琪时首通1-2
ScenarioDialogueConfig.SCENARIO_9 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "刚才那个火球有点大了...又把自己衣服烧了个洞...呜呜团长你不要看！" },
        { characterId = 2, name = "麦琪", text = "诶？角落里有件粗布长袍！虽然不太好看，但至少比现在这身强...而且摸着好像不怕火烧？太好了换上换上！" },
    },
    rewards = {
        { type = "equip", templateId = "A49", quality = 2, level = 1 },
    },
}

--- 情景 10：琳达首通1-2 后的小情景对话（获得护甲奖励：优质 破烂鳞甲）
--- 出现条件: 初始角色为琳达时首通1-2
ScenarioDialogueConfig.SCENARIO_10 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "...敌人比之前强。被蹭到了手臂。需要防护。" },
        { characterId = 3, name = "琳达", text = "...地上有件鳞甲。虽然破了几片，但比树皮结实。穿上了。不要看我。换衣服而已。" },
    },
    rewards = {
        { type = "equip", templateId = "A19", quality = 2, level = 1 },
    },
}

--- 情景 11：卡琳首通1-3 后的大情景对话（获得角色奖励：随机获得麦琪或琳达）
--- 出现条件: 初始角色为卡琳时首通1-3
ScenarioDialogueConfig.SCENARIO_11 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "卡琳", text = "呼——终于打完了！好厉害的怪物！话说回来...麦琪和琳达怎么还没跟上来？" },
        { characterId = 1, name = "卡琳", text = "不会是迷路了吧？还是被怪物缠住了？团长，要不我们先等等她们——啊，那边好像有动静！" },
    },
    rewards = {
        { type = "hero", heroPool = { 2, 3 } },
    },
}

--- 情景 12：麦琪首通1-3 后的大情景对话（获得角色奖励：随机获得卡琳或琳达）
--- 出现条件: 初始角色为麦琪时首通1-3
ScenarioDialogueConfig.SCENARIO_12 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "麦琪", text = "赢了赢了！...诶，等一下，卡琳和琳达呢？她们不是说跟在后面的吗？" },
        { characterId = 2, name = "麦琪", text = "呜呜，不会出什么事了吧...团长，我们在这里等一下她们好不好？...啊！那边有人过来了！" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 3 } },
    },
}

--- 情景 13：琳达首通1-3 后的大情景对话（获得角色奖励：随机获得卡琳或麦琪）
--- 出现条件: 初始角色为琳达时首通1-3
ScenarioDialogueConfig.SCENARIO_13 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "琳达", text = "...战斗结束。清点物资时发现——只有我们两个。卡琳和麦琪没有跟上。" },
        { characterId = 3, name = "琳达", text = "...不用担心，她们不会有事。在这里等一下。...有脚步声，从后方来的。" },
    },
    rewards = {
        { type = "hero", heroPool = { 1, 2 } },
    },
}

--- 情景 14：获得卡琳后的跟上对话
--- 出现条件: 通过情景11-13获得卡琳
ScenarioDialogueConfig.SCENARIO_14 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "哈...哈...终于追上你们了！刚才那群怪物太黏人了，砍了半天才脱身！没事没事，我来了就万事大吉！" },
    },
}

--- 情景 15：获得麦琪后的跟上对话
--- 出现条件: 通过情景11-13获得麦琪
ScenarioDialogueConfig.SCENARIO_15 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "等、等等我！呼...差点就追丢了！刚才有只怪突然窜出来，我一个火球把它炸飞了...顺便把路标也炸了...但我还是找到你们了！" },
    },
}

--- 情景 16：获得琳达后的跟上对话
--- 出现条件: 通过情景11-13获得琳达
ScenarioDialogueConfig.SCENARIO_16 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "...抱歉，来晚了。路上遇到了一些麻烦。已经处理好了。...从现在起，我会跟紧的。" },
    },
}

--- 情景 17：卡琳首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为卡琳时首通0104
ScenarioDialogueConfig.SCENARIO_17 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "团长！看我找到了什么！是我们丢掉的日志！" },
    },
}

--- 情景 18：麦琪首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为麦琪时首通0104
ScenarioDialogueConfig.SCENARIO_18 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "团长，日……日志找到了！差点就用火球烧掉了！" },
    },
}

--- 情景 19：琳达首通1-4 后的小情景（发现日志）
--- 出现条件: 初始角色为琳达时首通0104
ScenarioDialogueConfig.SCENARIO_19 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "嗯？这是……之前丢失的日志？" },
    },
}

--- 情景 20：卡琳首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为卡琳时首通0105
ScenarioDialogueConfig.SCENARIO_20 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 1, name = "卡琳", text = "呼呼！真是一场恶战！不过还好……倒是没受伤。" },
        { characterId = 1, name = "卡琳", text = "这边过去好像就到城镇了，我们要不去城镇里逛一逛。" },
    },
}

--- 情景 21：麦琪首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为麦琪时首通0105
ScenarioDialogueConfig.SCENARIO_21 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 2, name = "麦琪", text = "成……成功了！我们成功了！团长！" },
        { characterId = 2, name = "麦琪", text = "好累！前面好像是城镇！我们要不要去逛一逛。" },
    },
}

--- 情景 22：琳达首通1-5 后的大情景（到达城镇）
--- 出现条件: 初始角色为琳达时首通0105
ScenarioDialogueConfig.SCENARIO_22 = {
    mode = "large",
    background = "image/关卡地图/MAP_1.png",
    steps = {
        { characterId = 3, name = "琳达", text = "森之巨灵么？不过如此……" },
        { characterId = 3, name = "琳达", text = "好像看到聚集地了，去补给一下吧。" },
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

--- 情景 24：卡琳结束情景23后
--- 出现条件: 初始角色为卡琳时结束情景23
ScenarioDialogueConfig.SCENARIO_24 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "卡琳", text = "哈喽！我们是路过的冒险家，这位是我们团长！" },
        { characterId = 11, name = "卫兵", text = "又是新来的冒险家？每一位外来者必须要先去教堂后才可自由活动，请跟我来" },
    },
}

--- 情景 25：麦琪结束情景23后
--- 出现条件: 初始角色为麦琪时结束情景23
ScenarioDialogueConfig.SCENARIO_25 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "麦琪", text = "呜！我们是路过的冒险家…！是…正义的伙伴！" },
        { characterId = 11, name = "卫兵", text = "又是自诩正义伙伴的家伙么？每一位外来者必须要先去教堂后才可自由活动，请跟我来" },
    },
}

--- 情景 26：琳达结束情景23后
--- 出现条件: 初始角色为琳达时结束情景23
ScenarioDialogueConfig.SCENARIO_26 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "琳达", text = "…没有恶意，只是路过的，看看有没有什么补给。" },
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

--- 情景 28：卡琳首次离开教堂
--- 出现条件: 初始角色为卡琳时首次离开教堂
ScenarioDialogueConfig.SCENARIO_28 = {
    mode = "small",
    steps = {
        { characterId = 1,  name = "卡琳", text = "感觉好像全身充满了力量！好像变强了！" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 1,  name = "卡琳", text = "走吧团长！我们去酒馆看看！" },
    },
}

--- 情景 29：麦琪首次离开教堂
--- 出现条件: 初始角色为麦琪时首次离开教堂
ScenarioDialogueConfig.SCENARIO_29 = {
    mode = "small",
    steps = {
        { characterId = 2,  name = "麦琪", text = "团长团长！我的火焰魔法，好像更强大了！" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 2,  name = "麦琪", text = "酒馆！一定有很多好吃的吧！好想吃炸薯条、烤肉片、芝士鸡肉汉堡、甜奶昔……" },
    },
}

--- 情景 30：琳达首次离开教堂
--- 出现条件: 初始角色为琳达时首次离开教堂
ScenarioDialogueConfig.SCENARIO_30 = {
    mode = "small",
    steps = {
        { characterId = 3,  name = "琳达", text = "呼……神明吗？也许有点意思……" },
        { characterId = 11, name = "卫兵", text = "获得祝福了吗？看来不是邪恶之辈，接下来可以在城镇自由行动了。" },
        { characterId = 11, name = "卫兵", text = "如果你们想找到其他冒险伙伴的话，可以去酒馆逛逛。" },
        { characterId = 3,  name = "琳达", text = "走吧…去看看" },
    },
}

--- 情景 31：首次进入酒馆
--- 出现条件: 首次进入酒馆
ScenarioDialogueConfig.SCENARIO_31 = {
    mode = "small",
    steps = {
        { characterId = 13, name = "老板娘", text = "呀！欢迎！是新来的冒险团嘛？要不要来喝一杯呀~" },
    },
    rewards = {
        { type = "scroll", count = 10 },
    },
}

--- 情景 32：卡琳首次离开酒馆
--- 出现条件: 初始角色为卡琳时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_32 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "看来我们招募到新伙伴了！我们的团队又变得更强大了！" },
    },
}

--- 情景 33：麦琪首次离开酒馆
--- 出现条件: 初始角色为麦琪时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_33 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "交到新朋友啦！接下来要一起努力哦！" },
    },
}

--- 情景 34：琳达首次离开酒馆
--- 出现条件: 初始角色为琳达时首次离开酒馆
ScenarioDialogueConfig.SCENARIO_34 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "还不赖……希望不会拖我们后腿…" },
    },
}

--- 情景 35：卡琳首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为卡琳时首通0201
ScenarioDialogueConfig.SCENARIO_35 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 1,  name = "卡琳", text = "前方好像有声音，团长！我们快去看看发生了什么！" },
    },
}

--- 情景 36：麦琪首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为麦琪时首通0201
ScenarioDialogueConfig.SCENARIO_36 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 2,  name = "麦琪", text = "团长！有人在叫！快去看看！" },
    },
}

--- 情景 37：琳达首通2-1 后的大情景（铁匠求救）
--- 出现条件: 初始角色为琳达时首通0201
ScenarioDialogueConfig.SCENARIO_37 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "救命！有人吗？……" },
        { characterId = 3,  name = "琳达", text = "有人需要帮助……加快脚步吧" },
    },
}

--- 情景 38：卡琳首次全体阵亡失败的大情景
--- 出现条件: 初始角色为卡琳时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_38 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 1,  name = "卡琳",   text = "团长……我们就要……在这里倒下了吗？" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 1,  name = "卡琳",   text = "什么情况！团长？我怎么活过来了！？刚刚发生了什么？" },
    },
}

--- 情景 39：麦琪首次全体阵亡失败的大情景
--- 出现条件: 初始角色为麦琪时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_39 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 2,  name = "麦琪",   text = "呜呜团长！要…坚…持不住了…" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 2,  name = "麦琪",   text = "呜呜团长！我以为再也见不到你了！" },
    },
}

--- 情景 40：琳达首次全体阵亡失败的大情景
--- 出现条件: 初始角色为琳达时首次全体阵亡失败
ScenarioDialogueConfig.SCENARIO_40 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 3,  name = "琳达",   text = "团长……你先走……" },
        { characterId = 5,  name = "神秘少女", text = "（一道神秘的光闪过）" },
        { characterId = 5,  name = "神秘少女", text = "这么快就坚持不住了嘛？" },
        { characterId = 5,  name = "神秘少女", text = "没有我的允许！可不许就在这里倒下哦~ 站起来！继续前进……" },
        { characterId = 3,  name = "琳达",   text = "还……活着吗？" },
    },
}

--- 情景 41：卡琳首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为卡琳时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_41 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 1,  name = "卡琳",      text = "你认错人了吧！我们是来救你的。" },
    },
}

--- 情景 42：麦琪首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为麦琪时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_42 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 2,  name = "麦琪",      text = "什么？！喂喂！我们只是路过的冒险家啊！" },
    },
}

--- 情景 43：琳达首次进入关卡0204（铁匠误会）
--- 出现条件: 初始角色为琳达时首次进入关卡0204
ScenarioDialogueConfig.SCENARIO_43 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "愤怒的铁匠", text = "又是你们这些强盗…吃我一锤！" },
        { characterId = 3,  name = "琳达",      text = "…认错人了吧。不过你想打就陪你打……" },
    },
}

--- 情景 44：卡琳首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为卡琳时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_44 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的剑上没有黑色的气息。" },
        { characterId = 1,  name = "卡琳", text = "本来就不是啊……你一上来就打，都没给我们解释的机会" },
        { characterId = 10, name = "铁匠", text = "很抱歉，但刚刚确实有一伙儿和你们很像的……算了，先不说这个了，作为补偿请来我的铁匠铺吧，我为你们进行装备强化" },
    },
}

--- 情景 45：麦琪首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为麦琪时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_45 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的火焰魔法中没有邪恶的气息。" },
        { characterId = 2,  name = "麦琪", text = "都说了不是！你怎么就听不进去话呢！哼！挨打了吧！" },
        { characterId = 10, name = "铁匠", text = "很抱歉，但刚刚确实有一伙儿和你们很像的……算了，先不说这个了，作为补偿请来我的铁匠铺吧，我为你们进行装备强化" },
    },
}

--- 情景 46：琳达首次通关关卡0204（铁匠道歉）
--- 出现条件: 初始角色为琳达时首次通关关卡0204
ScenarioDialogueConfig.SCENARIO_46 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 10, name = "铁匠", text = "停停…等一下！你们好像确实不是刚刚那伙人，你的箭矢中没有暗黑的回响" },
        { characterId = 3,  name = "琳达", text = "暗黑的回响？这是怎么回事？" },
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

--- 情景 48：卡琳首次离开铁匠铺
--- 出现条件: 初始角色为卡琳时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_48 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "感觉不错，剑身更加锋利了！" },
    },
}

--- 情景 49：麦琪首次离开铁匠铺
--- 出现条件: 初始角色为麦琪时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_49 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "唔，法杖的魔力更加充裕了！" },
    },
}

--- 情景 50：琳达首次离开铁匠铺
--- 出现条件: 初始角色为琳达时首次离开铁匠铺
ScenarioDialogueConfig.SCENARIO_50 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "箭矢更加锋利了，还不错……" },
    },
}

--- 情景 51：卡琳首次通关关卡0205
--- 出现条件: 初始角色为卡琳时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_51 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "总感觉有些吃力了……听说城镇里新开放了一个竞技场，要不我们去看看？" },
    },
}

--- 情景 52：麦琪首次通关关卡0205
--- 出现条件: 初始角色为麦琪时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_52 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "呜！好强的怪物，咱的实力好像跟不上了，需要多磨练一下才行！" },
    },
}

--- 情景 53：琳达首次通关关卡0205
--- 出现条件: 初始角色为琳达时首次通关关卡0205
ScenarioDialogueConfig.SCENARIO_53 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "咳咳……有点吃力了，或许我们该去竞技场磨练一下。" },
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

-- 情景 55：卡琳首次通关关卡1305
-- 出现条件: 初始角色为卡琳时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_55 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "刚刚好像掉落了什么好东西！快来看看" },
    },
}

-- 情景 56：麦琪首次通关关卡1305
-- 出现条件: 初始角色为麦琪时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_56 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "这是什么！上面还有血迹！这是其他冒险家留下的遗物吗？" },
    },
}

-- 情景 57：琳达首次通关关卡1305
-- 出现条件: 初始角色为琳达时首次通关关卡1305
ScenarioDialogueConfig.SCENARIO_57 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "这是……其他冒险家留下的遗物？" },
    },
}

--- 情景 58：卡琳首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为卡琳时首通0305
ScenarioDialogueConfig.SCENARIO_58 = {
    mode = "small",
    steps = {
        { characterId = 1, name = "卡琳", text = "报告！发现一个金矿洞穴！我们可以去探查一番！" },
    },
}

--- 情景 59：麦琪首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为麦琪时首通0305
ScenarioDialogueConfig.SCENARIO_59 = {
    mode = "small",
    steps = {
        { characterId = 2, name = "麦琪", text = "哇！团长，这下面有好多的黄金呀！" },
    },
}

--- 情景 60：琳达首通3-5 后的小情景对话（副本引导）
--- 出现条件: 初始角色为琳达时首通0305
ScenarioDialogueConfig.SCENARIO_60 = {
    mode = "small",
    steps = {
        { characterId = 3, name = "琳达", text = "洞穴？可能有危险……" },
    },
}

--- 情景 61：首次进入终端关卡0999
--- 出现条件: 首次进入关卡0999
ScenarioDialogueConfig.SCENARIO_61 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "哦？有趣，竟然又抵达这里了？" },
        { characterId = 1, name = "卡琳", text = "你是？一切的元凶？" },
        { characterId = 2, name = "麦琪", text = "大魔王！受死吧！" },
        { characterId = 3, name = "琳达", text = "哼！看我的利箭" },
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
        { characterId = 1, name = "卡琳", text = "团长！别睡懒觉啦！我们要开始出发了！" },
        { characterId = 1, name = "卡琳", text = "有我在前面开路，什么怪物都不怕！嘿嘿，就是有点小激动！" },
        { characterId = 2, name = "麦琪", text = "哇，今天天气真不错！最适合冒险了！" },
        { characterId = 2, name = "麦琪", text = "团长放心！我的火焰魔法今天状态超好的！...大概！只要别再把地图烧掉就没问题！" },
        { characterId = 3, name = "琳达", text = "...风向正常。适合赶路。" },
        { characterId = 3, name = "琳达", text = "...多带了水和干粮。不是担心你们。只是背包还有空间。" },
        { characterId = 1, name = "卡琳", text = "好了大家都准备好了！走吧！一起出发！" },
    },
}

--- 情景 64：首次进入关卡2505（假卡琳遭遇）
--- 出现条件: 首次进入关卡2505
ScenarioDialogueConfig.SCENARIO_64 = {
    mode = "large",
    background = "image/关卡地图/MAP_2.png",
    steps = {
        { characterId = 6, name = "卡琳？", text = "团长……你怎么一个人走了啊？我们不是打败大魔王了吗……" },
        { characterId = 1, name = "卡琳", text = "什么情况！团长？这是……我？" },
        { characterId = 6, name = "卡琳？", text = "团长找到新的卡琳了嘛？不允许！" },
        { characterId = 6, name = "卡琳？", text = "团长只能属于我！" },
        { characterId = 1, name = "卡琳", text = "不知道你是从哪来的！团长我们上！一起击败她！" },
    },
}

--- 情景 65：首次进入关卡2705（假麦琪遭遇）
--- 出现条件: 首次进入关卡2705
ScenarioDialogueConfig.SCENARIO_65 = {
    mode = "large",
    background = "image/关卡地图/MAP_4.png",
    steps = {
        { characterId = 7, name = "麦琪？", text = "团长……人家等你好久了，我们刚刚拯救了世界哦~" },
        { characterId = 2, name = "麦琪", text = "这难道是？另一个我吗？" },
        { characterId = 7, name = "麦琪？", text = "呜呜呜！团长难道不要人家了~" },
        { characterId = 7, name = "麦琪？", text = "说好的要组一辈子旅团的！既然如此，那就死吧！" },
        { characterId = 2, name = "麦琪", text = "团长小心！她虽然和我长得很像，但绝对不是我！" },
    },
}

--- 情景 67：首次进入关卡2905（假琳达遭遇）
--- 出现条件: 首次进入关卡2905
ScenarioDialogueConfig.SCENARIO_67 = {
    mode = "large",
    background = "image/关卡地图/MAP_6.png",
    steps = {
        { characterId = 8, name = "琳达？", text = "团长……你来了，不要再……继续前进了" },
        { characterId = 3, name = "琳达", text = "嗯？什么意思？" },
        { characterId = 8, name = "琳达？", text = "只要一直前进的话，就永远都停不下来……" },
        { characterId = 8, name = "琳达？", text = "快杀了我……" },
        { characterId = 3, name = "琳达", text = "……收到" },
    },
}

--- 情景 68：首次进入困难终端关卡1999
--- 出现条件: 首次进入关卡1999
ScenarioDialogueConfig.SCENARIO_68 = {
    mode = "large",
    background = "image/关卡地图/MAP_999.png",
    steps = {
        { characterId = 4, name = "？？？", text = "又来了么？真有意思" },
        { characterId = 4, name = "？？？", text = "这位「团长」，亲手杀死过去的伙伴是什么感受呢？" },
        { characterId = 4, name = "？？？", text = "一路上的「馈赠」，可还喜欢？" },
        { characterId = 1, name = "卡琳", text = "你在说什么！不过只是几只拟态怪！不要在这里扰乱心智！" },
        { characterId = 2, name = "麦琪", text = "大魔王！受死吧！" },
        { characterId = 3, name = "琳达", text = "哼！看我的利箭" },
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
        { characterId = 6, name = "卡琳？", text = "团长！别做白日梦了！我们要开始出发了！" },
        { characterId = 6, name = "卡琳？", text = "有我在前面开路，什么士兵都不怕！嘿嘿，就是有点小激动！" },
        { characterId = 7, name = "麦琪？", text = "哇，今天天气真不错！最适合猎杀了！" },
        { characterId = 7, name = "麦琪？", text = "团长放心！我的火焰魔法今天状态超好的！...大概！只要别再把你的头发烧掉就行！" },
        { characterId = 8, name = "琳达？", text = "...风向正常。适合行动。" },
        { characterId = 8, name = "琳达？", text = "...没带多少东西。身上全是那些冒险家的遗物，要装不下了。" },
        { characterId = 6, name = "卡琳？", text = "好了大家都准备好了！走吧！狩猎开始！" },
        { characterId = 1, name = "卡琳", text = "团长！团长！你怎么一直在发呆啊，还没睡醒嘛？" },
        { characterId = 2, name = "麦琪", text = "团长今天怎么感觉怪怪的……" },
        { characterId = 3, name = "琳达", text = "打起精神……走吧，该出发了" },
    },
}

--- 情景 71：首次进入关卡4705（假卡琳独白）
--- 出现条件: 首次进入关卡4705
ScenarioDialogueConfig.SCENARIO_71 = {
    mode = "small",
    steps = {
        { characterId = 6, name = "卡琳？", text = "团长……我们不是说好一起狩猎的么？" },
    },
}

--- 情景 72：首次进入关卡4805（假麦琪独白）
--- 出现条件: 首次进入关卡4805
ScenarioDialogueConfig.SCENARIO_72 = {
    mode = "small",
    steps = {
        { characterId = 7, name = "麦琪？", text = "团长……今天又干掉了好多冒险家，可是还是没有你有意思呢……" },
    },
}

--- 情景 73：首次进入关卡4905（假琳达独白）
--- 出现条件: 首次进入关卡4905
ScenarioDialogueConfig.SCENARIO_73 = {
    mode = "small",
    steps = {
        { characterId = 8, name = "琳达？", text = "团长……你身边的人好碍眼……" },
    },
}

return ScenarioDialogueConfig

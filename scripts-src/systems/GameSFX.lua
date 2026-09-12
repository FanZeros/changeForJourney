-- ============================================================================
-- GameSFX  - 游戏音效管理器
-- 负责加载和播放所有 SFX（音效），与 GameBGM 分开管理
-- ============================================================================

local GameSFX = {}

-- ── 音效定义 ──
-- weight: 多个音效时的随机权重（等权留空即可）
local SFX_DEFS = {
    -- 点击到空白处（未命中任何按钮）
    click        = { paths = { "audio/sfx/Click.ogg"      }, gain = 0.7 },

    -- 单位受伤（随机1/2）
    hit          = { paths = { "audio/sfx/Hit1.ogg",
                                "audio/sfx/Hit2.ogg"       }, gain = 0.8 },

    -- 装备安装 / 一键穿戴
    install      = { paths = { "audio/sfx/Install.ogg"    }, gain = 0.9 },

    -- 英雄升级
    level_up     = { paths = { "audio/sfx/LevelUP.ogg"    }, gain = 1.0 },

    -- UI 通用点击（1=轻 … 4=重），外部按权重自行选择
    ui_click_1   = { paths = { "audio/sfx/UI_Click_1.ogg" }, gain = 0.6 },
    ui_click_2   = { paths = { "audio/sfx/UI_Click_2.ogg" }, gain = 0.65 },
    ui_click_3   = { paths = { "audio/sfx/UI_Click_3.ogg" }, gain = 0.7 },
    ui_click_4   = { paths = { "audio/sfx/UI_Click_4.ogg" }, gain = 0.75 },

    -- 角色界面拿起英雄卡（拖动时，随机1/2）
    ui_pick      = { paths = { "audio/sfx/UI_pick_1.ogg",
                                "audio/sfx/UI_pick_2.ogg"  }, gain = 0.7 },

    -- 角色界面将英雄卡放入槽位（随机1/2）
    ui_loosen    = { paths = { "audio/sfx/UI_loosen_1.ogg",
                                "audio/sfx/UI_loosen_2.ogg"}, gain = 0.7 },

    -- UI 动画移动（1=轻 … 4=重），外部按需选择
    ui_move_1    = { paths = { "audio/sfx/UI_move_1.ogg"  }, gain = 0.5 },
    ui_move_2    = { paths = { "audio/sfx/UI_move_2.ogg"  }, gain = 0.55 },
    ui_move_3    = { paths = { "audio/sfx/UI_move_3.ogg"  }, gain = 0.6 },
    ui_move_4    = { paths = { "audio/sfx/UI_move_4.ogg"  }, gain = 0.65 },

    -- ── 战斗投射物音效 ──
    -- 英雄攻击
    EF_ATK_1     = { paths = { "audio/battle_sfx/EF_ATK_1.ogg"  }, gain = 0.56 },
    EF_ATK_2     = { paths = { "audio/battle_sfx/EF_ATK_2.ogg"  }, gain = 0.56 },
    EF_ATK_3     = { paths = { "audio/battle_sfx/EF_ATK_3.ogg"  }, gain = 0.56 },
    EF_ATK_4     = { paths = { "audio/battle_sfx/EF_ATK_4.ogg"  }, gain = 0.56 },
    EF_ATK_5     = { paths = { "audio/battle_sfx/EF_ATK_5.ogg"  }, gain = 0.56 },
    EF_ATK_6     = { paths = { "audio/battle_sfx/EF_ATK_6.ogg"  }, gain = 0.56 },
    EF_ATK_7     = { paths = { "audio/battle_sfx/EF_ATK_7.ogg"  }, gain = 0.56 },
    EF_ATK_8     = { paths = { "audio/battle_sfx/EF_ATK_8.ogg"  }, gain = 0.56 },
    EF_ATK_9     = { paths = { "audio/battle_sfx/EF_ATK_9.ogg"  }, gain = 0.56 },
    EF_ATK_10    = { paths = { "audio/battle_sfx/EF_ATK_10.ogg" }, gain = 0.56 },
    EF_ATK_11    = { paths = { "audio/battle_sfx/EF_ATK_11.ogg" }, gain = 0.56 },
    EF_ATK_12    = { paths = { "audio/battle_sfx/EF_ATK_12.ogg" }, gain = 0.56 },
    EF_ATK_13    = { paths = { "audio/battle_sfx/EF_ATK_13.ogg" }, gain = 0.56 },
    EF_ATK_14    = { paths = { "audio/battle_sfx/EF_ATK_14.ogg" }, gain = 0.56 },
    EF_ATK_15    = { paths = { "audio/battle_sfx/EF_ATK_15.ogg" }, gain = 0.56 },
    -- 16/20/21/22/23 专用音效尚未入库，暂复用相近职业音效（避免加载缺失资源报错）
    EF_ATK_16    = { paths = { "audio/battle_sfx/EF_ATK_11.ogg" }, gain = 0.56 },  -- 洛星绘→素华斩击
    EF_ATK_20    = { paths = { "audio/battle_sfx/EF_ATK_13.ogg" }, gain = 0.56 },  -- 梅丽莎→暗影能量
    EF_ATK_21    = { paths = { "audio/battle_sfx/EF_ATK_6.ogg"  }, gain = 0.56 },  -- 亚历克斯→露娜闪电
    EF_ATK_22    = { paths = { "audio/battle_sfx/EF_ATK_6.ogg"  }, gain = 0.56 },  -- 赛拉→露娜闪电
    EF_ATK_23    = { paths = { "audio/battle_sfx/EF_ATK_15.ogg" }, gain = 0.56 },  -- 艾尔温→伊丽莎白圣光
    -- 怪物攻击
    EF_MS_1      = { paths = { "audio/battle_sfx/EF_MS_1.ogg"   }, gain = 0.56 },
    EF_MS_7      = { paths = { "audio/battle_sfx/EF_MS_7.ogg"   }, gain = 0.56 },
    EF_MS_8      = { paths = { "audio/battle_sfx/EF_MS_8.ogg"   }, gain = 0.56 },
    EF_MS_9      = { paths = { "audio/battle_sfx/EF_MS_9.ogg"   }, gain = 0.56 },
    EF_MS_13     = { paths = { "audio/battle_sfx/EF_MS_13.ogg"  }, gain = 0.56 },
    EF_MS_16     = { paths = { "audio/battle_sfx/EF_MS_16.ogg"  }, gain = 0.56 },
    EF_MS_22     = { paths = { "audio/battle_sfx/EF_MS_22.ogg"  }, gain = 0.56 },
    EF_MS_24     = { paths = { "audio/battle_sfx/EF_MS_24.ogg"  }, gain = 0.56 },
    EF_MS_27     = { paths = { "audio/battle_sfx/EF_MS_27.ogg"  }, gain = 0.56 },
    EF_MS_30     = { paths = { "audio/battle_sfx/EF_MS_30.ogg"  }, gain = 0.56 },
    EF_MS_36     = { paths = { "audio/battle_sfx/EF_MS_36.ogg"  }, gain = 0.56 },
    EF_MS_39     = { paths = { "audio/battle_sfx/EF_MS_39.ogg"  }, gain = 0.56 },
    EF_MS_43     = { paths = { "audio/battle_sfx/EF_MS_43.ogg"  }, gain = 0.56 },
    EF_MS_46     = { paths = { "audio/battle_sfx/EF_MS_46.ogg"  }, gain = 0.56 },
    EF_MS_47     = { paths = { "audio/battle_sfx/EF_MS_47.ogg"  }, gain = 0.56 },
    EF_MS_50     = { paths = { "audio/battle_sfx/EF_MS_50.ogg"  }, gain = 0.56 },
    EF_MS_53     = { paths = { "audio/battle_sfx/EF_MS_53.ogg"  }, gain = 0.56 },
    -- 转职/技能
    EF_ZY_106    = { paths = { "audio/battle_sfx/EF_ZY_106.ogg" }, gain = 0.56 },
    EF_ZY_224    = { paths = { "audio/battle_sfx/EF_ZY_224.ogg" }, gain = 0.56 },
    EF_skill_11  = { paths = { "audio/battle_sfx/EF_skill_11.ogg" }, gain = 0.56 },
    EF_skill_16  = { paths = { "audio/battle_sfx/EF_skill_11.ogg" }, gain = 0.56 }, -- 灵月飞剑→夜华斩
    EF_skill_20  = { paths = { "audio/battle_sfx/EF_ATK_13.ogg" }, gain = 0.56 }, -- 星门→能量箭
}

-- ── 内部状态 ──
---@type Scene
local scene_       = nil
---@type Node
local sfxNode_     = nil
local started_     = false
local masterGain_  = 1.0   -- 主音量乘数（由 SettingsPanel 控制）

-- 已加载的 Sound 资源：{ key -> Sound[] }
local sounds_      = {}

-- 复用 SoundSource 池（避免每次 play 新建组件）
local MAX_POOL     = 12
local pool_        = {}    -- SoundSource[]

-- ── 内部工具 ──

--- 从池中获取一个空闲的 SoundSource，若无则新建
---@return SoundSource
local function acquireSource()
    for _, src in ipairs(pool_) do
        if not src:IsPlaying() then
            return src
        end
    end
    -- 扩池
    if sfxNode_ and #pool_ < MAX_POOL then
        local src = sfxNode_:CreateComponent("SoundSource")
        src.soundType = "Effect"
        table.insert(pool_, src)
        return src
    end
    -- 池满时复用最后一个（音效打断可接受）
    return pool_[#pool_]
end

-- ── 公开 API ──

---@param scene Scene
function GameSFX.init(scene)
    scene_ = scene
end

--- 初始化并预加载全部音效
function GameSFX.start()
    if started_ then return end
    started_ = true
    if not scene_ then return end

    sfxNode_ = scene_:CreateChild("GameSFX", LOCAL)

    -- 预建若干 SoundSource 到池
    for i = 1, 6 do
        local src = sfxNode_:CreateComponent("SoundSource")
        src.soundType = "Effect"
        pool_[i] = src
    end

    -- 预加载全部音效
    for key, def in pairs(SFX_DEFS) do
        sounds_[key] = {}
        for _, path in ipairs(def.paths) do
            local snd = cache:GetResource("Sound", path)
            if snd then
                snd.looped = false
                table.insert(sounds_[key], snd)
            else
                print("[GameSFX] 加载失败: " .. path)
            end
        end
    end

    print("[GameSFX] 已启动，加载音效 " .. #(function()
        local t = {}
        for k in pairs(SFX_DEFS) do table.insert(t, k) end
        return t
    end)() .. " 种")
end

--- 播放指定音效
---@param key string  音效键（见 SFX_DEFS）
function GameSFX.play(key)
    if not started_ then return end
    local def = SFX_DEFS[key]
    local list = sounds_[key]
    if not def or not list or #list == 0 then
        print("[GameSFX] 未知音效或未加载: " .. tostring(key))
        return
    end
    -- 随机选一个
    local snd = list[math.random(1, #list)]
    local src = acquireSource()
    src.gain = def.gain * masterGain_
    src:Play(snd)
end

--- 播放 UI 通用点击音（轻/中/重 由外部传 level 1~4，默认 2）
---@param level? number 1=轻 2=中轻 3=中重 4=重
function GameSFX.playUIClick(level)
    local keys = { "ui_click_1", "ui_click_2", "ui_click_3", "ui_click_4" }
    local key = keys[math.max(1, math.min(4, level or 2))]
    GameSFX.play(key)
end

--- 播放 UI 移动音（level 1~4，默认 2）
---@param level? number
function GameSFX.playUIMove(level)
    local keys = { "ui_move_1", "ui_move_2", "ui_move_3", "ui_move_4" }
    local key = keys[math.max(1, math.min(4, level or 2))]
    GameSFX.play(key)
end

--- 设置主音量乘数（0~1），立即生效
---@param gain number
function GameSFX.setMasterGain(gain)
    masterGain_ = math.max(0, math.min(1, gain))
end

---@return number
function GameSFX.getMasterGain()
    return masterGain_
end

function GameSFX.stop()
    for _, src in ipairs(pool_) do
        src:Stop()
    end
    if sfxNode_ then sfxNode_:Remove() end
    sfxNode_  = nil
    pool_     = {}
    sounds_   = {}
    started_  = false
end

return GameSFX

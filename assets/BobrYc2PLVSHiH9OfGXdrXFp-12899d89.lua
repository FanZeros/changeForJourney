-- ============================================================================
-- CharacterSchema.lua — 角色数据字段统一定义（全项目唯一，中心化单例）
-- 路径: scripts/shared/schemas/CharacterSchema.lua
--
-- 职责:
--   1. 角色数据字段的注册中心（零硬编码，全靠子系统注册）
--   2. 提供 RegisterSubsystemFields() 让子系统 Schema 注入字段
--   3. PDM / PlayerStore 遍历 Fields 动态构建注册表
--
-- 字段定义格式（模块级 JSON 模式）:
--   fieldKey = {
--     pdmKey     = "ModXxx",                       -- PDM 内部键名
--     type       = "json",                          -- "scalar"|"string"|"json"
--     scope      = "server"|"global",               -- 作用域
--     persist    = { via="cloud", cloudKey="mod_xxx" } | false,
--     getDefault = function() return {} end,        -- 默认值工厂
--     onLoad     = function(data) end,              -- 加载后修正（可选）
--     desc       = "说明",
--   }
--
-- 持久化策略:
--   via="cloud" → serverCloud scores（JSON 模块 blob）
--   false       → sync-only，仅运行时同步，不持久化
--
-- 与 SaveManager 的数据兼容:
--   fieldKey 必须与 ModuleRegistry.modules[i].name 一致
--   cloudKey 必须与 ModuleRegistry.modules[i].key 一致
--   → serverCloud 存储格式完全相同，迁移期两者共存
-- ============================================================================

local CharacterSchema = {}

--- 全局字段表（由各子系统 Schema 注册填充，初始为空）
CharacterSchema.Fields = {}

-- ========================================================================
-- 子系统 Schema 注册机制
-- ========================================================================

--- 注册子系统 Schema 字段到 CharacterSchema.Fields
--- PDM / PlayerStore 遍历 Fields 时自动包含所有已注册的子系统字段
---@param schemaName string 子系统名称（日志用）
---@param fields table<string, table> 与 Fields 格式一致的字段表
function CharacterSchema.RegisterSubsystemFields(schemaName, fields)
    local count = 0
    for fieldKey, def in pairs(fields) do
        if CharacterSchema.Fields[fieldKey] then
            print(string.format(
                "[CharacterSchema] WARN: RegisterSubsystemFields(%s) 字段冲突 key=%s，跳过",
                schemaName, fieldKey))
        else
            CharacterSchema.Fields[fieldKey] = def
            count = count + 1
        end
    end
    print(string.format(
        "[CharacterSchema] RegisterSubsystemFields: %s -> %d fields merged",
        schemaName, count))
end

-- ========================================================================
-- 子系统 Schema 注册区
-- ========================================================================

local ProfileSchema   = require("shared.profile.ProfileSchema")
local PlayerSchema    = require("shared.player.PlayerSchema")
local CurrencySchema  = require("shared.currency.CurrencySchema")
local HeroesSchema    = require("shared.heroes.HeroesSchema")
local EquipmentSchema = require("shared.equipment.EquipmentSchema")
local BattleSchema    = require("shared.battle.BattleSchema")
local ArenaSchema     = require("shared.arena.ArenaSchema")
local LootboxSchema   = require("shared.lootbox.LootboxSchema")
local TalentsSchema   = require("shared.talents.TalentsSchema")
local SigninSchema    = require("shared.signin.SigninSchema")
local MailSchema      = require("shared.mail.MailSchema")
local RedeemSchema    = require("shared.redeem.RedeemSchema")
local TaskSchema      = require("shared.task.TaskSchema")
local SessionSchema   = require("shared.session.SessionSchema")
local MarketSchema       = require("shared.market.MarketSchema")
local QuotaSchema        = require("shared.quota.QuotaSchema")
local SlotEnhanceSchema  = require("shared.slotenhance.SlotEnhanceSchema")
local TavernSchema       = require("shared.tavern.TavernSchema")
local RelicSchema        = require("shared.relic.RelicSchema")
local ArtifactSchema     = require("shared.artifact.ArtifactSchema")
local DungeonSchema      = require("shared.dungeon.DungeonSchema")
local ChallengerSchema   = require("shared.challenger.ChallengerSchema")

CharacterSchema.RegisterSubsystemFields("Profile",   ProfileSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Player",    PlayerSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Currency",  CurrencySchema.Fields)
CharacterSchema.RegisterSubsystemFields("Heroes",    HeroesSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Equipment", EquipmentSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Battle",    BattleSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Arena",     ArenaSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Lootbox",   LootboxSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Talents",   TalentsSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Signin",    SigninSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Mail",      MailSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Redeem",    RedeemSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Task",      TaskSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Session",   SessionSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Market",      MarketSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Quota",       QuotaSchema.Fields)
CharacterSchema.RegisterSubsystemFields("SlotEnhance", SlotEnhanceSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Tavern",     TavernSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Relic",      RelicSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Artifact",   ArtifactSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Dungeon",    DungeonSchema.Fields)
CharacterSchema.RegisterSubsystemFields("Challenger", ChallengerSchema.Fields)

-- ========================================================================
-- 工具函数
-- ========================================================================

--- 按作用域过滤字段
---@param scope string "server"|"global"
---@return table<string, table>
function CharacterSchema.GetFieldsByScope(scope)
    local result = {}
    for key, def in pairs(CharacterSchema.Fields) do
        if def.scope == scope then
            result[key] = def
        end
    end
    return result
end

--- 按持久化后端过滤
---@param via string|false "cloud"|false
---@return table<string, table>
function CharacterSchema.GetFieldsByPersist(via)
    local result = {}
    for key, def in pairs(CharacterSchema.Fields) do
        if via == false then
            if def.persist == false then result[key] = def end
        elseif type(def.persist) == "table" and def.persist.via == via then
            result[key] = def
        end
    end
    return result
end

--- 获取 pdmKey -> fieldKey 反向映射
---@return table<string, string>
function CharacterSchema.GetPdmKeyMap()
    local result = {}
    for fieldKey, def in pairs(CharacterSchema.Fields) do
        result[def.pdmKey] = fieldKey
    end
    return result
end

--- 对指定模块数据执行 onLoad 修正（cjson key 类型、数组稀疏等）
--- 客户端收到推送数据后也需要调用，确保与服务端 PDM mergeModuleData 一致
---@param fieldKey string
---@param data table
function CharacterSchema.applyOnLoad(fieldKey, data)
    if type(data) ~= "table" then return end
    local def = CharacterSchema.Fields[fieldKey]
    if def and def.onLoad then
        local ok, err = pcall(def.onLoad, data)
        if not ok then
            print("[CharacterSchema] applyOnLoad error for " .. fieldKey .. ": " .. tostring(err))
        end
    end
end

--- 获取 cloudKey -> fieldKey[] 分组映射（用于 serverCloud 批量操作）
---@return table<string, string[]>
function CharacterSchema.GetCloudKeyGroups()
    local result = {}
    for fieldKey, def in pairs(CharacterSchema.Fields) do
        if type(def.persist) == "table" and def.persist.cloudKey then
            local ck = def.persist.cloudKey
            if not result[ck] then result[ck] = {} end
            result[ck][#result[ck] + 1] = fieldKey
        end
    end
    return result
end

return CharacterSchema

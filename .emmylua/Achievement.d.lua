---@meta

---@alias AchievementOperation "unlock"|"increment"
---@alias AchievementType "normal"|"platinum"

---@class AchievementResult 成就写入成功结果
---@field operation AchievementOperation 本次完成的操作
---@field achievementId string 普通成就 achievementId；白金成就透传宿主值，可能为空字符串
---@field achievementName string 成就展示名称
---@field achievementType AchievementType 成就类型
---@field currentStep integer 当前累计步数；unlock 固定为 0，increment 为当前累计进度

---@class AchievementError 成就写入失败信息
---@field achievementId string 失败请求对应的普通成就 achievementId
---@field message string 错误描述

---@class AchievementCallbacks 成就异步回调
---@field onSuccess? fun(result: AchievementResult)
---@field onFailure? fun(code: integer, error: AchievementError)

---@class SDK 客户端 SDK 全局对象
local SDK = {}

--- 控制宿主原生成就解锁提示。
---@param enabled boolean
function SDK:SetAchievementToastEnabled(enabled) end

--- 打开当前登录用户的原生成就页面。
function SDK:ShowAchievements() end

--- 解锁一个单步普通成就。
---@param achievementId string 长度 1..40，仅允许字母、数字、- 和 _
function SDK:UnlockAchievement(achievementId) end

--- 增加普通进度成就的步数。
---@param achievementId string 长度 1..40，仅允许字母、数字、- 和 _
---@param steps integer 本次增加步数，范围 1..INT_MAX（客户端 Native 接口使用 int）
function SDK:IncrementAchievement(achievementId, steps) end

--- 注册当前 Lua 状态的成就 listener；再次注册会替换已有 listener。
---@param listener AchievementCallbacks
function SDK:RegisterAchievementListener(listener) end

--- 移除当前成就 listener。
function SDK:UnregisterAchievementListener() end

---@type SDK
sdk = {}

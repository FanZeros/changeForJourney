-- ============================================================================
-- ChurchResults - ChurchPage.onActionResult 抽出（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local state = deps.state
    local ANIM = deps.ANIM
    local CHAR_SLOT = deps.CHAR_SLOT
    local getProtocol = deps.getProtocol
    local ArtifactPanel = deps.ArtifactPanel
    local CharacterPanel = deps.CharacterPanel
    local SpineCardEffect = deps.SpineCardEffect
    local clearPowerCache = deps.clearPowerCache

    local function refreshTownBadge()
        local okBN, BN = pcall(require, "ui.hud.BottomNav")
        if okBN and BN and BN.refreshTownBadge then
            BN.refreshTownBadge()
        end
    end

    local function setFloat(text)
        state.floatText = text
        state.floatTextX = 540
        state.floatTextY = 980
        state.floatTextTime = time.elapsedTime
    end

    local function onActionResult(data)
        -- 转职结果与教堂开关无关（转职页在右侧栏角色详情）
        local ProtocolEarly = getProtocol()
        if data.action == ProtocolEarly.ACTION_TYPES.ADVANCE_CLASS
            or data.action == ProtocolEarly.ACTION_TYPES.RESET_CLASS
            or (data.branchId and data.advLevel) then
            -- 继续往下处理
        elseif not state.open then
            return
        end
        if not data.success and not state.open then return end

        -- 神器装配结果
        local Protocol = getProtocol()
        if data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP and data.success then
            setFloat("神器安装成功，下波战斗生效")
            ArtifactPanel.onArtifactEquipResult(true)
        elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP and data.success then
            setFloat("神器已卸下，下波战斗生效")
        elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE and data.success then
            setFloat("神器合成成功")
        elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL and data.success then
            setFloat("神器置换成功")
            local okPanel, panel = pcall(require, "ui.church.ChurchArtifactPanel")
            if okPanel and panel and panel.onArtifactRerollResult then
                panel.onArtifactRerollResult(true)
            end
        elseif data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE and data.success then
            setFloat("神器洗练成功")
            local okPanel, panel = pcall(require, "ui.church.ChurchArtifactPanel")
            if okPanel and panel and panel.onArtifactRefineValueResult then
                panel.onArtifactRefineValueResult(true, data.artifactId)
            end
        elseif (data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE) and not data.success then
            if data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP then
                ArtifactPanel.onArtifactEquipResult(false)
            end
            setFloat(data.reason or "神器操作失败")
        end

        if data.action == Protocol.ACTION_TYPES.ARTIFACT_DRAW
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_EQUIP
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_UNEQUIP
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_MERGE
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_REROLL
            or data.action == Protocol.ACTION_TYPES.ARTIFACT_REFINE_VALUE then
            refreshTownBadge()
        end

        -- 转职成功结果（由 ADVANCE_CLASS handler 返回，含 branchId + advLevel + branchName）
        -- 转职页已迁到右侧栏角色详情，结果处理与教堂打开状态无关
        if data.branchId and data.advLevel then
            print("[ChurchPage] 转职成功: " .. tostring(data.branchName)
                .. " heroId=" .. tostring(data.heroId)
                .. " advLevel=" .. tostring(data.advLevel))
            -- 同步 advBranch 到 CharacterPanel，使转职天赋在当前会话立即生效
            if data.heroId then
                CharacterPanel.setHeroAdvBranch(data.heroId, data.branchId, data.advLevel)
            end
            -- 清除战斗力缓存，下次绘制会重新计算
            clearPowerCache()
            -- 刷新城镇Tab角标（转职后可能不再有可转职英雄）
            refreshTownBadge()
            -- 转职成功 Spine 特效：播放在右侧栏角色详情的立绘位置
            local okDetail, CharacterDetail = pcall(require, "ui.character.detail.CharacterDetail")
            if okDetail and CharacterDetail.getHeroId and CharacterDetail.getHeroId() == data.heroId then
                CharacterDetail.markPowerDirty()
                SpineCardEffect.playJobChange(540, 447)
            end
            local ClassChange = require("ui.church.ChurchClassChange")
            ClassChange.showFloat("转职成功")
        end

        -- 重置转职成功结果（由 RESET_CLASS handler 返回）
        if data.action == Protocol.ACTION_TYPES.RESET_CLASS and data.success and data.heroId then
            print("[ChurchPage] 重置转职成功 heroId=" .. tostring(data.heroId)
                .. " removedOffhand=" .. tostring(data.removedOffhandSeq))
            CharacterPanel.resetHeroAdvBranch(data.heroId)
            -- 清除战斗力缓存
            clearPowerCache()
            -- 刷新城镇Tab角标
            refreshTownBadge()
            local okDetail, CharacterDetail = pcall(require, "ui.character.detail.CharacterDetail")
            if okDetail and CharacterDetail.markPowerDirty then
                CharacterDetail.markPowerDirty()
            end
            require("ui.church.ChurchClassChange").showFloat("已重置转职")
        end
    end

    return { onActionResult = onActionResult }
end

return M

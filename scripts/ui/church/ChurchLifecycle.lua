-- ============================================================================
-- ChurchLifecycle - 教堂 open/close/forceClose/动画进度（玩法不变）
-- ============================================================================

local M = {}

function M.bind(deps)
    local state = deps.state
    local ANIM = deps.ANIM
    local easeOutCubic = deps.easeOutCubic
    local easeInCubic = deps.easeInCubic
    local ArtifactPanel = deps.ArtifactPanel
    local ArtifactDrawPanel = deps.ArtifactDrawPanel
    local ensureInit = deps.ensureInit
    local getOnCloseCallback = deps.getOnCloseCallback
    local setOnCloseCallback = deps.setOnCloseCallback
    local getOnOpenCallback = deps.getOnOpenCallback
    local setOnOpenCallback = deps.setOnOpenCallback

    local function open()
        if not ensureInit() then
            print("[ChurchPage] open before init, skip")
            return
        end
        state.open = true
        state.closing = false
        state.openTime = time.elapsedTime
        require("systems.GameSFX").playUIMove(1)
        do
            local okTP, TP = pcall(require, "ui.church.talent.TalentPage")
            if okTP and TP and TP.isOpen and TP.isOpen() and TP.forceClose then
                TP.forceClose()
            end
        end
        state.tab = "shenqi"
        state.tabFrom = "shenqi"
        state.tabSwitchTime = 0
        ArtifactPanel.reset()
        ArtifactDrawPanel.reset()
        print("[ChurchPage] 打开教堂")
    end

    local function close()
        if state.closing then return end
        state.closing = true
        state.closeTime = time.elapsedTime
        print("[ChurchPage] 关闭教堂（动画）")
    end

    local function isOpen()
        return state.open
    end

    local function forceClose()
        if not state.open then return end
        print("[ChurchPage] forceClose: 跳过动画强制关闭 (closing=" .. tostring(state.closing) .. ")")
        state.open = false
        state.closing = false
    end

    local function getAnimProgress()
        if not state.open then return 0 end
        if state.closing then
            local elapsed = time.elapsedTime - state.closeTime
            local rawT = math.min(1.0, elapsed / ANIM.CLOSE_DUR)
            return 1 - easeInCubic(rawT)
        else
            local elapsed = time.elapsedTime - state.openTime
            local rawT = math.min(1.0, elapsed / ANIM.OPEN_DUR)
            return easeOutCubic(rawT)
        end
    end

    return {
        open = open,
        close = close,
        isOpen = isOpen,
        forceClose = forceClose,
        getAnimProgress = getAnimProgress,
        setOnCloseCallback = setOnCloseCallback,
        setOnOpenCallback = setOnOpenCallback,
        getOnCloseCallback = getOnCloseCallback,
        getOnOpenCallback = getOnOpenCallback,
    }
end

return M

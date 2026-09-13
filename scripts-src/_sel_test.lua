-- _sel_test.lua — 临时探针: 打开选关页验证渲染（validate-test 模式, 不入库）
---@diagnostic disable: undefined-global
local BTP = require("ui.BattleTriPage")

V.atFrame(150, function()
    BTP.toggleStageSelect()
end)

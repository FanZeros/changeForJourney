-- 竖屏开始画面已移除。保留空模块，避免 240db7b 的 require 在启动时找不到文件而黑屏。
local StartScreen = {}

function StartScreen.init() end
function StartScreen.reopen() end
function StartScreen.skipForReconnect() end
function StartScreen.isOpen() return false end
function StartScreen.update() end
function StartScreen.draw() end
function StartScreen.handleInput() return false end

return StartScreen

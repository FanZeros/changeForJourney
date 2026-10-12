-- 空模块占位：保留该文件，避免 require 在启动时找不到文件而黑屏。
local StartScreen = {}

function StartScreen.init() end
function StartScreen.reopen() end
function StartScreen.skipForReconnect() end
function StartScreen.isOpen() return false end
function StartScreen.update() end
function StartScreen.draw() end
function StartScreen.handleInput() return false end

return StartScreen

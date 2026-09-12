--[[
================================================================================
  UIScaler.lua - UI 缩放适配组件
================================================================================

【用途】
  提供基于设计分辨率的 UI 适配组件，支持两种缩放模式。

【缩放模式】
  CONTAIN_MODE（默认）：
    - 类比 CSS background-size: contain
    - 设计内容完全可见，宽高比不同时有额外可见区域（黑边）
    - 公式：scaleFactor = min(scaleX, scaleY)

  COVER_MODE：
    - 类比 CSS background-size: cover
    - 填满整个屏幕，宽高比不同时设计内容会被裁剪
    - 公式：scaleFactor = max(scaleX, scaleY)
    - 建议配合 clipChildren = true 使用

【使用方法】
  require "LuaScripts/Utilities/UIScaler"

  function Start()
      -- CONTAIN 模式（默认）
      local uiScaler = CreateUIScaler(nil, 1920, 1080)
      
      -- COVER 模式（填满屏幕，配合 clipChildren）
      local uiScaler = CreateUIScaler(nil, 1920, 1080, COVER_MODE, true)
      
      -- 访问设计容器，添加 UI
      local button = Button:new()
      uiScaler.designContainer:AddChild(button)
  end

  function HandleRender()
      -- NVG 绘制时使用
      nvgBeginFrame(ctx, uiScaler.scaledWidth, uiScaler.scaledHeight, uiScaler.scaleFactor)
      nvgTranslate(ctx, uiScaler.designOriginX, uiScaler.designOriginY)
      -- ...
  end

【属性说明】
  设计参数（初始化时设置）：
    - designWidth, designHeight: 设计分辨率
    - scaleMode: 缩放模式（CONTAIN_MODE 或 COVER_MODE）

  只读计算属性（自动更新）：
    - deviceWidth, deviceHeight: 物理分辨率（设备实际像素）
    - scaledWidth, scaledHeight: 逻辑分辨率（物理分辨率 / scaleFactor）
    - scaleFactor: 缩放因子
    - designOriginX, designOriginY: 设计区域原点（基于逻辑分辨率，用于 NVG 偏移）
    - designContainer: 设计区域 UI 容器

================================================================================
--]]

--------------------------------------------------------------------------------
-- 缩放模式常量
--------------------------------------------------------------------------------

---@alias ScaleMode integer

---CONTAIN 模式：设计内容完全可见，可能有额外区域（类比 CSS contain）
---@type ScaleMode
CONTAIN_MODE = 0

---COVER 模式：填满屏幕，设计内容可能被裁剪（类比 CSS cover）
---@type ScaleMode
COVER_MODE = 1

---@class UIScaler : LuaScriptObject
---@field designWidth number 设计宽度
---@field designHeight number 设计高度
---@field scaleMode ScaleMode 缩放模式（CONTAIN_MODE 或 COVER_MODE）
---@field deviceWidth number 物理分辨率宽度（只读）
---@field deviceHeight number 物理分辨率高度（只读）
---@field scaledWidth number 逻辑分辨率宽度（物理分辨率/scaleFactor，只读）
---@field scaledHeight number 逻辑分辨率高度（物理分辨率/scaleFactor，只读）
---@field scaleFactor number 缩放因子（只读）
---@field designOriginX number 设计区域原点X（基于逻辑分辨率，用于NVG偏移，只读）
---@field designOriginY number 设计区域原点Y（基于逻辑分辨率，用于NVG偏移，只读）
---@field designContainer UIElement|nil 设计区域UI容器
---@field clipChildren boolean 是否裁剪设计区域外的内容
UIScaler = ScriptObject()

UIScaler.designWidth = 1920
UIScaler.designHeight = 1080
UIScaler.scaleMode = CONTAIN_MODE
UIScaler.deviceWidth = 0
UIScaler.deviceHeight = 0
UIScaler.scaledWidth = 0
UIScaler.scaledHeight = 0
UIScaler.scaleFactor = 1.0
UIScaler.designOriginX = 0
UIScaler.designOriginY = 0
UIScaler.designContainer = nil
UIScaler.clipChildren = false

---初始化 UIScaler
---@param designW number 设计宽度
---@param designH number 设计高度
---@param scaleMode? ScaleMode 缩放模式，默认 CONTAIN_MODE
---@param clipChildren? boolean 是否裁剪设计区域外的内容，默认 false
function UIScaler:Init(designW, designH, scaleMode, clipChildren)
    self.designWidth = designW or 1920
    self.designHeight = designH or 1080
    self.scaleMode = scaleMode or CONTAIN_MODE
    self.clipChildren = clipChildren == true
    
    -- 创建设计区域容器
    self:CreateDesignContainer()
    
    -- 首次更新
    self:UpdateScale()
end

---创建设计区域容器
function UIScaler:CreateDesignContainer()
    if self.designContainer then
        self.designContainer:Remove()
    end
    
    self.designContainer = UIElement:new()
    self.designContainer:SetClipChildren(self.clipChildren)
    ui.root:AddChild(self.designContainer)
end

---更新缩放计算（内部方法，ScreenMode 变化时自动调用）
function UIScaler:UpdateScale()
    local graphics = GetGraphics()
    
    -- 设备分辨率（物理像素）
    self.deviceWidth = graphics:GetWidth()
    self.deviceHeight = graphics:GetHeight()
    
    -- 计算缩放因子
    local scaleX = self.deviceWidth / self.designWidth
    local scaleY = self.deviceHeight / self.designHeight
    
    if self.scaleMode == COVER_MODE then
        -- COVER：取大的，填满屏幕，内容可能被裁剪
        self.scaleFactor = math.max(scaleX, scaleY)
    else
        -- CONTAIN（默认）：取小的，内容完全可见，可能有额外区域
        self.scaleFactor = math.min(scaleX, scaleY)
    end
    
    -- 缩放后尺寸（虚拟分辨率，UI坐标系）
    self.scaledWidth = self.deviceWidth / self.scaleFactor
    self.scaledHeight = self.deviceHeight / self.scaleFactor
    
    -- 设计区域原点（基于虚拟分辨率的居中偏移，用于 NVG）
    self.designOriginX = (self.scaledWidth - self.designWidth) / 2
    self.designOriginY = (self.scaledHeight - self.designHeight) / 2
    
    -- 设置 UI 系统缩放
    ui:SetScale(Vector2(self.scaleFactor, self.scaleFactor))
    
    -- 更新设计区域容器
    if self.designContainer then
        self.designContainer:SetPosition(math.floor(self.designOriginX), math.floor(self.designOriginY))
        self.designContainer:SetSize(math.floor(self.designWidth), math.floor(self.designHeight))
    end
    
    -- 强制布局更新
    ui.root:UpdateLayout()
end

---设置新的设计分辨率
---@param designW number 设计宽度
---@param designH number 设计高度
function UIScaler:SetDesignSize(designW, designH)
    self.designWidth = designW
    self.designHeight = designH
    self:UpdateScale()
end

---设置缩放模式
---@param mode ScaleMode 缩放模式（CONTAIN_MODE 或 COVER_MODE）
function UIScaler:SetScaleMode(mode)
    self.scaleMode = mode
    self:UpdateScale()
end

---设置是否裁剪设计区域外的内容
---@param clip boolean 是否裁剪
function UIScaler:SetClipChildren(clip)
    self.clipChildren = clip
    if self.designContainer then
        self.designContainer:SetClipChildren(clip)
    end
end

---ScriptObject 生命周期：启动
function UIScaler:Start()
    -- 使用闭包捕获 self，因为字符串函数名只能查找全局函数
    self:SubscribeToEvent("ScreenMode", function(eventType, eventData)
        self:UpdateScale()
    end)
end

---ScriptObject 生命周期：停止
function UIScaler:Stop()
    if self.designContainer then
        self.designContainer:Remove()
        self.designContainer = nil
    end
end

--------------------------------------------------------------------------------
-- 便捷函数
--------------------------------------------------------------------------------

---@type Node|nil 内部用于挂载 ScriptObject 的 Node（parentNode 为 nil 时自动创建）
local _uiScalerNode = nil

---创建并初始化 UIScaler
---@param node Node|nil 挂载目标节点，传 nil 则内部自动创建
---@param designW number 设计宽度
---@param designH number 设计高度
---@param scaleMode? ScaleMode 缩放模式，默认 CONTAIN_MODE
---@param clipChildren? boolean 是否裁剪设计区域外的内容，默认 false
---@return UIScaler
function CreateUIScaler(node, designW, designH, scaleMode, clipChildren)
    if node == nil then
        if _uiScalerNode == nil then
            _uiScalerNode = Node()
        end
        node = _uiScalerNode
    end
    
    local scriptInstance = node:GetScriptObject("UIScaler")
    if scriptInstance == nil then
        scriptInstance = node:CreateScriptObject("UIScaler")
    end
    
    scriptInstance:Init(designW, designH, scaleMode, clipChildren)
    return scriptInstance
end


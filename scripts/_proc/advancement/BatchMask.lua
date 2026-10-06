-- 换面人基础职5与二转217–220；只向父绘图闭包发出主体几何。
-- 不创建Image、不读旧PNG、不画底板、不写图片、不安装；统一底板由父生成器负责。
-- 职业DNA：尖眉面甲、隐蔽皮革、旧铜扣件与短刃；不是技能复制/传播流程图。
-- 五种轮廓：尖顶兜帽 / 低垂兜帽横刃 / 三面伪装套装 / 钩刃腕甲 / 同型交叉双刃。
-- 280设计空间中心139.5，所有实际发出几何及描边必须在半径110内。
-- 主协调冻结模块后统一进行真实烘焙、审核、安装、LSP及官方build。

---@class BatchMaskDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field ellipse fun(cx: number, cy: number, rx: number, ry: number, top: number[], bottom?: number[])
---@field arc fun(cx: number, cy: number, rx: number, ry: number, firstDeg: number, lastDeg: number, width: number, color: number[])
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field star fun(cx: number, cy: number, radius: number, color: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

-- 复用109的完整前景面甲，以及110的暗铁内甲＋留存半壳；不复制几何表。
-- 通过绘图闭包筛选已有面甲组，变换顶点后交给本模块的安全接口。
-- 109的借取轨迹、影面与颊侧箭形；110的剥离甲片、散落碎片全部不发出。
-- 分组按完整轮廓特征及显式结束轮廓，不按绘图调用序号截断。
-- 这些轮廓指纹冻结于本次ReviewMask源；内部增减line/polygon不影响分组。
-- 若源轮廓改变，assert拒绝继续，让主协调重新冻结而非悄悄错选。
local CONTOURS = {
    full = "109,102;137,110;156,129;161,157;151,184;133,212;112,227;91,212;73,184;61,154;65,128;83,111",
    fullEnd = "144,192;158,199;156,210",
    inner = "128,66;151,78;173,101;180,132;172,166;155,197;127,221;103,206;83,179;73,149;76,116;93,88",
    shell = "126,69;139,82;135,102;145,120;132,140;140,155;127,174;135,192;124,219;103,203;86,177;76,148;80,118;96,91",
    shellEnd = "173,84;193,95;215,118;221,147;210,177;185,199;171,189;179,162;173,146;180,126;167,109",
}
local reviewMask = require("_proc.advancement.ReviewMask")

---@param points number[][]
---@return string
local function contourFingerprint(points)
    local values = {}
    for _, p in ipairs(points) do
        values[#values + 1] = string.format("%g,%g", p[1], p[2])
    end
    return table.concat(values, ";")
end

---@param d BatchMaskDraw
---@param id integer
return function(d, id)
    assert(id == 5 or id == 217 or id == 218 or id == 219 or id == 220,
        "BatchMask只绘制5/217/218/219/220，禁止覆盖109/110")
    local CENTER, LIMIT = 139.5, 110
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    -- 不以裁剪掩盖越界。父emblem最宽描边为7，顶点检查预留半宽3.5。
    -- 安全圆为凸集：线段、多边形和贝塞尔控制点通过即可覆盖其内部路径。
    ---@param x number
    ---@param y number
    ---@param padding number
    local function pointInside(x, y, padding)
        assert(padding >= 0 and padding < LIMIT, "BatchMask描边宽度无效")
        local dx, dy, room = x - CENTER, y - CENTER, LIMIT - padding
        assert(dx * dx + dy * dy <= room * room,
            "BatchMask主体含描边越过半径110：id=" .. id .. "，x=" .. x .. "，y=" .. y)
    end

    ---@param points number[][]
    ---@param padding number
    local function pathInside(points, padding)
        for _, p in ipairs(points) do pointInside(p[1], p[2], padding) end
    end

    ---@param points number[][]
    ---@param top number[]
    ---@param bottom number[]|nil
    ---@param opacity number|nil
    local function polygon(points, top, bottom, opacity)
        pathInside(points, 0)
        d.polygon(points, top, bottom, opacity)
    end

    ---@param points number[][]
    ---@param top number[]|nil
    ---@param bottom number[]|nil
    local function emblem(points, top, bottom)
        pathInside(points, 3.5)
        d.emblem(points, top or BONE, bottom or GOLD)
    end

    ---@param x0 number
    ---@param y0 number
    ---@param x1 number
    ---@param y1 number
    ---@param width number
    ---@param color number[]
    ---@param opacity number|nil
    local function line(x0, y0, x1, y1, width, color, opacity)
        pointInside(x0, y0, width * 0.5)
        pointInside(x1, y1, width * 0.5)
        d.line(x0, y0, x1, y1, width, color, opacity)
    end

    ---@param points number[][]
    ---@param width number
    ---@param color number[]
    ---@param closed boolean|nil
    ---@param opacity number|nil
    local function stroke(points, width, color, closed, opacity)
        pathInside(points, width * 0.5)
        d.stroke(points, width, color, closed, opacity)
    end

    ---@param cx number
    ---@param cy number
    ---@param rx number
    ---@param ry number
    ---@param top number[]
    ---@param bottom number[]|nil
    local function ellipse(cx, cy, rx, ry, top, bottom)
        assert(rx > 0 and ry > 0, "BatchMask椭圆半径必须为正")
        -- 以包围矩形四角保守检查，父椭圆像素必在此范围内。
        pointInside(cx - rx, cy - ry, 0)
        pointInside(cx + rx, cy - ry, 0)
        pointInside(cx + rx, cy + ry, 0)
        pointInside(cx - rx, cy + ry, 0)
        d.ellipse(cx, cy, rx, ry, top, bottom)
    end

    ---@param x number
    ---@param y number
    local function rivet(x, y)
        ellipse(x, y, 4, 4, DARK)
        ellipse(x - 0.45, y - 0.55, 2.55, 2.55, BONE, GOLD)
    end

    ---@param points number[][]
    ---@param sourceX number
    ---@param sourceY number
    ---@param targetX number
    ---@param targetY number
    ---@param scale number
    ---@param angle number
    ---@return number[][]
    local function transformed(points, sourceX, sourceY, targetX, targetY, scale, angle)
        local result = {}
        local cosine, sine = math.cos(angle), math.sin(angle)
        for _, p in ipairs(points) do
            local x, y = (p[1] - sourceX) * scale, (p[2] - sourceY) * scale
            result[#result + 1] = { targetX + x * cosine - y * sine,
                targetY + x * sine + y * cosine }
        end
        return result
    end

    ---@param sourceId integer
    ---@param x number
    ---@param y number
    ---@param scale number
    ---@param degrees number
    local function face(sourceId, x, y, scale, degrees)
        assert(sourceId == 109 or sourceId == 110, "BatchMask面甲来源只能是109/110")
        assert(scale > 0 and scale <= 1, "BatchMask面甲缩放无效")
        local sourceX, sourceY = 111, 164
        if sourceId == 110 then sourceX, sourceY = 128, 144 end
        local angle = degrees * math.pi / 180
        local active, panels, ended = false, 0, false

        ---@param points number[][]
        ---@return number[][]
        local function project(points)
            return transformed(points, sourceX, sourceY, x, y, scale, angle)
        end

        ---@type AdvancementReviewMaskDraw
        local proxy = {
            DARK = DARK, GOLD = GOLD, BONE = BONE, SHADE = SHADE,
            polygon = function(points, top, bottom, opacity)
                if active then polygon(project(points), top, bottom, opacity) end
            end,
            stroke = function(points, width, color, closed, opacity)
                if active then stroke(project(points), width * scale, color, closed, opacity) end
            end,
            line = function(x0, y0, x1, y1, width, color, opacity)
                if active then
                    local p = project({ { x0, y0 }, { x1, y1 } })
                    line(p[1][1], p[1][2], p[2][1], p[2][2], width * scale, color, opacity)
                end
            end,
            ellipse = function(cx, cy, rx, ry, top, bottom)
                if active then
                    -- 当前选中的面甲不含椭圆；仍为复用闭包提供完整合法接口。
                    -- 如上游添加椭圆，转为48点轮廓以保持旋转后的椭圆形状。
                    local points = {}
                    for i = 0, 47 do
                        local a = i * math.pi / 24
                        points[#points + 1] = { cx + rx * math.cos(a), cy + ry * math.sin(a) }
                    end
                    polygon(project(points), top, bottom)
                end
            end,
            curve = function(points, c1x, c1y, c2x, c2y, endx, endy)
                if active then
                    -- curve只扩充来源路径，不直接绘制；随后stroke再统一投影。
                    pathInside(project({ points[#points], { c1x, c1y },
                        { c2x, c2y }, { endx, endy } }), 0)
                    d.curve(points, c1x, c1y, c2x, c2y, endx, endy)
                end
            end,
            emblem = function(points, top, bottom)
                local fingerprint = contourFingerprint(points)
                local start = fingerprint == CONTOURS.full
                local finish = fingerprint == CONTOURS.fullEnd
                if sourceId == 110 then
                    start = fingerprint == CONTOURS.inner or fingerprint == CONTOURS.shell
                    finish = fingerprint == CONTOURS.shellEnd
                end
                if start then
                    -- 110先画内甲再画留存半壳，允许相邻两个命名主体组。
                    active = true
                    panels = panels + 1
                    -- 父emblem描边固定7，不随缩放改变；留粗暗边保证小图可读。
                    emblem(project(points), top, bottom)
                elseif finish then
                    assert(active, "BatchMask面甲结束轮廓缺少前置主体")
                    active = false
                    ended = true
                else
                    assert(not active, "BatchMask面甲组出现未冻结的emblem轮廓")
                end
            end,
        }
        reviewMask(proxy, sourceId)
        -- 完整开始/结束轮廓和组数同时验证，内部加线不影响边界；变形显式拒绝。
        local expected = sourceId == 109 and 1 or 2
        assert(panels == expected and ended and not active,
            "BatchMask复用面甲组失配：来源=" .. sourceId)
    end

    if id == 5 then
        -- 换面人：尖顶皮革兜帽内藏完整骨白面甲，单枚铜扣收住下垂帽襟。
        -- 对应基础换面：观察并借用敌方护甲克制，短暂换位后破甲；不画复制箭头。
        local hood = { { 139.5, 45 }, { 107, 66 }, { 90, 95 }, { 81, 133 },
            { 79, 194 }, { 104, 213 }, { 139.5, 228 }, { 175, 213 },
            { 200, 194 }, { 198, 133 }, { 189, 95 }, { 172, 66 } }
        emblem(hood, GOLD, SHADE)
        polygon({ { 139.5, 53 }, { 168, 73 }, { 183, 100 }, { 190, 136 },
            { 192, 188 }, { 172, 204 }, { 139.5, 219 }, { 107, 204 },
            { 87, 188 }, { 89, 136 }, { 96, 100 }, { 111, 73 } }, SHADE, DARK)
        -- 左帽边是一整块宽亮皮革，右侧深暗；不用碎线铺满面甲周围。
        polygon({ { 136, 60 }, { 111, 79 }, { 100, 108 }, { 95, 153 },
            { 97, 183 }, { 111, 197 }, { 102, 200 }, { 91, 188 },
            { 93, 130 }, { 105, 88 } }, GOLD, SHADE)
        polygon({ { 149, 70 }, { 173, 90 }, { 182, 126 }, { 186, 185 },
            { 167, 200 }, { 177, 167 }, { 174, 122 } }, DARK)
        polygon({ { 139.5, 79 }, { 170, 93 }, { 185, 125 }, { 181, 163 },
            { 166, 190 }, { 139.5, 207 }, { 111, 190 }, { 97, 163 },
            { 94, 125 }, { 109, 95 } }, DARK)
        face(109, 139.5, 138, 0.9, 0)
        -- 前帽沿压过面甲额角，读作藏在兜帽里的装备，而非漂浮的人脸。
        emblem({ { 139.5, 67 }, { 166, 83 }, { 178, 103 }, { 157, 94 },
            { 139.5, 84 }, { 121, 94 }, { 102, 105 }, { 113, 84 } }, GOLD, SHADE)
        line(117, 82, 137, 70, 2.8, BONE)
        stroke({ { 88, 143 }, { 88, 190 }, { 109, 207 } }, 3, GOLD, false)
        -- 仅两片宽帽襟与一个实体喉扣，不扩展成人物肩胸或额外徽记。
        emblem({ { 93, 181 }, { 112, 189 }, { 137, 210 }, { 124, 221 },
            { 105, 211 }, { 90, 196 } }, GOLD, SHADE)
        emblem({ { 186, 181 }, { 167, 189 }, { 143, 210 }, { 154, 221 },
            { 175, 211 }, { 190, 196 } }, SHADE, DARK)
        emblem({ { 132, 205 }, { 147, 205 }, { 152, 215 }, { 147, 226 },
            { 132, 226 }, { 127, 215 } }, BONE, GOLD)
        polygon({ { 136, 210 }, { 144, 210 }, { 144, 221 }, { 136, 221 } }, DARK)
        line(111, 197, 126, 211, 2.8, BONE)
        return
    end

    if id == 217 then
        -- 静面（借面→二转）：低垂深兜帽、闭口遮面和横置潜伏短刃。
        -- 精确技能：5秒未受攻击，目标护甲削弱20%→40%；装备语义是隐蔽静候。
        -- 宽帽檐与水平短刃构成扁宽轮廓，绝不画计时刻度或护甲百分比。
        emblem({ { 112, 60 }, { 141, 54 }, { 164, 65 }, { 184, 87 },
            { 192, 122 }, { 202, 181 }, { 181, 204 }, { 140, 216 },
            { 102, 205 }, { 77, 184 }, { 85, 123 }, { 91, 88 } }, GOLD, SHADE)
        polygon({ { 112, 69 }, { 140, 62 }, { 159, 72 }, { 176, 93 },
            { 183, 128 }, { 192, 181 }, { 177, 194 }, { 139, 208 },
            { 105, 196 }, { 87, 182 }, { 93, 125 }, { 100, 94 } }, SHADE, DARK)
        polygon({ { 106, 88 }, { 142, 82 }, { 174, 99 }, { 181, 140 },
            { 170, 174 }, { 142, 196 }, { 112, 178 }, { 96, 142 } }, DARK)
        face(109, 143, 143, 0.76, -8)
        -- 压低的整片帽檐遮住额头，不画眼珠或光点。
        emblem({ { 101, 87 }, { 128, 78 }, { 153, 85 }, { 176, 106 },
            { 184, 126 }, { 151, 112 }, { 130, 105 }, { 96, 118 } }, GOLD, SHADE)
        polygon({ { 100, 111 }, { 129, 98 }, { 151, 107 }, { 177, 119 },
            { 173, 128 }, { 150, 118 }, { 128, 113 }, { 103, 124 } }, DARK)
        stroke({ { 106, 90 }, { 128, 83 }, { 151, 90 }, { 171, 108 } }, 3.2, BONE, false)
        -- 一整张皮革口罩覆住面甲下部，保留上部尖眉双眼孔作为共同DNA。
        emblem({ { 107, 157 }, { 134, 162 }, { 169, 154 }, { 178, 170 },
            { 166, 188 }, { 143, 198 }, { 117, 185 }, { 99, 171 } }, GOLD, SHADE)
        polygon({ { 110, 164 }, { 134, 171 }, { 171, 162 }, { 169, 171 },
            { 140, 182 }, { 113, 174 } }, SHADE, DARK)
        line(113, 164, 132, 169, 3.2, BONE)
        line(140, 169, 168, 162, 3.2, GOLD)
        -- 横刃为完整器物：一侧握柄、宽护手、另一侧单尖短刀，不画动势轨迹。
        emblem({ { 67, 200 }, { 91, 205 }, { 94, 216 }, { 87, 224 },
            { 66, 212 }, { 59, 208 } }, GOLD, SHADE)
        polygon({ { 66, 205 }, { 86, 209 }, { 88, 216 }, { 65, 211 } }, DARK)
        emblem({ { 94, 196 }, { 105, 194 }, { 112, 220 }, { 103, 225 },
            { 97, 214 } }, BONE, GOLD)
        emblem({ { 108, 201 }, { 185, 194 }, { 220, 199 }, { 198, 214 },
            { 115, 218 } }, BONE, GOLD)
        polygon({ { 113, 209 }, { 191, 203 }, { 213, 199 }, { 195, 209 },
            { 118, 215 } }, GOLD, SHADE)
        line(117, 204, 183, 198, 2.7, BONE)
        rivet(99, 207)
        return
    end

    if id == 218 then
        -- 千面（借面→二转）：铜轭、皮革披襟与三张实际可替换的仪式面甲。
        -- 精确技能：5秒未受攻击，攻速+40%；器物表达密探快速换装，非三次复制。
        -- 两侧面甲朝外悬挂，中央面甲朝正面；层级、朝向和承托件都真实可见。
        emblem({ { 98, 66 }, { 177, 66 }, { 197, 83 }, { 190, 99 },
            { 171, 87 }, { 109, 87 }, { 87, 101 }, { 80, 84 } }, GOLD, SHADE)
        polygon({ { 103, 72 }, { 174, 72 }, { 187, 83 }, { 176, 84 },
            { 108, 81 }, { 93, 91 }, { 88, 84 } }, BONE, GOLD)
        emblem({ { 94, 147 }, { 64, 169 }, { 78, 193 }, { 111, 211 },
            { 139.5, 224 }, { 169, 211 }, { 202, 193 }, { 217, 169 },
            { 186, 147 }, { 166, 156 }, { 114, 157 } }, GOLD, SHADE)
        polygon({ { 83, 174 }, { 98, 163 }, { 121, 168 }, { 133, 208 },
            { 111, 200 }, { 87, 187 } }, SHADE, DARK)
        polygon({ { 180, 165 }, { 198, 174 }, { 190, 186 }, { 167, 200 },
            { 148, 210 }, { 161, 172 } }, DARK)
        face(109, 91, 124, 0.61, -24)
        face(109, 187, 124, 0.61, 24)
        -- 两枚皮革挂带明确连接面甲与铜轭，避免读成漂浮镜像或灵魂分身。
        emblem({ { 86, 77 }, { 98, 76 }, { 105, 96 }, { 99, 106 },
            { 89, 100 } }, GOLD, SHADE)
        emblem({ { 180, 76 }, { 192, 77 }, { 189, 100 }, { 179, 106 },
            { 173, 96 } }, GOLD, SHADE)
        rivet(94, 89)
        rivet(183, 89)
        -- 中央大面甲只取109已有主面，尺寸约88×110，不用千张小面纹。
        face(109, 139.5, 162, 0.88, 0)
        emblem({ { 126, 91 }, { 153, 91 }, { 158, 102 }, { 149, 112 },
            { 131, 112 }, { 121, 102 } }, GOLD, SHADE)
        polygon({ { 132, 96 }, { 147, 96 }, { 147, 106 }, { 132, 106 } }, DARK)
        line(131, 95, 149, 95, 2.5, BONE)
        -- 宽披襟下方只留两根斜缝，与完整正脸共存，不形成光环或机关箭头。
        line(92, 185, 114, 204, 3.1, GOLD)
        line(188, 185, 165, 204, 3.1, GOLD)
        return
    end

    if id == 219 then
        -- 致命面（剥面→二转）：一把厚背钩刃与斜向护腕，半壳面甲固定在腕铠上。
        -- 精确技能：暴击立刻填满攻击进度，每轮最多一次；用处决突袭装备表达。
        -- 不画暴击星芒、进度环、血滴或从尸体传播的机制图解。
        emblem({ { 87, 153 }, { 111, 145 }, { 139, 160 }, { 157, 188 },
            { 148, 214 }, { 121, 227 }, { 92, 217 }, { 76, 195 } }, GOLD, SHADE)
        polygon({ { 91, 160 }, { 110, 154 }, { 131, 166 }, { 145, 188 },
            { 139, 207 }, { 120, 217 }, { 97, 209 }, { 85, 192 } }, SHADE, DARK)
        -- 两片大腕甲斜向叠接，钩刃根部由实体护手固定。
        emblem({ { 85, 166 }, { 107, 158 }, { 136, 177 }, { 143, 190 },
            { 122, 198 }, { 98, 185 } }, BONE, GOLD)
        polygon({ { 104, 170 }, { 131, 181 }, { 135, 188 }, { 123, 192 },
            { 105, 182 } }, GOLD, SHADE)
        emblem({ { 82, 190 }, { 99, 186 }, { 129, 204 }, { 130, 218 },
            { 117, 222 }, { 95, 213 } }, GOLD, SHADE)
        line(88, 194, 113, 209, 3.2, BONE)
        -- 钩刃的内缺口大于20px，粗背与向内回钩在64px仍保留形状区别。
        local hook = { { 130, 167 }, { 142, 137 }, { 148, 107 }, { 163, 82 },
            { 183, 67 }, { 205, 65 }, { 218, 78 }, { 211, 96 },
            { 199, 107 }, { 184, 105 }, { 189, 93 }, { 204, 86 },
            { 196, 79 }, { 179, 90 }, { 171, 113 }, { 170, 136 },
            { 156, 165 }, { 144, 180 } }
        emblem(hook, BONE, GOLD)
        polygon({ { 139, 166 }, { 152, 137 }, { 157, 109 }, { 172, 86 },
            { 186, 76 }, { 196, 74 }, { 204, 79 }, { 193, 84 },
            { 176, 101 }, { 164, 140 }, { 151, 167 }, { 145, 174 } }, GOLD, SHADE)
        polygon({ { 180, 91 }, { 196, 79 }, { 204, 86 }, { 189, 93 },
            { 184, 105 }, { 178, 113 } }, DARK)
        stroke({ { 137, 159 }, { 149, 132 }, { 154, 107 }, { 168, 85 },
            { 185, 72 }, { 202, 70 } }, 3.2, BONE, false)
        stroke({ { 215, 80 }, { 208, 94 }, { 198, 102 }, { 189, 102 } }, 3.2, GOLD, false)
        emblem({ { 114, 148 }, { 124, 142 }, { 169, 168 }, { 172, 179 },
            { 159, 187 }, { 117, 162 } }, GOLD, SHADE)
        line(122, 149, 164, 173, 3.2, BONE)
        -- 保留110的错齿半壳结构，不把剥下碎片或第二张脸搬到腕甲周围。
        face(110, 116, 188, 0.4, -28)
        rivet(88, 176)
        rivet(145, 197)
        return
    end

    -- 双面（剥面→二转）：两把几何与材质完全相同的短刃，握柄分别通向两侧。
    -- 精确技能只允许同型副手武器，明确不画一刀一钩或一刀一盾。
    -- 上方半壳面甲来自110，和交叉双刃共享职业面甲DNA，但不占双持主体。
    emblem({ { 112, 156 }, { 89, 177 }, { 96, 204 }, { 139.5, 226 },
        { 182, 204 }, { 190, 177 }, { 166, 156 } }, GOLD, SHADE)
    polygon({ { 112, 170 }, { 128, 179 }, { 132, 212 }, { 103, 197 },
        { 98, 180 } }, SHADE, DARK)
    polygon({ { 169, 170 }, { 181, 180 }, { 174, 197 }, { 146, 212 },
        { 151, 179 } }, DARK)
    face(110, 139.5, 112, 0.62, 0)
    -- 额前皮革扣只是一枚悬挂装备的矩形扣件，不补角冠、星芒或文字。
    emblem({ { 127, 57 }, { 151, 57 }, { 154, 65 }, { 148, 74 },
        { 132, 74 }, { 125, 65 } }, GOLD, SHADE)
    line(131, 61, 148, 61, 2.7, BONE)

    ---@param degrees number
    local function twinDagger(degrees)
        local angle = degrees * math.pi / 180
        ---@param points number[][]
        ---@return number[][]
        local function project(points)
            return transformed(points, 0, 0, CENTER, 145, 1, angle)
        end
        -- 两次调用完全同一刀身、护手、握柄及尾帽，没有按左右交换武器类型。
        emblem(project({ { -8, 35 }, { 8, 35 }, { 8, 73 }, { 5, 82 },
            { -5, 82 }, { -8, 73 } }), GOLD, SHADE)
        polygon(project({ { -4, 41 }, { 4, 41 }, { 4, 74 }, { -4, 74 } }), DARK)
        stroke(project({ { -5, 48 }, { 5, 48 } }), 3.5, GOLD, false)
        stroke(project({ { -5, 61 }, { 5, 61 } }), 3.5, GOLD, false)
        emblem(project({ { -11, 77 }, { 11, 77 }, { 12, 86 }, { 7, 91 },
            { -7, 91 }, { -12, 86 } }), BONE, GOLD)
        emblem(project({ { 0, -96 }, { 11, -73 }, { 12, 16 }, { 7, 28 },
            { -7, 28 }, { -12, 16 }, { -11, -73 } }), BONE, GOLD)
        polygon(project({ { 0, -87 }, { 7, -70 }, { 8, 13 }, { 3, 23 },
            { 0, 23 } }), GOLD, SHADE)
        stroke(project({ { -5, -65 }, { -6, 9 }, { -3, 20 } }), 3, BONE, false)
        emblem(project({ { -24, 28 }, { -18, 22 }, { 18, 22 }, { 24, 28 },
            { 19, 36 }, { -19, 36 } }), GOLD, SHADE)
        stroke(project({ { -17, 27 }, { 17, 27 } }), 3.2, BONE, false)
    end
    twinDagger(-38)
    twinDagger(38)
end

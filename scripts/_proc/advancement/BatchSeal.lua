-- 封门人基础职与二转主体；基于父生成器及 Review 系列的 CPU 图元接口。
-- 只绘制 1 / 201–204，已审核的 101 / 102 不在本模块权限内。
-- 底板、像素、降采样、PNG 输出和安装全部由父生成器负责。
-- 五种独立护具轮廓：尖底门盾 / 封带塔盾 / 闭面护盔 / 落闸栅门 / 斜向臂铠。
-- 只用暗铁、旧铜、骨白；不用人物、技能流程、箭头、爱心或附加职业徽记。

---@class BatchSealDraw
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

---@param d BatchSealDraw
---@param id integer
return function(d, id)
    assert(id == 1 or id == 201 or id == 202 or id == 203 or id == 204,
        "BatchSeal只允许1/201/202/203/204，禁止重绘101/102")
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE
    local CENTER, LIMIT = 139.5, 108

    -- 不靠裁剪隐藏越界。所有发出图元在调用父闭包前检查，含圆头描边。
    -- 圆盘是凸集：多边形顶点及贝塞尔控制点合规即保证内部路径合规。
    -- 本地 emblem 的最宽描边为7；这里固定按半宽3.5预留，底板仍由父负责。
    ---@param x number
    ---@param y number
    ---@param padding number
    local function pointInside(x, y, padding)
        assert(padding >= 0 and padding < LIMIT, "BatchSeal无效描边宽度")
        local dx, dy, room = x - CENTER, y - CENTER, LIMIT - padding
        assert(dx * dx + dy * dy <= room * room,
            "BatchSeal主体或描边超出半径108：id=" .. id .. "，x=" .. x .. "，y=" .. y)
    end

    ---@param points number[][]
    ---@param padding number
    local function pathInside(points, padding)
        for _, p in ipairs(points) do pointInside(p[1], p[2], padding) end
    end

    -- 本地平滑填充只影响这五个主体，父底板与其他职业仍保持原绘制。
    -- 铜主面保持足够亮度；骨白用于可在64px读出的受光面，不铺满全部甲片。
    ---@param a number[]
    ---@param b number[]
    ---@param t number
    ---@return number[]
    local function mix(a, b, t)
        return { a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
    end
    local COPPER = mix(BONE, GOLD, 0.55)
    local LIGHT = mix(BONE, GOLD, 0.18)
    local EDGE = mix(GOLD, SHADE, 0.62)

    -- Sutherland–Hodgman按水平半平面裁切；交点始终在线段内。
    -- 相邻带复用同一个边界值，父even-odd填充的低y边界包含、高y边界排除，
    -- 不靠微量扩张补缝，因此半透明不会在带边界重复合成。
    ---@param points number[][]
    ---@param boundary number
    ---@param keepBelow boolean
    ---@return number[][]
    local function clipHorizontal(points, boundary, keepBelow)
        local result = {}
        if #points == 0 then return result end
        local previous = points[#points]
        local previousInside = keepBelow and previous[2] <= boundary
            or not keepBelow and previous[2] >= boundary
        for _, current in ipairs(points) do
            local currentInside = keepBelow and current[2] <= boundary
                or not keepBelow and current[2] >= boundary
            if currentInside ~= previousInside then
                local t = (boundary - previous[2]) / (current[2] - previous[2])
                result[#result + 1] = {
                    previous[1] + (current[1] - previous[1]) * t, boundary }
            end
            if currentInside then result[#result + 1] = current end
            previous, previousInside = current, currentInside
        end
        return result
    end

    ---@param points number[][]
    ---@param top number[]
    ---@param bottom number[]|nil
    ---@param opacity number|nil
    local function polygon(points, top, bottom, opacity)
        pathInside(points, 0)
        if #points < 3 then return end
        if not bottom then
            d.polygon(points, top, nil, opacity)
            return
        end
        local y0, y1 = points[1][2], points[1][2]
        for _, p in ipairs(points) do
            y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
        end
        local height = y1 - y0
        if height <= 0 then return end
        -- 560母图每行0.5设计单位一带；薄形状至少一带，不增加噪声。
        local count = math.max(1, math.ceil(height * 2))
        local boundaries = {}
        for i = 0, count do boundaries[i + 1] = y0 + height * i / count end
        boundaries[1], boundaries[count + 1] = y0, y1
        for i = 1, count do
            local lower, upper = boundaries[i], boundaries[i + 1]
            local piece = clipHorizontal(clipHorizontal(points, lower, false), upper, true)
            local twiceArea = 0
            if #piece >= 3 then
                local previous = piece[#piece]
                for _, current in ipairs(piece) do
                    twiceArea = twiceArea + previous[1] * current[2] - current[1] * previous[2]
                    previous = current
                end
                if math.abs(twiceArea) > 0.00000001 then
                    local color = mix(top, bottom, ((lower + upper) * 0.5 - y0) / height)
                    d.polygon(piece, color, nil, opacity)
                end
            end
        end
    end

    ---@param points number[][]
    ---@param top number[]|nil
    ---@param bottom number[]|nil
    local function emblem(points, top, bottom)
        pathInside(points, 3.5)
        d.stroke(points, 7, DARK, true)
        polygon(points, top or BONE, bottom or GOLD)
        d.stroke(points, 1.5, GOLD, true)
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
        assert(rx > 0 and ry > 0, "BatchSeal椭圆半径必须大于0")
        -- 用包围矩形四角做保守检查，比只查椭圆四轴端点更严格。
        pointInside(cx - rx, cy - ry, 0)
        pointInside(cx + rx, cy - ry, 0)
        pointInside(cx + rx, cy + ry, 0)
        pointInside(cx - rx, cy + ry, 0)
        -- 48点内接椭圆改走本地平滑polygon，不再触发父ellipse的磨损乘子。
        local points = {}
        for i = 0, 47 do
            local angle = math.pi * 2 * i / 48
            points[#points + 1] = { cx + math.cos(angle) * rx, cy + math.sin(angle) * ry }
        end
        polygon(points, top, bottom)
    end

    ---@param x number
    ---@param y number
    ---@param radius number|nil
    local function rivet(x, y, radius)
        local r = radius or 3.8
        ellipse(x, y, r, r, DARK)
        ellipse(x - 0.45, y - 0.55, r * 0.64, r * 0.64, BONE, GOLD)
        line(x - r * 0.28, y - r * 0.27, x + r * 0.3, y - r * 0.27, 1, BONE)
    end

    if id == 1 then
        -- 原尖底门盾轮廓保持；包边、门扉和门铰重画成真正厚甲。
        local shield = { { 139.5, 52 }, { 176, 68 }, { 200, 97 }, { 200, 156 },
            { 186, 189 }, { 159, 217 }, { 139.5, 229 }, { 120, 217 },
            { 93, 189 }, { 79, 156 }, { 79, 97 }, { 103, 68 } }
        emblem(shield, LIGHT, GOLD)
        -- 左上宽倒角保留缩略骨白识别，下右暗壁留在原盾沿内。
        polygon({ { 139.5, 55 }, { 171, 70 }, { 168, 77 }, { 139.5, 64 },
            { 111, 78 }, { 92, 103 }, { 93, 155 }, { 106, 182 },
            { 128, 204 }, { 139.5, 214 }, { 139.5, 223 }, { 121, 213 },
            { 97, 186 }, { 83, 155 }, { 83, 99 }, { 106, 71 } }, BONE, COPPER)
        polygon({ { 175, 72 }, { 196, 99 }, { 196, 155 }, { 182, 186 },
            { 156, 214 }, { 140, 224 }, { 140, 216 }, { 151, 207 },
            { 175, 181 }, { 187, 155 }, { 187, 103 }, { 169, 78 } }, EDGE, SHADE)
        polygon({ { 139.5, 64 }, { 168, 78 }, { 187, 103 }, { 186, 155 },
            { 173, 182 }, { 151, 204 }, { 139.5, 212 }, { 128, 204 },
            { 106, 182 }, { 93, 155 }, { 92, 103 }, { 111, 78 } }, DARK)
        emblem({ { 111, 82 }, { 134, 72 }, { 134, 202 }, { 117, 188 },
            { 100, 158 }, { 99, 105 } }, COPPER, GOLD)
        polygon({ { 111, 84 }, { 129, 76 }, { 129, 84 }, { 113, 92 },
            { 105, 108 }, { 106, 155 }, { 122, 184 }, { 127, 190 },
            { 120, 184 }, { 103, 156 }, { 102, 106 } }, BONE, LIGHT)
        polygon({ { 114, 95 }, { 127, 87 }, { 127, 178 }, { 119, 172 },
            { 110, 153 }, { 109, 111 } }, LIGHT, COPPER)
        polygon({ { 128, 84 }, { 134, 80 }, { 134, 198 }, { 128, 191 } }, GOLD, EDGE)
        emblem({ { 145, 72 }, { 168, 82 }, { 180, 105 }, { 179, 158 },
            { 162, 188 }, { 145, 202 } }, COPPER, EDGE)
        polygon({ { 148, 78 }, { 166, 87 }, { 172, 101 }, { 167, 102 },
            { 161, 93 }, { 148, 87 } }, LIGHT, COPPER)
        -- 右扉中央不再填黑洞；铜正面和狭窄暗侧壁分别占面。
        polygon({ { 150, 89 }, { 164, 97 }, { 171, 109 }, { 170, 153 },
            { 158, 177 }, { 150, 185 } }, COPPER, GOLD)
        polygon({ { 171, 105 }, { 177, 109 }, { 176, 157 }, { 160, 187 },
            { 148, 198 }, { 148, 188 }, { 160, 175 }, { 170, 153 } }, EDGE, SHADE)
        line(139.5, 82, 139.5, 196, 8, DARK)
        polygon({ { 133, 88 }, { 136, 85 }, { 136, 190 }, { 133, 187 } }, BONE, COPPER)
        -- 原两枚侧铰保留，重画压板顶面、下厚边及短铰轴。
        for _, y in ipairs({ 119, 158 }) do
            emblem({ { 86, y - 7 }, { 108, y - 7 }, { 112, y },
                { 108, y + 7 }, { 86, y + 7 } }, COPPER, GOLD)
            polygon({ { 89, y - 6 }, { 106, y - 6 }, { 109, y - 2 },
                { 91, y - 2 } }, BONE, LIGHT)
            polygon({ { 89, y + 2 }, { 109, y + 2 }, { 106, y + 6 },
                { 89, y + 6 } }, EDGE, SHADE)
            line(87, y - 4, 87, y + 4, 6, DARK)
            line(86, y - 4, 86, y + 3, 3.2, COPPER)
            rivet(98, y, 3.5)
            rivet(184, y, 3.5)
        end
        -- 尖底同包边是一体铸件，不另叠徽记。
        polygon({ { 112, 193 }, { 139.5, 216 }, { 139.5, 223 },
            { 121, 213 } }, LIGHT, COPPER)
        polygon({ { 145, 209 }, { 171, 188 }, { 158, 211 },
            { 145, 220 } }, GOLD, EDGE)
        return
    end

    if id == 201 then
        -- 原方底塔盾与单根斜封带不改轮廓，重画框沿、带身和嵌合扣座。
        local tower = { { 97, 60 }, { 181, 60 }, { 197, 76 }, { 197, 194 },
            { 183, 215 }, { 97, 215 }, { 82, 194 }, { 82, 77 } }
        emblem(tower, COPPER, GOLD)
        polygon({ { 98, 63 }, { 179, 63 }, { 188, 74 }, { 181, 77 },
            { 175, 72 }, { 103, 72 }, { 91, 85 }, { 91, 190 },
            { 101, 207 }, { 98, 211 }, { 86, 192 }, { 86, 79 } }, BONE, COPPER)
        polygon({ { 187, 78 }, { 194, 78 }, { 194, 193 }, { 181, 211 },
            { 99, 211 }, { 104, 205 }, { 178, 205 }, { 187, 188 } }, EDGE, SHADE)
        polygon({ { 103, 74 }, { 175, 74 }, { 184, 85 }, { 184, 188 },
            { 177, 200 }, { 103, 200 }, { 95, 188 }, { 95, 85 } }, DARK)
        emblem({ { 101, 86 }, { 111, 79 }, { 134, 79 }, { 134, 195 },
            { 103, 195 }, { 101, 186 } }, COPPER, GOLD)
        polygon({ { 107, 89 }, { 116, 84 }, { 126, 84 }, { 126, 189 },
            { 108, 189 } }, LIGHT, COPPER)
        polygon({ { 128, 84 }, { 134, 84 }, { 134, 192 }, { 128, 192 } }, GOLD, EDGE)
        emblem({ { 145, 79 }, { 169, 79 }, { 177, 87 }, { 177, 186 },
            { 174, 195 }, { 145, 195 } }, COPPER, EDGE)
        polygon({ { 149, 84 }, { 167, 84 }, { 172, 90 }, { 167, 93 },
            { 149, 90 } }, LIGHT, COPPER)
        polygon({ { 149, 95 }, { 166, 95 }, { 166, 188 }, { 149, 188 } }, COPPER, GOLD)
        polygon({ { 168, 94 }, { 174, 94 }, { 174, 187 },
            { 169, 192 }, { 168, 185 } }, EDGE, SHADE)
        line(139.5, 83, 139.5, 192, 7, DARK)
        -- 上下护沿的顶面与下壁用宽色面替换旧亮线；盾内保留窄暗台阶。
        emblem({ { 96, 66 }, { 181, 66 }, { 188, 75 }, { 180, 84 },
            { 98, 84 }, { 90, 76 } }, LIGHT, GOLD)
        polygon({ { 98, 68 }, { 178, 68 }, { 183, 73 }, { 179, 76 },
            { 99, 76 }, { 94, 73 } }, BONE, LIGHT)
        polygon({ { 95, 78 }, { 183, 78 }, { 179, 83 }, { 99, 83 } }, GOLD, EDGE)
        polygon({ { 100, 84 }, { 178, 84 }, { 178, 88 }, { 100, 88 } }, DARK)
        emblem({ { 92, 192 }, { 184, 192 }, { 186, 200 }, { 178, 209 },
            { 101, 209 }, { 91, 200 } }, COPPER, EDGE)
        polygon({ { 95, 194 }, { 181, 194 }, { 183, 199 },
            { 98, 199 }, { 94, 197 } }, LIGHT, COPPER)
        polygon({ { 97, 202 }, { 182, 202 }, { 176, 208 }, { 103, 208 } }, EDGE, SHADE)
        -- 带下接触阴影只在原带右下附近，带宽与轴线保持。
        polygon({ { 110, 90 }, { 181, 180 }, { 183, 191 },
            { 174, 193 }, { 104, 98 } }, DARK)
        emblem({ { 92, 85 }, { 105, 75 }, { 184, 178 }, { 189, 197 },
            { 175, 203 }, { 88, 99 } }, COPPER, GOLD)
        polygon({ { 94, 86 }, { 104, 79 }, { 180, 179 }, { 177, 183 },
            { 101, 87 }, { 94, 94 } }, BONE, LIGHT)
        polygon({ { 101, 92 }, { 106, 86 }, { 176, 179 }, { 182, 194 },
            { 176, 196 } }, LIGHT, COPPER)
        polygon({ { 91, 98 }, { 175, 200 }, { 186, 196 }, { 183, 188 },
            { 177, 192 }, { 98, 97 } }, GOLD, EDGE)
        -- 原封扣由暗凹槽包住铜压舌，不靠单斜线冒充结构。
        emblem({ { 126, 119 }, { 142, 112 }, { 157, 132 }, { 155, 145 },
            { 139, 152 }, { 125, 132 } }, COPPER, EDGE)
        polygon({ { 128, 120 }, { 141, 115 }, { 146, 122 }, { 132, 127 } }, BONE, COPPER)
        polygon({ { 133, 126 }, { 143, 122 }, { 151, 133 }, { 149, 140 },
            { 139, 145 }, { 131, 134 } }, DARK)
        polygon({ { 135, 127 }, { 141, 125 }, { 148, 134 }, { 145, 141 },
            { 139, 140 }, { 134, 133 } }, COPPER, GOLD)
        polygon({ { 135, 127 }, { 140, 126 }, { 146, 134 },
            { 143, 135 }, { 137, 131 } }, LIGHT, COPPER)
        polygon({ { 140, 148 }, { 152, 142 }, { 153, 136 },
            { 155, 140 }, { 153, 145 }, { 140, 151 } }, EDGE, SHADE)
        rivet(106, 91, 4.5)
        rivet(177, 188, 4.5)
        rivet(91, 137)
        rivet(188, 137)
        return
    end

    if id == 202 then
        -- 原闭面重盔和宽护颈轮廓保持，无脸部特征，壳体分面重画。
        local gorget = { { 99, 165 }, { 78, 168 }, { 57, 187 }, { 67, 204 },
            { 102, 219 }, { 139.5, 226 }, { 177, 219 }, { 213, 204 },
            { 223, 187 }, { 202, 168 }, { 180, 165 }, { 173, 179 },
            { 155, 191 }, { 124, 191 }, { 106, 179 } }
        emblem(gorget, COPPER, EDGE)
        polygon({ { 79, 173 }, { 98, 170 }, { 108, 184 }, { 125, 195 },
            { 139, 200 }, { 139, 207 }, { 106, 204 }, { 77, 192 },
            { 66, 187 } }, LIGHT, COPPER)
        polygon({ { 64, 190 }, { 79, 198 }, { 110, 211 }, { 139.5, 217 },
            { 139.5, 222 }, { 103, 215 }, { 71, 201 } }, COPPER, GOLD)
        polygon({ { 185, 173 }, { 201, 173 }, { 217, 186 }, { 207, 197 },
            { 177, 208 }, { 149, 214 }, { 149, 204 }, { 174, 191 } }, COPPER, EDGE)
        polygon({ { 215, 193 }, { 209, 202 }, { 176, 216 }, { 144, 222 },
            { 144, 216 }, { 176, 209 }, { 205, 197 } }, EDGE, SHADE)
        local helm = { { 122, 55 }, { 156, 55 }, { 173, 69 }, { 188, 96 },
            { 190, 151 }, { 179, 176 }, { 157, 192 }, { 122, 192 },
            { 100, 175 }, { 89, 151 }, { 91, 96 }, { 106, 69 } }
        emblem(helm, LIGHT, GOLD)
        -- 盔顶由左上受光壳面、铜中央面和右暗折面组成，取消直切双色柱。
        polygon({ { 123, 60 }, { 151, 60 }, { 158, 70 }, { 144, 75 },
            { 131, 91 }, { 102, 102 }, { 101, 95 }, { 111, 74 } }, BONE, LIGHT)
        polygon({ { 150, 66 }, { 162, 69 }, { 175, 85 }, { 181, 100 },
            { 153, 96 }, { 129, 96 }, { 134, 83 } }, LIGHT, COPPER)
        polygon({ { 165, 69 }, { 172, 74 }, { 185, 98 }, { 187, 148 },
            { 176, 173 }, { 156, 188 }, { 151, 181 }, { 170, 162 },
            { 177, 144 }, { 176, 99 } }, GOLD, EDGE)
        polygon({ { 96, 99 }, { 103, 100 }, { 103, 149 }, { 111, 168 },
            { 120, 179 }, { 119, 184 }, { 103, 172 }, { 93, 150 } }, LIGHT, COPPER)
        -- 单条盔窗改成亮上唇、暗内腔和厚下唇，不再加腔内横线。
        polygon({ { 102, 105 }, { 126, 98 }, { 158, 99 }, { 177, 107 },
            { 177, 113 }, { 158, 106 }, { 126, 105 }, { 103, 112 } }, LIGHT, COPPER)
        polygon({ { 103, 111 }, { 126, 105 }, { 158, 106 }, { 176, 113 },
            { 175, 123 }, { 153, 118 }, { 126, 117 }, { 104, 123 } }, DARK)
        polygon({ { 104, 123 }, { 126, 117 }, { 153, 118 }, { 175, 123 },
            { 174, 129 }, { 151, 124 }, { 127, 123 }, { 106, 129 } }, GOLD, EDGE)
        -- 护面仍是一张整甲；左倒角留亮，中央铜面宽，右下折面狭窄。
        emblem({ { 102, 130 }, { 126, 123 }, { 153, 124 }, { 178, 131 },
            { 172, 163 }, { 155, 179 }, { 123, 179 }, { 108, 163 } }, COPPER, GOLD)
        polygon({ { 106, 133 }, { 127, 127 }, { 134, 128 }, { 132, 134 },
            { 112, 139 }, { 116, 157 }, { 125, 169 }, { 125, 175 },
            { 112, 161 } }, BONE, LIGHT)
        polygon({ { 117, 141 }, { 133, 135 }, { 146, 134 }, { 151, 169 },
            { 143, 175 }, { 127, 173 }, { 119, 160 } }, LIGHT, COPPER)
        polygon({ { 153, 129 }, { 174, 135 }, { 169, 159 }, { 154, 174 },
            { 146, 176 }, { 151, 163 } }, GOLD, EDGE)
        polygon({ { 111, 164 }, { 124, 173 }, { 152, 174 }, { 170, 160 },
            { 168, 166 }, { 155, 179 }, { 124, 179 }, { 114, 170 } }, GOLD, EDGE)
        -- 一块宽喉甲承接护面，删除旧中央双亮线，避免“嘴部”观感。
        emblem({ { 109, 183 }, { 128, 190 }, { 153, 190 }, { 171, 183 },
            { 169, 197 }, { 151, 205 }, { 128, 205 }, { 111, 197 } }, COPPER, EDGE)
        polygon({ { 113, 186 }, { 128, 192 }, { 153, 192 }, { 167, 187 },
            { 163, 193 }, { 150, 198 }, { 129, 198 }, { 116, 194 } }, LIGHT, COPPER)
        polygon({ { 115, 196 }, { 129, 201 }, { 150, 201 }, { 166, 195 },
            { 166, 198 }, { 151, 204 }, { 129, 204 }, { 115, 199 } }, GOLD, EDGE)
        -- 护面最下缘压住喉甲；阴影是一条宽接触面，不是描嘴的亮线。
        polygon({ { 119, 180 }, { 127, 183 }, { 153, 183 }, { 162, 180 },
            { 155, 189 }, { 127, 189 } }, DARK)
        rivet(97, 135, 4)
        rivet(181, 135, 4)
        rivet(80, 190, 4)
        rivet(200, 190, 4)
        return
    end

    if id == 203 then
        -- 原宽门架、三栅两梁和负空间保持；重画门架导槽而非盾面刻线。
        local gate = { { 68, 190 }, { 68, 88 }, { 98, 64 }, { 181, 64 },
            { 210, 88 }, { 210, 190 }, { 195, 208 }, { 179, 208 },
            { 179, 103 }, { 166, 92 }, { 113, 92 }, { 100, 103 },
            { 100, 208 }, { 84, 208 } }
        emblem(gate, COPPER, GOLD)
        polygon({ { 72, 90 }, { 100, 68 }, { 179, 68 }, { 189, 78 },
            { 183, 81 }, { 176, 76 }, { 110, 77 }, { 80, 100 },
            { 80, 186 }, { 75, 195 }, { 72, 187 } }, BONE, LIGHT)
        polygon({ { 83, 102 }, { 94, 96 }, { 94, 200 }, { 86, 201 },
            { 82, 187 } }, COPPER, GOLD)
        -- 内壁暗槽落在原立柱里，不扩大到三根栅的间隙。
        polygon({ { 95, 101 }, { 100, 103 }, { 100, 205 }, { 95, 205 } }, EDGE, DARK)
        polygon({ { 113, 84 }, { 166, 84 }, { 178, 94 }, { 174, 100 },
            { 166, 92 }, { 113, 92 }, { 104, 99 }, { 101, 94 } }, GOLD, EDGE)
        polygon({ { 194, 91 }, { 205, 93 }, { 205, 188 }, { 193, 201 },
            { 186, 202 }, { 186, 103 } }, GOLD, EDGE)
        polygon({ { 179, 103 }, { 184, 99 }, { 184, 204 }, { 179, 207 } }, EDGE, DARK)
        -- 栅体原12px宽保持，内部改较窄暗边及实际三分面，释放负空间。
        for _, x in ipairs({ 113, 139.5, 166 }) do
            local bar = { { x - 6, 91 }, { x + 6, 91 }, { x + 6, 187 },
                { x + 3, 201 }, { x - 3, 201 }, { x - 6, 187 } }
            stroke(bar, 3, DARK, true)
            polygon(bar, LIGHT, GOLD)
            polygon({ { x - 5, 95 }, { x - 1, 95 }, { x - 1, 188 },
                { x - 2, 196 }, { x - 4, 186 } }, BONE, LIGHT)
            polygon({ { x, 95 }, { x + 3, 95 }, { x + 3, 186 },
                { x + 1, 195 }, { x, 189 } }, COPPER, GOLD)
            polygon({ { x + 3, 94 }, { x + 6, 94 }, { x + 6, 187 },
                { x + 3, 201 }, { x + 1, 197 }, { x + 3, 186 } }, GOLD, EDGE)
        end
        -- 横梁顶面亮、梁身铜、下壁暗；下压缝不添加细刻纹。
        for _, y in ipairs({ 124, 161 }) do
            polygon({ { 101, y + 5 }, { 178, y + 5 }, { 178, y + 8 },
                { 101, y + 8 } }, DARK)
            local beam = { { 101, y - 5 }, { 178, y - 5 }, { 182, y },
                { 178, y + 5 }, { 101, y + 5 }, { 97, y } }
            stroke(beam, 3, DARK, true)
            polygon(beam, COPPER, GOLD)
            polygon({ { 102, y - 4 }, { 177, y - 4 }, { 179, y - 1 },
                { 100, y - 1 } }, BONE, LIGHT)
            polygon({ { 100, y + 2 }, { 179, y + 2 }, { 177, y + 5 },
                { 102, y + 5 } }, GOLD, EDGE)
            rivet(113, y, 3.2)
            rivet(166, y, 3.2)
        end
        -- 原吊扣保留机械开口，左右壁用宽填充区分，不加新附件。
        emblem({ { 128, 65 }, { 151, 65 }, { 155, 74 }, { 151, 86 },
            { 128, 86 }, { 124, 74 } }, COPPER, GOLD)
        polygon({ { 129, 67 }, { 149, 67 }, { 152, 72 },
            { 128, 72 }, { 127, 70 } }, BONE, COPPER)
        polygon({ { 133, 73 }, { 146, 73 }, { 146, 81 }, { 133, 81 } }, DARK)
        polygon({ { 147, 72 }, { 151, 72 }, { 149, 83 },
            { 128, 83 }, { 130, 80 }, { 147, 80 } }, GOLD, EDGE)
        -- 底座内槽承接栅脚，顶沿仍保留明显骨白受光面。
        emblem({ { 91, 201 }, { 187, 201 }, { 193, 208 }, { 183, 215 },
            { 96, 215 }, { 86, 208 } }, COPPER, EDGE)
        polygon({ { 102, 202 }, { 177, 202 }, { 177, 206 }, { 102, 206 } }, DARK)
        polygon({ { 93, 204 }, { 100, 204 }, { 102, 207 }, { 178, 207 },
            { 180, 204 }, { 187, 205 }, { 185, 210 }, { 95, 210 },
            { 91, 207 } }, LIGHT, COPPER)
        polygon({ { 96, 211 }, { 186, 211 }, { 182, 214 }, { 98, 214 } }, GOLD, EDGE)
        rivet(79, 111, 4)
        rivet(79, 178, 4)
        rivet(199, 111, 4)
        rivet(199, 178, 4)
        return
    end

    -- 反冲闸：斜向闭拳臂铠与宽护腕，轴线及轮廓都不再是正立盾/门。
    -- 这是孤立的钢甲护具，没有人体手指、动势箭头或40%进度流程图。
    -- 局部坐标绕中心旋转30度，只投影几何，不改父像素或画布状态。
    local cosine, sine = math.cos(math.pi / 6), math.sin(math.pi / 6)
    ---@param points number[][]
    ---@return number[][]
    local function projected(points)
        local result = {}
        for _, p in ipairs(points) do
            result[#result + 1] = { CENTER + p[1] * cosine - p[2] * sine,
                CENTER + p[1] * sine + p[2] * cosine }
        end
        return result
    end
    ---@param x number
    ---@param y number
    ---@param radius number|nil
    local function joint(x, y, radius)
        local p = projected({ { x, y } })[1]
        rivet(p[1], p[2], radius)
    end

    -- 204：原斜向拳甲、三片叠甲与袖口轮廓保持，面光按投影后的画面顶左。
    -- 宽袖口后板先画，甲片之间直接露出暗背板，不画额外运动轨迹。
    emblem(projected({ { -43, 46 }, { -34, 38 }, { 33, 38 }, { 45, 48 },
        { 41, 74 }, { 22, 87 }, { -24, 87 }, { -42, 74 } }), COPPER, EDGE)
    polygon(projected({ { -39, 48 }, { -31, 42 }, { 28, 42 }, { 35, 47 },
        { 30, 52 }, { -29, 52 }, { -34, 67 }, { -39, 65 } }), BONE, LIGHT)
    polygon(projected({ { 35, 49 }, { 42, 51 }, { 38, 72 }, { 22, 83 },
        { 20, 76 }, { 31, 67 } }), GOLD, EDGE)
    emblem(projected({ { -27, -35 }, { 28, -35 }, { 36, 54 }, { 23, 75 },
        { -24, 75 }, { -38, 58 } }), GOLD, EDGE)
    polygon(projected({ { -27, -29 }, { -21, -30 }, { -23, 53 },
        { -17, 64 }, { -23, 69 }, { -33, 56 } }), LIGHT, COPPER)
    polygon(projected({ { -20, -29 }, { 20, -29 }, { 26, 51 },
        { 16, 65 }, { -15, 65 }, { -24, 53 } }), DARK)
    polygon(projected({ { 25, -28 }, { 29, -26 }, { 33, 52 },
        { 22, 70 }, { 18, 65 }, { 26, 50 } }), EDGE, SHADE)
    -- 拳峰保持钝端和宽肩；两块指节甲重画顶面，暗缝体现铰接而不是手指。
    emblem(projected({ { -31, -59 }, { -28, -77 }, { -10, -86 }, { 18, -86 },
        { 36, -72 }, { 40, -49 }, { 29, -34 }, { -23, -36 } }), LIGHT, GOLD)
    polygon(projected({ { -27, -75 }, { -9, -82 }, { 16, -82 }, { 20, -76 },
        { -8, -75 }, { -24, -65 } }), BONE, LIGHT)
    polygon(projected({ { 20, -80 }, { 32, -70 }, { 36, -50 }, { 27, -38 },
        { 20, -42 }, { 28, -53 }, { 26, -68 } }), GOLD, EDGE)
    polygon(projected({ { -27, -50 }, { 28, -48 }, { 32, -42 },
        { 25, -36 }, { -22, -38 } }), EDGE, SHADE)
    -- 原拇指护甲的嵌座与上左面分开，不另添人体轮廓。
    emblem(projected({ { 25, -48 }, { 42, -41 }, { 49, -24 }, { 43, -12 },
        { 25, -10 }, { 14, -22 } }), COPPER, EDGE)
    polygon(projected({ { 27, -42 }, { 37, -37 }, { 41, -26 }, { 35, -19 },
        { 26, -18 }, { 20, -24 } }), LIGHT, COPPER)
    polygon(projected({ { 39, -37 }, { 45, -32 }, { 46, -24 }, { 40, -15 },
        { 26, -13 }, { 26, -18 }, { 36, -20 }, { 41, -27 } }), GOLD, EDGE)
    polygon(projected({ { 17, -24 }, { 25, -19 }, { 26, -13 },
        { 22, -14 }, { 15, -22 } }), DARK)
    emblem(projected({ { -24, -73 }, { -9, -79 }, { -2, -74 }, { -2, -55 },
        { -21, -55 }, { -26, -62 } }), LIGHT, COPPER)
    polygon(projected({ { -22, -71 }, { -9, -76 }, { -5, -72 },
        { -5, -66 }, { -19, -63 }, { -23, -65 } }), BONE, LIGHT)
    polygon(projected({ { -22, -60 }, { -4, -62 }, { -3, -56 },
        { -20, -56 }, { -24, -62 } }), GOLD, EDGE)
    emblem(projected({ { 3, -78 }, { 17, -78 }, { 28, -67 }, { 28, -54 },
        { 3, -54 } }), COPPER, GOLD)
    polygon(projected({ { 5, -75 }, { 16, -75 }, { 24, -67 },
        { 21, -64 }, { 14, -69 }, { 5, -69 } }), LIGHT, COPPER)
    polygon(projected({ { 5, -60 }, { 25, -62 }, { 25, -55 },
        { 5, -55 } }), GOLD, EDGE)
    -- 每张原叠甲改宽铜面＋4–6px骨白倒角＋下右厚壁，暗缝露出真实背板。
    for _, y in ipairs({ -23, 2, 27 }) do
        emblem(projected({ { -28, y - 7 }, { -15, y - 12 }, { 22, y - 12 },
            { 32, y - 5 }, { 29, y + 9 }, { 17, y + 14 }, { -20, y + 14 },
            { -32, y + 7 } }), LIGHT, GOLD)
        polygon(projected({ { -26, y - 5 }, { -14, y - 9 }, { 20, y - 9 },
            { 26, y - 5 }, { 23, y - 2 }, { -12, y - 3 },
            { -23, y + 1 }, { -25, y + 6 }, { -29, y + 4 } }), BONE, LIGHT)
        polygon(projected({ { -19, y + 1 }, { -10, y - 2 }, { 21, y - 2 },
            { 25, y + 2 }, { 21, y + 7 }, { 14, y + 10 },
            { -18, y + 10 }, { -24, y + 5 } }), LIGHT, COPPER)
        polygon(projected({ { 26, y - 3 }, { 30, y - 3 }, { 27, y + 8 },
            { 16, y + 12 }, { -19, y + 12 }, { -27, y + 7 },
            { -24, y + 4 }, { -17, y + 8 }, { 14, y + 8 },
            { 23, y + 4 } }), GOLD, EDGE)
        polygon(projected({ { -18, y + 12 }, { 17, y + 12 }, { 26, y + 8 },
            { 24, y + 11 }, { 17, y + 14 }, { -18, y + 14 } }), EDGE, SHADE)
    end
    -- 护腕旧黑槽重画成内腔、受光口沿与暗下壁；两个原铰钉数量不变。
    polygon(projected({ { -30, 68 }, { -20, 73 }, { 21, 73 }, { 31, 66 },
        { 33, 72 }, { 20, 82 }, { -21, 82 }, { -33, 74 } }), DARK)
    polygon(projected({ { -30, 70 }, { -20, 75 }, { 20, 75 }, { 28, 70 },
        { 27, 74 }, { 18, 78 }, { -20, 78 }, { -29, 74 } }), EDGE, SHADE)
    polygon(projected({ { -33, 67 }, { -29, 65 }, { -21, 70 }, { 21, 70 },
        { 28, 65 }, { 31, 67 }, { 22, 74 }, { -21, 74 },
        { -31, 70 } }), LIGHT, COPPER)
    polygon(projected({ { -30, 77 }, { -20, 82 }, { 19, 82 }, { 30, 75 },
        { 25, 82 }, { 20, 85 }, { -22, 85 }, { -33, 78 } }), GOLD, EDGE)
    joint(-32, 51, 4.5)
    joint(34, 51, 4.5)
end

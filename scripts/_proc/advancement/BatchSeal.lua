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
    -- 父 emblem 的最宽描边为7；这里固定按半宽3.5预留，底板仍由父负责。
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
        assert(rx > 0 and ry > 0, "BatchSeal椭圆半径必须大于0")
        -- 用包围矩形四角做保守检查，比只查椭圆四轴端点更严格。
        pointInside(cx - rx, cy - ry, 0)
        pointInside(cx + rx, cy - ry, 0)
        pointInside(cx + rx, cy + ry, 0)
        pointInside(cx - rx, cy + ry, 0)
        d.ellipse(cx, cy, rx, ry, top, bottom)
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
        -- 封门人：完整尖底盾，门扉甲板与中央深缝是职业识别，不图解12%储伤。
        -- 轮廓顶端不加冠齿；左右大明暗面在64px仍可读为厚重封门盾。
        local shield = { { 139.5, 52 }, { 176, 68 }, { 200, 97 }, { 200, 156 },
            { 186, 189 }, { 159, 217 }, { 139.5, 229 }, { 120, 217 },
            { 93, 189 }, { 79, 156 }, { 79, 97 }, { 103, 68 } }
        emblem(shield, GOLD, SHADE)
        polygon({ { 139.5, 64 }, { 168, 78 }, { 187, 103 }, { 186, 155 },
            { 173, 182 }, { 151, 204 }, { 139.5, 212 }, { 128, 204 },
            { 106, 182 }, { 93, 155 }, { 92, 103 }, { 111, 78 } }, DARK)
        -- 左扉骨白大面，右扉旧铜暗面；两者共享护甲语言而非装饰小符号。
        emblem({ { 111, 82 }, { 134, 72 }, { 134, 202 }, { 117, 188 },
            { 100, 158 }, { 99, 105 } }, BONE, GOLD)
        emblem({ { 145, 72 }, { 168, 82 }, { 180, 105 }, { 179, 158 },
            { 162, 188 }, { 145, 202 } }, GOLD, SHADE)
        polygon({ { 108, 104 }, { 124, 89 }, { 128, 86 }, { 128, 179 },
            { 116, 168 }, { 108, 151 } }, BONE, GOLD)
        polygon({ { 154, 85 }, { 166, 91 }, { 174, 107 }, { 173, 154 },
            { 159, 179 }, { 154, 184 } }, SHADE, DARK)
        line(139.5, 82, 139.5, 196, 8, DARK)
        line(136, 88, 136, 190, 1.8, BONE)
        -- 两枚侧向门铰是盾面结构，不横穿中缝形成十字徽记。
        for _, y in ipairs({ 119, 158 }) do
            emblem({ { 86, y - 7 }, { 108, y - 7 }, { 112, y },
                { 108, y + 7 }, { 86, y + 7 } }, GOLD, SHADE)
            line(89, y - 4, 104, y - 4, 2.2, BONE)
            rivet(94, y, 3.5)
            rivet(184, y, 3.5)
        end
        polygon({ { 112, 193 }, { 139.5, 216 }, { 139.5, 223 }, { 121, 213 } }, BONE, GOLD)
        polygon({ { 145, 209 }, { 171, 188 }, { 158, 211 }, { 145, 220 } }, GOLD, SHADE)
        stroke({ { 84, 103 }, { 84, 154 }, { 97, 186 }, { 121, 211 } }, 2.8, BONE, false)
        stroke({ { 173, 74 }, { 195, 100 }, { 195, 154 }, { 182, 186 } }, 2.5, SHADE, false)
        line(113, 76, 134, 66, 2.5, BONE)
        return
    end

    if id == 201 then
        -- 封条：方底塔盾与一根实体斜封带；不是尖底基础盾的换色版。
        -- 加厚的封带、门铰和封扣表达重防御职业，不画治疗或转伤流程。
        local tower = { { 97, 60 }, { 181, 60 }, { 197, 76 }, { 197, 194 },
            { 183, 215 }, { 97, 215 }, { 82, 194 }, { 82, 77 } }
        emblem(tower, GOLD, SHADE)
        polygon({ { 103, 74 }, { 175, 74 }, { 184, 85 }, { 184, 188 },
            { 177, 200 }, { 103, 200 }, { 95, 188 }, { 95, 85 } }, DARK)
        emblem({ { 101, 86 }, { 111, 79 }, { 134, 79 }, { 134, 195 },
            { 103, 195 }, { 101, 186 } }, GOLD, SHADE)
        emblem({ { 145, 79 }, { 169, 79 }, { 177, 87 }, { 177, 186 },
            { 174, 195 }, { 145, 195 } }, GOLD, SHADE)
        polygon({ { 107, 92 }, { 122, 85 }, { 127, 85 }, { 127, 188 },
            { 107, 188 } }, BONE, GOLD)
        polygon({ { 154, 85 }, { 169, 89 }, { 172, 97 }, { 171, 187 },
            { 154, 187 } }, SHADE, DARK)
        line(139.5, 83, 139.5, 192, 7, DARK)
        -- 塔盾上、下两道护沿，不画第二圈底板。
        emblem({ { 96, 66 }, { 181, 66 }, { 188, 75 }, { 180, 84 },
            { 98, 84 }, { 90, 76 } }, BONE, GOLD)
        emblem({ { 92, 192 }, { 184, 192 }, { 186, 200 }, { 178, 209 },
            { 101, 209 }, { 91, 200 } }, GOLD, SHADE)
        line(101, 69, 175, 69, 2.5, BONE)
        line(103, 201, 176, 201, 3, SHADE)
        -- 一根宽斜封带从左上到右下，宽度约22px，缩小仍保有完整实心面。
        emblem({ { 92, 85 }, { 105, 75 }, { 184, 178 }, { 189, 197 },
            { 175, 203 }, { 88, 99 } }, BONE, GOLD)
        polygon({ { 105, 84 }, { 176, 177 }, { 182, 193 }, { 176, 195 },
            { 99, 96 } }, GOLD, SHADE)
        line(99, 87, 175, 185, 3.4, BONE)
        -- 封扣是铆合的矩形装甲件，不是魔法符号或文字标签。
        emblem({ { 126, 119 }, { 142, 112 }, { 157, 132 }, { 155, 145 },
            { 139, 152 }, { 125, 132 } }, GOLD, SHADE)
        line(132, 122, 149, 144, 3, BONE)
        rivet(106, 91, 4.5)
        rivet(177, 188, 4.5)
        rivet(91, 137)
        rivet(188, 137)
        stroke({ { 86, 86 }, { 86, 190 }, { 99, 210 } }, 2.7, BONE, false)
        stroke({ { 193, 85 }, { 193, 191 }, { 181, 209 } }, 2.8, SHADE, false)
        return
    end

    if id == 202 then
        -- 殉门：无人佩戴的闭面重盔与宽喉甲；完全没有人物脸、眼珠或皇冠。
        -- 拱顶、单缝盔窗和张开的护颈，与门盾/塔盾的外轮廓直接区分。
        local gorget = { { 99, 165 }, { 78, 168 }, { 57, 187 }, { 67, 204 },
            { 102, 219 }, { 139.5, 226 }, { 177, 219 }, { 213, 204 },
            { 223, 187 }, { 202, 168 }, { 180, 165 }, { 173, 179 },
            { 155, 191 }, { 124, 191 }, { 106, 179 } }
        emblem(gorget, GOLD, SHADE)
        polygon({ { 80, 178 }, { 68, 188 }, { 79, 197 }, { 109, 209 },
            { 139.5, 215 }, { 139.5, 221 }, { 103, 215 }, { 70, 201 },
            { 62, 188 } }, BONE, GOLD)
        polygon({ { 181, 178 }, { 202, 178 }, { 216, 188 }, { 207, 199 },
            { 176, 212 }, { 147, 218 }, { 147, 210 }, { 171, 198 } }, GOLD, DARK)
        local helm = { { 122, 55 }, { 156, 55 }, { 173, 69 }, { 188, 96 },
            { 190, 151 }, { 179, 176 }, { 157, 192 }, { 122, 192 },
            { 100, 175 }, { 89, 151 }, { 91, 96 }, { 106, 69 } }
        emblem(helm, BONE, GOLD)
        polygon({ { 141, 62 }, { 156, 63 }, { 170, 76 }, { 180, 99 },
            { 181, 147 }, { 171, 169 }, { 151, 183 }, { 141, 183 } }, GOLD, SHADE)
        polygon({ { 116, 75 }, { 133, 63 }, { 133, 97 }, { 102, 103 },
            { 103, 93 } }, BONE, GOLD)
        -- 盔窗是单条机械开口，禁用双眼、鼻子、嘴等面部特征。
        polygon({ { 102, 108 }, { 126, 102 }, { 158, 103 }, { 177, 111 },
            { 176, 123 }, { 153, 118 }, { 126, 117 }, { 104, 123 } }, DARK)
        stroke({ { 104, 105 }, { 126, 99 }, { 159, 100 }, { 177, 108 } }, 3.2, GOLD, false)
        line(110, 113, 170, 113, 2, SHADE)
        -- 下半盔是一整张护面甲而非人脸；大分面只有左亮、右暗两块。
        emblem({ { 102, 130 }, { 126, 123 }, { 153, 124 }, { 178, 131 },
            { 172, 163 }, { 155, 179 }, { 123, 179 }, { 108, 163 } }, GOLD, SHADE)
        polygon({ { 108, 134 }, { 133, 128 }, { 133, 172 }, { 121, 169 },
            { 112, 159 } }, BONE, GOLD)
        polygon({ { 143, 128 }, { 172, 135 }, { 167, 157 }, { 154, 170 },
            { 143, 174 } }, SHADE, DARK)
        line(139.5, 130, 139.5, 173, 3, GOLD)
        stroke({ { 110, 73 }, { 98, 98 }, { 97, 149 }, { 106, 169 } }, 3, BONE, false)
        stroke({ { 180, 134 }, { 182, 150 }, { 173, 172 }, { 156, 185 } }, 3, SHADE, false)
        line(127, 61, 150, 61, 2.4, BONE)
        -- 护颈三片实体叠甲；止于喉甲，不扩展成人物胸像或全身。
        emblem({ { 109, 183 }, { 128, 190 }, { 153, 190 }, { 171, 183 },
            { 169, 197 }, { 151, 205 }, { 128, 205 }, { 111, 197 } }, GOLD, SHADE)
        line(116, 193, 128, 197, 2.5, BONE)
        line(128, 199, 151, 199, 2.5, BONE)
        rivet(97, 135, 4)
        rivet(181, 135, 4)
        rivet(80, 190, 4)
        rivet(200, 190, 4)
        return
    end

    if id == 203 then
        -- 死闸：宽门架与三根落到底的重栅，识别依赖大开口，不是盾上刻栅纹。
        -- 三根栅之间预留真实负空间；栅脚为钝齿，不借箭头表达转伤。
        local gate = { { 68, 190 }, { 68, 88 }, { 98, 64 }, { 181, 64 },
            { 210, 88 }, { 210, 190 }, { 195, 208 }, { 179, 208 },
            { 179, 103 }, { 166, 92 }, { 113, 92 }, { 100, 103 },
            { 100, 208 }, { 84, 208 } }
        emblem(gate, GOLD, SHADE)
        polygon({ { 74, 91 }, { 102, 70 }, { 176, 70 }, { 185, 78 },
            { 111, 79 }, { 82, 100 }, { 82, 188 }, { 75, 192 } }, BONE, GOLD)
        polygon({ { 194, 92 }, { 204, 93 }, { 204, 188 }, { 193, 200 },
            { 186, 200 }, { 186, 102 } }, SHADE, DARK)
        -- 三个栅体宽12、间距26.5；父暗边半宽3.5后间隙仍有7.5。
        for _, x in ipairs({ 113, 139.5, 166 }) do
            emblem({ { x - 6, 91 }, { x + 6, 91 }, { x + 6, 187 },
                { x + 3, 201 }, { x - 3, 201 }, { x - 6, 187 } }, BONE, GOLD)
            polygon({ { x + 1, 98 }, { x + 4, 98 }, { x + 4, 185 },
                { x + 1, 192 } }, GOLD, SHADE)
            line(x - 3, 99, x - 3, 180, 2.6, BONE)
        end
        -- 两根真实横梁与竖栅构成闸栅结构，不添加宗教十字徽记。
        for _, y in ipairs({ 124, 161 }) do
            emblem({ { 101, y - 5 }, { 178, y - 5 }, { 182, y },
                { 178, y + 5 }, { 101, y + 5 }, { 97, y } }, GOLD, SHADE)
            line(105, y - 3, 175, y - 3, 2.1, BONE)
            rivet(113, y, 3.2)
            rivet(166, y, 3.2)
        end
        -- 上梁机械吊扣仅为厚门架构件，无尖顶/冠齿。
        emblem({ { 128, 65 }, { 151, 65 }, { 155, 74 }, { 151, 86 },
            { 128, 86 }, { 124, 74 } }, GOLD, SHADE)
        polygon({ { 133, 70 }, { 146, 70 }, { 146, 79 }, { 133, 79 } }, DARK)
        line(131, 68, 148, 68, 2.1, BONE)
        emblem({ { 91, 201 }, { 187, 201 }, { 193, 208 }, { 183, 215 },
            { 96, 215 }, { 86, 208 } }, GOLD, SHADE)
        line(101, 204, 179, 204, 2.4, BONE)
        line(100, 211, 180, 211, 2.8, SHADE)
        rivet(79, 111, 4)
        rivet(79, 178, 4)
        rivet(199, 111, 4)
        rivet(199, 178, 4)
        stroke({ { 72, 105 }, { 72, 187 }, { 85, 202 } }, 2.8, BONE, false)
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
    ---@param points number[][]
    ---@param width number
    ---@param color number[]
    local function edge(points, width, color)
        stroke(projected(points), width, color, false)
    end
    ---@param x number
    ---@param y number
    ---@param radius number|nil
    local function joint(x, y, radius)
        local p = projected({ { x, y } })[1]
        rivet(p[1], p[2], radius)
    end

    -- 先铺宽袖口及背板；上层手甲与三张叠甲自然遮挡，不画运动轨迹。
    emblem(projected({ { -43, 46 }, { -34, 38 }, { 33, 38 }, { 45, 48 },
        { 41, 74 }, { 22, 87 }, { -24, 87 }, { -42, 74 } }), GOLD, SHADE)
    emblem(projected({ { -27, -35 }, { 28, -35 }, { 36, 54 }, { 23, 75 },
        { -24, 75 }, { -38, 58 } }), BONE, GOLD)
    polygon(projected({ { 7, -28 }, { 25, -27 }, { 30, 51 }, { 19, 67 },
        { 7, 67 } }), GOLD, SHADE)
    polygon(projected({ { -29, 50 }, { -15, 55 }, { -15, 68 }, { -24, 67 },
        { -32, 57 } }), BONE, GOLD)
    -- 闭合拳峰：宽肩、平钝拳端和突出的拇指护甲，不做尖刃或人物大脸。
    emblem(projected({ { -31, -59 }, { -28, -77 }, { -10, -86 }, { 18, -86 },
        { 36, -72 }, { 40, -49 }, { 29, -34 }, { -23, -36 } }), BONE, GOLD)
    polygon(projected({ { 8, -79 }, { 18, -79 }, { 30, -68 }, { 34, -49 },
        { 25, -41 }, { 8, -43 } }), GOLD, SHADE)
    emblem(projected({ { 25, -48 }, { 42, -41 }, { 49, -24 }, { 43, -12 },
        { 25, -10 }, { 14, -22 } }), GOLD, SHADE)
    polygon(projected({ { 27, -40 }, { 37, -36 }, { 41, -25 }, { 36, -18 },
        { 27, -17 }, { 22, -23 } }), BONE, GOLD)
    -- 两枚宽指节甲和一道关节缝，比四五条细刻线更适合64px。
    emblem(projected({ { -24, -73 }, { -9, -79 }, { -2, -74 }, { -2, -55 },
        { -21, -55 }, { -26, -62 } }), BONE, GOLD)
    emblem(projected({ { 3, -78 }, { 17, -78 }, { 28, -67 }, { 28, -54 },
        { 3, -54 } }), GOLD, SHADE)
    edge({ { -19, -72 }, { -10, -75 }, { -7, -71 } }, 2.7, BONE)
    edge({ { 7, -74 }, { 16, -74 }, { 24, -66 } }, 2.7, BONE)
    -- 三张宽叠甲沿臂铠纵轴覆盖，左右侧翼阶梯构成独立锯齿轮廓。
    for _, y in ipairs({ -23, 2, 27 }) do
        emblem(projected({ { -28, y - 7 }, { -15, y - 12 }, { 22, y - 12 },
            { 32, y - 5 }, { 29, y + 9 }, { 17, y + 14 }, { -20, y + 14 },
            { -32, y + 7 } }), BONE, GOLD)
        polygon(projected({ { 5, y - 7 }, { 22, y - 7 }, { 27, y - 2 },
            { 24, y + 6 }, { 15, y + 9 }, { 5, y + 9 } }), GOLD, SHADE)
        edge({ { -23, y - 4 }, { -13, y - 8 }, { 18, y - 8 } }, 2.6, BONE)
        edge({ { -17, y + 10 }, { 16, y + 10 }, { 25, y + 6 } }, 3, SHADE)
    end
    -- 厚护腕的开口与两枚铰钉保留护具尺度，不附加轮环或职业符号。
    polygon(projected({ { -30, 68 }, { -20, 73 }, { 21, 73 }, { 31, 66 },
        { 33, 72 }, { 20, 82 }, { -21, 82 }, { -33, 74 } }), DARK)
    edge({ { -34, 48 }, { -36, 64 }, { -29, 73 } }, 3, BONE)
    edge({ { -20, 84 }, { 19, 84 }, { 36, 73 } }, 2.8, GOLD)
    joint(-32, 51, 4.5)
    joint(34, 51, 4.5)
end

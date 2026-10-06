-- 裂隙使一转审核主体；沿用 generate_advancement_trials 的 CPU 图元闭包。
-- 105保留三截错位裂晶，补金属束箍与权杖承托；106保留双瓣深裂晶与短爪杖。
-- 四元素收进镶座组件，以职业器物为主轮廓，不再画机制循环箭。
-- 只提交主体路径，底板、560母图、预乘降采样和审核PNG由调用方负责。
-- 所有控制点及描边都收在中心(139.5,139.5)半径112内，不读取旧图。

---@class ReviewRiftDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field ellipse fun(cx: number, cy: number, rx: number, ry: number, top: number[], bottom?: number[])
---@field arc fun(cx: number, cy: number, rx: number, ry: number, firstDeg: number, lastDeg: number, width: number, color: number[])
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d ReviewRiftDraw
---@param branchId integer
return function(d, branchId)
    assert(branchId == 105 or branchId == 106, "ReviewRift只绘制105/106审核主体")
    local polygon, line, stroke = d.polygon, d.line, d.stroke
    local curve, emblem = d.curve, d.emblem
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    if branchId == 105 then
        -- 后层束箍连成错位权杖，晶核原路径与两道断隙完全保留。
        -- 侧柱只走晶体外缘，绝不穿过中央宽空隙；底部有独立握柄与柄尾。
        emblem({ { 117, 202 }, { 137, 202 }, { 145, 228 },
            { 139, 241 }, { 122, 241 }, { 118, 229 } }, GOLD, SHADE)
        polygon({ { 121, 216 }, { 129, 216 }, { 134, 237 }, { 125, 237 } }, BONE, GOLD)
        stroke({ { 103, 91 }, { 83, 105 }, { 80, 153 },
            { 92, 191 }, { 117, 211 } }, 16, DARK, false)
        stroke({ { 103, 91 }, { 83, 105 }, { 80, 153 },
            { 92, 191 }, { 117, 211 } }, 9, GOLD, false)
        stroke({ { 155, 92 }, { 192, 105 }, { 202, 143 },
            { 182, 191 }, { 141, 211 } }, 16, DARK, false)
        stroke({ { 155, 92 }, { 192, 105 }, { 202, 143 },
            { 182, 191 }, { 141, 211 } }, 9, GOLD, false)
        stroke({ { 84, 108 }, { 83, 152 }, { 94, 189 } }, 2.8, BONE, false)
        stroke({ { 192, 109 }, { 198, 142 }, { 180, 187 } }, 2.8, BONE, false)

        -- 三截实心晶核上下错开；两条宽空隙是真负空间，不用细纹模拟裂痕。
        -- 断口首尾相差16px，扣除两侧7px暗描边后仍有9px间隙。
        local upper = { { 127, 52 }, { 157, 78 }, { 168, 89 },
            { 155, 99 }, { 107, 99 }, { 97, 85 } }
        local middle = { { 119, 115 }, { 180, 115 }, { 191, 129 },
            { 176, 152 }, { 119, 152 }, { 109, 134 } }
        local lower = { { 95, 168 }, { 165, 168 }, { 157, 185 },
            { 125, 214 }, { 99, 187 }, { 88, 176 } }
        emblem(upper, BONE, GOLD)
        emblem(middle, BONE, GOLD)
        emblem(lower, BONE, GOLD)

        -- 倒角只保留三张明面、三张铜暗面，避免小尺寸杂色碎斑。
        polygon({ { 127, 57 }, { 126, 89 }, { 108, 95 }, { 102, 85 } }, BONE, GOLD)
        polygon({ { 132, 65 }, { 161, 88 }, { 152, 95 }, { 136, 90 } }, GOLD, SHADE)
        stroke({ { 106, 96 }, { 128, 89 }, { 155, 96 } }, 3.5, DARK, false)
        line(128, 61, 128, 87, 3, BONE)
        polygon({ { 122, 119 }, { 146, 125 }, { 143, 148 },
            { 122, 148 }, { 114, 134 } }, BONE, GOLD)
        polygon({ { 152, 124 }, { 179, 119 }, { 185, 130 },
            { 172, 148 }, { 150, 148 } }, GOLD, SHADE)
        stroke({ { 118, 119 }, { 148, 126 }, { 184, 119 } }, 3.5, DARK, false)
        line(148, 128, 148, 148, 3, BONE)
        polygon({ { 95, 172 }, { 124, 174 }, { 124, 205 }, { 102, 185 } }, BONE, GOLD)
        polygon({ { 134, 174 }, { 158, 172 }, { 151, 184 }, { 131, 204 } }, GOLD, SHADE)
        stroke({ { 94, 173 }, { 128, 178 }, { 160, 173 } }, 3.5, DARK, false)
        line(128, 181, 127, 202, 3, BONE)

        -- 每截断口一条粗铜唇，层数直接由三大色面表达，不额外堆计数小点。
        line(111, 97, 151, 97, 3.5, GOLD)
        line(124, 150, 171, 150, 3.5, GOLD)
        line(100, 170, 159, 170, 3.5, BONE)

        -- 实物束箍短爪扣住各截晶体，不再用循环箭和位移短痕说明技能。
        emblem({ { 98, 88 }, { 111, 91 }, { 113, 100 },
            { 104, 102 }, { 98, 97 } }, GOLD, SHADE)
        emblem({ { 172, 121 }, { 184, 116 }, { 194, 129 },
            { 187, 140 }, { 181, 136 } }, GOLD, SHADE)
        emblem({ { 87, 174 }, { 99, 178 }, { 104, 190 },
            { 94, 192 }, { 88, 184 } }, GOLD, SHADE)
        emblem({ { 110, 207 }, { 146, 207 }, { 141, 220 }, { 117, 220 } }, GOLD, SHADE)
        line(116, 211, 140, 211, 3, BONE)
        line(122, 230, 139, 230, 5, DARK)
        line(123, 229, 138, 229, 2.8, GOLD)
        return
    end

    -- 深缝双瓣晶核与短爪法杖沿用原坐标；四符收进有连接臂的仪式镶座。
    -- 四镶座是杖首组件，不围出第二层底板，也不穿过中央纵向裂隙。
    for _, arm in ipairs({
        { { 86, 112 }, { 95, 119 }, { 103, 139 } },
        { { 193, 112 }, { 184, 119 }, { 176, 139 } },
        { { 87, 176 }, { 104, 171 }, { 123, 165 } },
        { { 192, 176 }, { 175, 171 }, { 156, 165 } },
    }) do
        stroke(arm, 15, DARK, false)
        stroke(arm, 8, GOLD, false)
    end
    emblem({ { 70, 73 }, { 88, 86 }, { 96, 105 },
        { 86, 123 }, { 59, 126 }, { 51, 109 }, { 57, 89 } }, GOLD, SHADE)
    polygon({ { 70, 79 }, { 83, 90 }, { 90, 105 },
        { 82, 119 }, { 61, 119 }, { 57, 107 }, { 62, 91 } }, DARK)
    emblem({ { 207, 73 }, { 226, 88 }, { 230, 107 },
        { 218, 126 }, { 193, 123 }, { 186, 106 }, { 193, 87 } }, GOLD, SHADE)
    polygon({ { 207, 79 }, { 221, 91 }, { 224, 106 },
        { 215, 120 }, { 197, 118 }, { 192, 105 }, { 198, 91 } }, DARK)
    emblem({ { 62, 148 }, { 85, 149 }, { 97, 171 },
        { 88, 195 }, { 65, 200 }, { 50, 178 } }, GOLD, SHADE)
    polygon({ { 65, 154 }, { 81, 155 }, { 91, 172 },
        { 84, 190 }, { 68, 194 }, { 56, 178 } }, DARK)
    emblem({ { 197, 145 }, { 220, 148 }, { 231, 173 },
        { 215, 201 }, { 194, 198 }, { 184, 173 } }, GOLD, SHADE)
    polygon({ { 200, 151 }, { 216, 154 }, { 225, 173 },
        { 213, 194 }, { 198, 192 }, { 190, 173 } }, DARK)

    -- 原杖身在后层，晶核断隙仍不被连接线填满。
    emblem({ { 133, 156 }, { 146, 156 }, { 145, 215 },
        { 139.5, 225 }, { 134, 215 } }, BONE, GOLD)
    polygon({ { 142, 162 }, { 145, 162 }, { 144, 212 }, { 140, 216 } }, GOLD, SHADE)
    line(137, 167, 137, 211, 3, BONE)
    for _, y in ipairs({ 180, 195, 209 }) do
        line(133, y, 146, y + 2, 5, DARK)
        line(134, y, 144, y + 1.5, 2.8, GOLD)
    end

    local leftCore = { { 132, 55 }, { 141, 82 }, { 131, 98 },
        { 141, 115 }, { 129, 136 }, { 134, 157 }, { 111, 139 }, { 101, 96 } }
    local rightCore = { { 147, 55 }, { 175, 96 }, { 166, 141 },
        { 146, 158 }, { 144, 138 }, { 154, 114 }, { 143, 98 }, { 154, 82 } }
    emblem(leftCore, BONE, GOLD)
    emblem(rightCore, BONE, GOLD)
    polygon({ { 129, 63 }, { 130, 82 }, { 121, 98 },
        { 126, 128 }, { 115, 136 }, { 106, 97 } }, BONE, GOLD)
    polygon({ { 156, 72 }, { 170, 97 }, { 162, 138 },
        { 150, 150 }, { 151, 138 }, { 160, 114 }, { 150, 97 } }, GOLD, SHADE)
    stroke({ { 130, 59 }, { 107, 96 }, { 115, 133 } }, 3.5, BONE, false)
    stroke({ { 151, 88 }, { 145, 98 }, { 155, 114 }, { 146, 138 } }, 3, GOLD, false)

    -- 非闭合的短爪承托，不画横护手，避免和拾骸者的剑混淆。
    local cradle = { { 94, 122 }, { 100, 145 }, { 117, 163 },
        { 139.5, 170 }, { 162, 163 }, { 179, 145 }, { 185, 122 } }
    stroke(cradle, 12, DARK, false)
    stroke(cradle, 6, GOLD, false)
    stroke({ { 96, 124 }, { 102, 143 }, { 119, 160 }, { 139.5, 167 } }, 2.8, BONE, false)
    emblem({ { 123, 160 }, { 156, 160 }, { 151, 173 }, { 128, 173 } }, GOLD, SHADE)
    line(128, 164, 151, 164, 3, BONE)

    -- 火：宽火舌与一个暗焰腔；整体仍是旧铜骨白，而非彩色法术光效。
    local fire = { { 59, 108 } }
    curve(fire, 57, 98, 69, 97, 70, 80)
    curve(fire, 80, 86, 75, 95, 84, 99)
    curve(fire, 93, 104, 86, 116, 73, 118)
    curve(fire, 65, 120, 60, 116, 59, 108)
    emblem(fire, BONE, GOLD)
    polygon({ { 71, 97 }, { 76, 106 }, { 73, 113 }, { 67, 110 } }, DARK)
    line(64, 106, 65, 112, 3, BONE)

    -- 冰：尖端/肩部明显的完整冰晶，不用雪花十字。
    emblem({ { 207, 80 }, { 222, 99 }, { 216, 115 },
        { 201, 119 }, { 192, 102 }, { 198, 89 } }, BONE, GOLD)
    polygon({ { 208, 86 }, { 217, 99 }, { 210, 114 }, { 206, 102 } }, GOLD, SHADE)
    stroke({ { 197, 101 }, { 206, 103 }, { 207, 87 } }, 3.5, DARK, false)
    line(207, 105, 202, 114, 3, BONE)

    -- 雷：实心折线电楔；保留宽腰和两尖端，64px不靠细线识别。
    emblem({ { 207, 152 }, { 218, 152 }, { 210, 167 }, { 222, 167 },
        { 198, 194 }, { 204, 176 }, { 192, 176 } }, BONE, GOLD)
    polygon({ { 211, 157 }, { 204, 169 }, { 212, 169 }, { 202, 184 },
        { 208, 172 }, { 200, 172 } }, GOLD, SHADE)

    -- 暗：实体弯月，内弧用路径做负空间，不覆盖父底板或叠泛光。
    local shadow = { { 78, 155 } }
    curve(shadow, 55, 153, 51, 181, 71, 192)
    curve(shadow, 78, 196, 87, 192, 89, 184)
    curve(shadow, 73, 187, 66, 165, 78, 155)
    emblem(shadow, GOLD, SHADE)
    local crescentEdge = { { 70, 159 } }
    curve(crescentEdge, 57, 163, 57, 180, 70, 187)
    stroke(crescentEdge, 3, BONE, false)

    -- 镶座连接已经提供完整器物轮廓，不再补循环箭或漂浮法术光效。
end

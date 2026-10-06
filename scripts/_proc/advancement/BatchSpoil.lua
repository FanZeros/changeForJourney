-- 拾骸者第二批审核主体：基础职业与二转战具，不画底板、不读旧图、不保存图片。
-- 以宽战剑、弧刃长斧、束扣重剑、剑斧双械与齿刃臂甲建立不同职业轮廓。
-- 共用中心为139.5、139.5，所有主体及描边均预留在112半径之内。

---@class BatchSpoilDraw
---@field polygon fun(points:number[][], top:number[], bottom?:number[], opacity?:number)
---@field line fun(x0:number, y0:number, x1:number, y1:number, width:number, color:number[], opacity?:number)
---@field stroke fun(points:number[][], width:number, color:number[], closed?:boolean, opacity?:number)
---@field ellipse fun(cx:number, cy:number, rx:number, ry:number, top:number[], bottom?:number[])
---@field curve fun(points:number[][], c1x:number, c1y:number, c2x:number, c2y:number, endx:number, endy:number)
---@field emblem fun(points:number[][], top?:number[], bottom?:number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d BatchSpoilDraw
---@param branchId integer
return function(d, branchId)
    assert(branchId == 2 or branchId == 205 or branchId == 206 or branchId == 207 or branchId == 208,
        "BatchSpoil只绘制2及205至208审核主体")
    -- 闭包必须点调用，不能把接口表当作隐含参数传入。
    local polygon, stroke, emblem = d.polygon, d.stroke, d.emblem
    local ellipse, curve = d.ellipse, d.curve
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    --- 武器只投影局部几何，不设置画布或改变父生成器的坐标系。
    ---@param cx number
    ---@param cy number
    ---@param angle number
    ---@param scale number
    ---@return fun(points:number[][]):number[][]
    local function projector(cx, cy, angle, scale)
        local cosine, sine = math.cos(angle), math.sin(angle)
        return function(points)
            local result = {}
            for _, point in ipairs(points) do
                result[#result + 1] = {
                    cx + (point[1] * cosine - point[2] * sine) * scale,
                    cy + (point[1] * sine + point[2] * cosine) * scale,
                }
            end
            return result
        end
    end

    --- 提炼原骨剑护手与缠骨握柄，保持一转到二转的装备家族关系。
    ---@param p fun(points:number[][]):number[][]
    ---@param scale number
    local function boneGrip(p, scale)
        -- 原来的上弯骨节护手保留，不改为宗教十字或皇冠。
        for _, side in ipairs({ -1, 1 }) do
            emblem(p({ { side * 3, 25 }, { side * 14, 29 }, { side * 23, 22 },
                { side * 24, 30 }, { side * 17, 39 }, { side * 8, 36 } }), BONE, GOLD)
            stroke(p({ { side * 10, 29 }, { side * 17, 32 }, { side * 21, 27 } }),
                2.2 * scale, BONE, false)
        end
        stroke(p({ { 0, 35 }, { 0, 66 } }), 15 * scale, DARK, false)
        stroke(p({ { 0, 36 }, { 0, 66 } }), 8 * scale, GOLD, false)
        for _, y in ipairs({ 43, 52, 61 }) do
            stroke(p({ { -4, y - 2 }, { 4, y + 1 } }), 3.2 * scale, SHADE, false)
            stroke(p({ { -4, y - 3 }, { 3, y - 1 } }), 1.8 * scale, BONE, false)
        end
        emblem(p({ { 0, 66 }, { 9, 73 }, { 6, 79 }, { -6, 79 }, { -9, 73 } }), BONE, GOLD)
    end

    --- 保留原骨剑的尖端、双面宽脊与骨节护手，基础职业只加宽剑身。
    ---@param cx number
    ---@param cy number
    ---@param angle number
    ---@param scale number
    ---@param breadth number
    local function boneSword(cx, cy, angle, scale, breadth)
        local p = projector(cx, cy, angle, scale)
        emblem(p({ { 0, -82 }, { 12 * breadth, -60 }, { 10 * breadth, 16 },
            { 5 * breadth, 29 }, { -5 * breadth, 29 }, { -10 * breadth, 16 },
            { -12 * breadth, -60 } }), BONE, GOLD)
        polygon(p({ { 0, -76 }, { 0, 23 }, { -6 * breadth, 15 },
            { -8 * breadth, -57 } }), BONE, GOLD)
        polygon(p({ { 3 * breadth, -67 }, { 9 * breadth, -56 },
            { 7 * breadth, 15 }, { 3 * breadth, 21 } }), GOLD, SHADE)
        stroke(p({ { 0, -55 }, { 0, 20 } }), 2.8 * scale, SHADE, false)
        stroke(p({ { -6 * breadth, -51 }, { -5 * breadth, 8 } }), 2 * scale, BONE, false)
        boneGrip(p, scale)
    end

    --- 骨柄长战斧：单一大弧刃与长握柄，轮廓不伪装为第二把剑。
    ---@param cx number
    ---@param cy number
    ---@param angle number
    ---@param scale number
    local function boneAxe(cx, cy, angle, scale)
        local p = projector(cx, cy, angle, scale)
        -- 长柄在斧头后方，顶部骨节与底部掌托均属于武器结构。
        stroke(p({ { 0, -81 }, { 0, 75 } }), 17 * scale, DARK, false)
        stroke(p({ { 0, -81 }, { 0, 75 } }), 10 * scale, GOLD, false)
        stroke(p({ { -2, -71 }, { -2, 17 } }), 3 * scale, BONE, false)
        emblem(p({ { 0, -92 }, { 9, -86 }, { 7, -75 }, { -7, -75 }, { -9, -86 } }), BONE, GOLD)
        local head = { { 7, -76 }, { 26, -90 } }
        curve(head, 37, -97, 51, -96, 60, -86)
        curve(head, 75, -68, 74, -35, 55, -17)
        curve(head, 45, -10, 31, -13, 24, -23)
        curve(head, 30, -43, 23, -60, 7, -61)
        emblem(p(head), BONE, GOLD)
        -- 内侧铜质斧腹与外侧骨白刃带是大色面，不靠密集波纹说明骨潮。
        local cheek = { { 13, -71 }, { 30, -81 } }
        curve(cheek, 43, -90, 54, -80, 57, -65)
        curve(cheek, 62, -44, 53, -29, 37, -24)
        curve(cheek, 39, -45, 29, -65, 13, -65)
        polygon(p(cheek), GOLD, SHADE)
        stroke(p({ { 33, -73 }, { 44, -65 }, { 46, -47 } }), 3 * scale, BONE, false)
        -- 骨节套箍包住斧眼，内凹留白仍可辨识为斧而不是扇形符号。
        emblem(p({ { -10, -70 }, { 11, -72 }, { 13, -55 }, { -9, -51 } }), BONE, GOLD)
        polygon(p({ { -4, -64 }, { 7, -65 }, { 7, -59 }, { -4, -57 } }), SHADE, DARK)
        for _, y in ipairs({ 29, 44, 59 }) do
            stroke(p({ { -6, y - 3 }, { 6, y + 3 } }), 5 * scale, SHADE, false)
            stroke(p({ { -5, y - 4 }, { 5, y + 1 } }), 2.5 * scale, BONE, false)
        end
        emblem(p({ { -8, 72 }, { 8, 72 }, { 10, 81 }, { 0, 86 }, { -10, 81 } }), BONE, GOLD)
    end

    --- 少量铆扣仅点明装备连接关系，不散布颗粒和假文字。
    ---@param x number
    ---@param y number
    local function rivet(x, y)
        ellipse(x, y, 4, 4, DARK)
        ellipse(x - 0.5, y - 0.5, 2.5, 2.5, BONE, GOLD)
    end

    if branchId == 2 then
        -- 基础拾骸者：左侧轻护肩与右侧宽骨柄战剑，绝不把骸骨画成库存图解。
        emblem({ { 75, 112 }, { 96, 99 }, { 121, 113 }, { 128, 138 },
            { 119, 166 }, { 106, 183 }, { 84, 177 }, { 70, 155 }, { 66, 131 } }, SHADE, DARK)
        emblem({ { 73, 115 }, { 94, 106 }, { 118, 119 }, { 121, 137 },
            { 108, 148 }, { 80, 146 }, { 69, 130 } }, BONE, GOLD)
        polygon({ { 77, 116 }, { 94, 110 }, { 115, 123 }, { 116, 131 },
            { 96, 121 }, { 80, 125 } }, BONE)
        emblem({ { 79, 154 }, { 111, 155 }, { 110, 170 }, { 99, 183 },
            { 84, 172 } }, GOLD, SHADE)
        -- 宽皮革连接带与两枚铜扣，没有人物躯干或背景盾盘。
        polygon({ { 86, 144 }, { 94, 145 }, { 95, 171 }, { 88, 173 } }, SHADE, DARK)
        rivet(80, 131)
        rivet(110, 135)
        boneSword(155, 138, 0.20, 1.08, 1.55)
    elseif branchId == 205 then
        -- 骨潮：一把长柄大弧刃战斧形成高耸的不对称外轮廓，不添浪花和层数符号。
        boneAxe(133, 148, 0.22, 1.03)
        -- 仅在长柄中下段增骨质握护，保留斧头内凹与柄侧的宽负空间。
        local p = projector(133, 148, 0.22, 1.03)
        emblem(p({ { -9, -1 }, { 10, -3 }, { 13, 15 }, { 8, 24 },
            { -8, 24 }, { -13, 15 } }), BONE, GOLD)
        stroke(p({ { -7, 9 }, { 8, 8 } }), 4, SHADE, false)
    elseif branchId == 206 then
        -- 骨债：宽腹祭血重剑与紧束扣具，用深槽和束带暗示自付代价，不画爱心或数字。
        -- 左侧是缠束护腕，环扣属于装备而非司仪祷环。
        emblem({ { 71, 143 }, { 96, 133 }, { 114, 143 }, { 118, 175 },
            { 108, 200 }, { 84, 205 }, { 67, 183 }, { 63, 159 } }, SHADE, DARK)
        for _, y in ipairs({ 149, 174 }) do
            emblem({ { 67, y }, { 88, y - 8 }, { 114, y - 2 }, { 114, y + 12 },
                { 89, y + 5 }, { 68, y + 12 } }, GOLD, SHADE)
            stroke({ { 72, y + 1 }, { 87, y - 3 }, { 108, y + 1 } }, 3, BONE, false)
        end
        emblem({ { 81, 151 }, { 101, 149 }, { 104, 183 }, { 85, 189 },
            { 78, 176 } }, BONE, GOLD)
        polygon({ { 86, 158 }, { 96, 157 }, { 98, 178 }, { 88, 180 } }, DARK)
        local p = projector(151, 138, -0.12, 1.02)
        emblem(p({ { 0, -92 }, { 26, -69 }, { 25, 7 }, { 17, 22 },
            { 6, 29 }, { -6, 29 }, { -17, 22 }, { -25, 7 }, { -26, -69 } }), BONE, GOLD)
        polygon(p({ { 0, -85 }, { 0, 23 }, { -17, 4 }, { -18, -62 } }), BONE, GOLD)
        polygon(p({ { 5, -79 }, { 21, -63 }, { 20, 5 }, { 9, 18 }, { 5, 16 } }), GOLD, SHADE)
        -- 一条宽沉槽与两道斜束扣，不将献血画成喷溅或额外机制图案。
        polygon(p({ { -3, -63 }, { 3, -65 }, { 4, 8 }, { 0, 19 }, { -4, 8 } }), SHADE, DARK)
        for _, y in ipairs({ -36, -11 }) do
            emblem(p({ { -24, y - 7 }, { 24, y + 3 }, { 23, y + 12 },
                { -24, y + 2 } }), GOLD, SHADE)
            polygon(p({ { -9, y - 1 }, { 8, y + 2 }, { 7, y + 7 }, { -10, y + 4 } }), DARK)
            stroke(p({ { -21, y - 3 }, { -12, y - 1 } }), 2.5, BONE, false)
        end
        boneGrip(p, 1.02)
    elseif branchId == 207 then
        -- 双械：左上宽直剑、右上单弧刃斧，两个不同类型的武器交错但各有完整握柄。
        -- 配置是不同类型双持，不能画成双剑、双斧或盾牌副手。
        boneAxe(148, 142, 0.52, 0.95)
        boneSword(128, 143, -0.52, 1.04, 1.15)
    else
        -- 连剥：一把带大齿的长战刃与层叠臂甲；连续感由战具覆片表达，不加箭头。
        emblem({ { 172, 137 }, { 195, 140 }, { 210, 165 }, { 211, 194 },
            { 197, 215 }, { 175, 208 }, { 157, 180 }, { 155, 154 } }, SHADE, DARK)
        for _, offset in ipairs({ 0, 25, 50 }) do
            local x, y = 163 + offset * 0.18, 144 + offset
            emblem({ { x, y }, { x + 23, y - 4 }, { x + 39, y + 9 },
                { x + 36, y + 25 }, { x + 17, y + 18 }, { x + 3, y + 20 } }, BONE, GOLD)
            polygon({ { x + 9, y + 7 }, { x + 23, y + 3 }, { x + 32, y + 11 },
                { x + 19, y + 10 } }, GOLD, SHADE)
        end
        -- 一根纵向皮革筋带压住覆片，避免把臂甲画成游离的三排库存。
        polygon({ { 178, 143 }, { 186, 145 }, { 196, 207 }, { 188, 211 } }, SHADE, DARK)
        rivet(182, 150)
        rivet(191, 201)
        local p = projector(120, 141, 0.48, 1.04)
        -- 大齿只留三段，齿根空隙宽；无细密锯齿、虫足或骨数量标签。
        emblem(p({ { 0, -88 }, { 20, -64 }, { 13, -51 }, { 25, -45 },
            { 13, -33 }, { 25, -24 }, { 13, -13 }, { 24, -3 },
            { 14, 9 }, { 10, 23 }, { 0, 29 }, { -12, 20 }, { -15, -63 } }), BONE, GOLD)
        polygon(p({ { -1, -78 }, { -1, 21 }, { -8, 14 }, { -10, -60 } }), BONE, GOLD)
        polygon(p({ { 4, -61 }, { 12, -55 }, { 6, -45 }, { 15, -40 },
            { 6, -29 }, { 15, -21 }, { 6, -10 }, { 14, -1 }, { 7, 12 }, { 4, 17 } }), GOLD, SHADE)
        stroke(p({ { -1, -56 }, { -1, 18 } }), 3, SHADE, false)
        boneGrip(p, 1.04)
    end
end

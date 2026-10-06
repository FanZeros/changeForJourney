-- 103/104 审核主体：沿用 generate_advancement_trials 的 CPU 多边形/曲线闭包。
-- 只发出形状；不创建画布、不读旧图、不画底板、不保存或安装 PNG。
-- 103：三层缚骨护肩与骨剑；104：保留斜骨剑剥开重甲的构图。
-- 共用骨节剑护手，以实物战具建立职业身份，不画心形或机制箭头。

---@class ReviewSpoilDraw
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

---@param d ReviewSpoilDraw
---@param branchId integer
return function(d, branchId)
    assert(branchId == 103 or branchId == 104, "ReviewSpoil只绘制103/104审核主体")
    -- 父生成器的闭包必须点调用，不把 d 当作隐含 self 传入。
    local polygon, stroke = d.polygon, d.stroke
    local ellipse, curve, emblem = d.ellipse, d.curve, d.emblem
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    --- 护肩三层弧形骨片沿用原三排结构，改为宽厚覆片而非独立库存长骨。
    ---@param cx number
    ---@param cy number
    ---@param half number
    local function shoulderRib(cx, cy, half)
        local left, right = cx - half, cx + half
        local plate = { { left, cy + 5 }, { left + 3, cy - 6 } }
        curve(plate, left + 19, cy - 17, right - 19, cy - 17, right - 3, cy - 6)
        curve(plate, right + 5, cy + 1, right + 6, cy + 8, right - 2, cy + 13)
        curve(plate, right - 17, cy + 4, left + 17, cy + 4, left + 2, cy + 13)
        emblem(plate, BONE, GOLD)
        local ridge = { { left + 7, cy - 3 } }
        curve(ridge, left + 23, cy - 11, right - 23, cy - 11, right - 7, cy - 3)
        stroke(ridge, 3, BONE, false)
        -- 每层只保留一道宽骨脊，层间空隙由真实轮廓留出。
        stroke({ { right - 9, cy + 2 }, { right - 6, cy + 7 } }, 3, SHADE, false)
    end

    --- 共用骨剑：局部坐标几何投影，不另建画布或改父生成器变换。
    ---@param cx number
    ---@param cy number
    ---@param angle number
    ---@param scale number
    local function boneSword(cx, cy, angle, scale)
        local cosine, sine = math.cos(angle), math.sin(angle)
        ---@param points number[][]
        ---@return number[][]
        local function projected(points)
            local result = {}
            for _, p in ipairs(points) do
                result[#result + 1] = { cx + (p[1] * cosine - p[2] * sine) * scale,
                    cy + (p[1] * sine + p[2] * cosine) * scale }
            end
            return result
        end
        ---@param points number[][]
        ---@param width number
        ---@param color number[]
        local function bladeStroke(points, width, color)
            stroke(projected(points), width * scale, color, false)
        end
        -- 宽脊剑身与左右明暗面，轮廓不做狭长针尖。
        emblem(projected({ { 0, -82 }, { 12, -60 }, { 10, 16 }, { 5, 29 },
            { -5, 29 }, { -10, 16 }, { -12, -60 } }), BONE, GOLD)
        polygon(projected({ { 0, -76 }, { 0, 23 }, { -6, 15 }, { -8, -57 } }), BONE, GOLD)
        polygon(projected({ { 3, -67 }, { 9, -56 }, { 7, 15 }, { 3, 21 } }), GOLD, SHADE)
        bladeStroke({ { 0, -55 }, { 0, 20 } }, 2.8, SHADE)
        bladeStroke({ { -6, -51 }, { -5, 8 } }, 2, BONE)
        -- 两只上弯骨节护手，不是直横杆/宗教十字。
        for _, side in ipairs({ -1, 1 }) do
            emblem(projected({ { side * 3, 25 }, { side * 14, 29 }, { side * 23, 22 },
                { side * 24, 30 }, { side * 17, 39 }, { side * 8, 36 } }), BONE, GOLD)
            bladeStroke({ { side * 10, 29 }, { side * 17, 32 }, { side * 21, 27 } }, 2.2, BONE)
        end
        bladeStroke({ { 0, 35 }, { 0, 66 } }, 15, DARK)
        bladeStroke({ { 0, 36 }, { 0, 66 } }, 8, GOLD)
        -- 三节粗缠带也是拾骸者共有的骨质握柄，非文字/计数标签。
        for _, y in ipairs({ 43, 52, 61 }) do
            bladeStroke({ { -4, y - 2 }, { 4, y + 1 } }, 3.2, SHADE)
            bladeStroke({ { -4, y - 3 }, { 3, y - 1 } }, 1.8, BONE)
        end
        emblem(projected({ { 0, 66 }, { 9, 73 }, { 6, 79 }, { -6, 79 }, { -9, 73 } }), BONE, GOLD)
    end

    if branchId == 103 then
        -- 骨市：保留左侧三排和右侧骨剑的位置，三排改成可穿戴的缚骨护肩。
        -- 缚带与下缘臂护均是装备结构，不用库存计数、心形或回流箭说明天赋。
        emblem({ { 97, 76 }, { 125, 74 }, { 144, 97 }, { 146, 160 },
            { 127, 186 }, { 99, 180 }, { 84, 151 }, { 81, 113 } }, SHADE, DARK)
        shoulderRib(110, 99, 43)
        shoulderRib(114, 134, 39)
        shoulderRib(112, 168, 33)
        -- 旧铜纵向缚带把三层骨覆片连成护肩，留出两侧的大块骨白。
        emblem({ { 107, 83 }, { 117, 82 }, { 126, 172 }, { 116, 185 },
            { 108, 176 }, { 103, 106 } }, GOLD, SHADE)
        stroke({ { 110, 91 }, { 118, 171 } }, 3, BONE, false)
        for _, y in ipairs({ 115, 150 }) do
            emblem({ { 104, y }, { 124, y - 1 }, { 125, y + 10 }, { 105, y + 11 } }, GOLD, SHADE)
            polygon({ { 110, y + 3 }, { 120, y + 2 }, { 120, y + 7 }, { 110, y + 8 } }, DARK)
        end
        -- 下缘短臂护代替原来独立心形，仍沿原构图的左下重心收尾。
        emblem({ { 92, 189 }, { 115, 191 }, { 132, 186 }, { 135, 205 },
            { 122, 220 }, { 101, 220 }, { 89, 207 } }, BONE, GOLD)
        polygon({ { 97, 204 }, { 126, 204 }, { 121, 214 }, { 103, 214 } }, GOLD, SHADE)
        boneSword(186, 140, 0, 1)
    else
        -- 剥壳：两大片甲壳沿斜骨剑分离；暗色裂口是开阔负空间而非细黑线。
        -- 配置是击杀精英/首领得骸骨 + 优先护甲克制目标，不是无条件破甲。
        local upperShell = { { 94, 77 }, { 126, 69 }, { 151, 80 }, { 165, 91 },
            { 146, 104 }, { 151, 116 }, { 129, 127 }, { 130, 140 }, { 106, 147 },
            { 99, 162 }, { 80, 165 }, { 64, 139 }, { 64, 110 }, { 77, 87 } }
        local lowerShell = { { 205, 98 }, { 220, 129 }, { 214, 163 }, { 196, 195 },
            { 162, 214 }, { 132, 208 }, { 119, 194 }, { 139, 180 }, { 135, 165 },
            { 158, 152 }, { 160, 137 }, { 183, 129 }, { 187, 115 } }
        emblem(upperShell, GOLD, SHADE)
        emblem(lowerShell, GOLD, SHADE)
        polygon({ { 96, 82 }, { 126, 77 }, { 151, 89 }, { 137, 99 },
            { 110, 94 }, { 87, 102 }, { 70, 121 }, { 72, 104 } }, BONE, GOLD)
        polygon({ { 205, 119 }, { 212, 132 }, { 207, 160 }, { 190, 188 },
            { 164, 203 }, { 146, 203 }, { 164, 191 }, { 188, 170 } }, GOLD, DARK)
        -- 粗宽甲片脊：保留简洁大面，不画满身鳞片和虫足。
        stroke({ { 78, 113 }, { 97, 104 }, { 120, 109 }, { 137, 111 } }, 7, DARK, false)
        stroke({ { 79, 110 }, { 98, 102 }, { 120, 106 }, { 137, 108 } }, 3, BONE, false)
        stroke({ { 77, 137 }, { 95, 128 }, { 117, 133 } }, 6, DARK, false)
        stroke({ { 78, 134 }, { 96, 125 }, { 117, 130 } }, 2.8, GOLD, false)
        stroke({ { 171, 146 }, { 193, 151 }, { 207, 145 } }, 6, DARK, false)
        stroke({ { 173, 143 }, { 193, 148 }, { 206, 142 } }, 3, BONE, false)
        stroke({ { 148, 181 }, { 167, 185 }, { 191, 171 } }, 6, DARK, false)
        stroke({ { 149, 178 }, { 167, 182 }, { 191, 168 } }, 3, GOLD, false)
        -- 少量大铜钉给“强敌重甲”尺度感，避免皇冠/人物头像暗示。
        for _, p in ipairs({ { 91, 87 }, { 83, 152 }, { 206, 132 }, { 174, 199 } }) do
            ellipse(p[1], p[2], 4.2, 4.2, DARK)
            ellipse(p[1] - 0.6, p[2] - 0.6, 2.8, 2.8, BONE, GOLD)
        end
        -- 脱开的两片保留原形，添宽皮革束带与边缘包条，明确是强敌穿戴的重甲。
        polygon({ { 68, 114 }, { 79, 111 }, { 89, 151 }, { 79, 159 }, { 72, 142 } }, SHADE, DARK)
        stroke({ { 73, 119 }, { 79, 145 } }, 3, GOLD, false)
        polygon({ { 196, 156 }, { 207, 150 }, { 204, 166 }, { 185, 193 },
            { 175, 196 }, { 179, 186 } }, SHADE, DARK)
        stroke({ { 202, 160 }, { 184, 186 } }, 3, GOLD, false)
        -- 两块剥落碎片与主体留明显空隙，不借绘制裁剪掩盖越界。
        emblem({ { 195, 78 }, { 207, 76 }, { 215, 87 }, { 204, 91 } }, BONE, GOLD)
        emblem({ { 60, 171 }, { 76, 178 }, { 72, 192 }, { 60, 184 } }, GOLD, SHADE)
        boneSword(141, 131, math.pi / 4, 1.15)
    end
end

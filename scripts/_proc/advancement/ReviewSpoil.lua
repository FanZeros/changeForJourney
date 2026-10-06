-- 103/104 审核主体：沿用 generate_advancement_trials 的 CPU 多边形/曲线闭包。
-- 只发出形状；不创建画布、不读旧图、不画底板、不保存或安装 PNG。
-- 103：三排可辨识的库存长骨 + 消耗回流的心形；104：斜骨剑剥开两片重甲。
-- 共用骨节剑护手，不用十字、皇冠、星芒或别的职业徽记。

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
    local polygon, line, stroke = d.polygon, d.line, d.stroke
    local ellipse, curve, emblem = d.ellipse, d.curve, d.emblem
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE

    --- 库存长骨有完整双髁轮廓，排间负空间不靠细刻线表达。
    ---@param cx number
    ---@param cy number
    ---@param half number
    local function reserveBone(cx, cy, half)
        local left, right = cx - half, cx + half
        local bone = { { left + 12, cy - 6 } }
        curve(bone, left + 8, cy - 16, left - 2, cy - 16, left - 5, cy - 9)
        curve(bone, left - 12, cy - 5, left - 12, cy + 5, left - 5, cy + 9)
        curve(bone, left - 2, cy + 16, left + 8, cy + 16, left + 12, cy + 6)
        curve(bone, left + 24, cy + 3, right - 24, cy + 3, right - 12, cy + 6)
        curve(bone, right - 8, cy + 16, right + 2, cy + 16, right + 5, cy + 9)
        curve(bone, right + 12, cy + 5, right + 12, cy - 5, right + 5, cy - 9)
        curve(bone, right + 2, cy - 16, right - 8, cy - 16, right - 12, cy - 6)
        curve(bone, right - 24, cy - 3, left + 24, cy - 3, left + 12, cy - 6)
        emblem(bone, BONE, GOLD)
        line(left + 15, cy - 2, right - 15, cy - 2, 3, BONE)
        line(left + 17, cy + 4, right - 17, cy + 4, 2.6, SHADE)
        -- 每端只留一道粗关节凹口，缩到64px不会变成细碎噪声。
        line(left - 4, cy - 4, left, cy + 4, 3, SHADE)
        line(right + 4, cy - 4, right, cy + 4, 3, SHADE)
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
        -- 骨市：左侧三排满储长骨，右侧直立骨剑；下方的心形承接消耗回流。
        -- 绝不把12→18的层数误画成三柄武器或治疗职业的圣徽。
        boneSword(186, 140, 0, 1)
        reserveBone(110, 96, 33)
        reserveBone(114, 132, 36)
        reserveBone(110, 168, 33)
        -- 两段铜色夹扣将“叠骨库存”连成一组，不另画箱子/第二层底板。
        for _, y in ipairs({ 111, 147 }) do
            emblem({ { 101, y }, { 119, y }, { 119, y + 5 }, { 101, y + 5 } }, GOLD, SHADE)
            line(104, y + 1, 116, y + 1, 1.8, BONE)
        end
        -- 消耗路径仅一条粗弯箭，来自库存而非从敌人抽血。
        local returnFlow = { { 147, 179 } }
        curve(returnFlow, 169, 188, 165, 201, 143, 205)
        stroke(returnFlow, 9, DARK, false)
        stroke(returnFlow, 4.2, GOLD, false)
        emblem({ { 137, 206 }, { 146, 196 }, { 149, 208 } }, BONE, GOLD)
        -- 不用十字/加号：骨白旧铜心形直接表达回复已损生命。
        local heart = { { 118, 202 } }
        curve(heart, 107, 187, 88, 196, 96, 211)
        curve(heart, 101, 219, 112, 225, 118, 231)
        curve(heart, 124, 225, 135, 219, 140, 211)
        curve(heart, 148, 196, 129, 187, 118, 202)
        emblem(heart, BONE, GOLD)
        polygon({ { 121, 204 }, { 135, 201 }, { 134, 210 }, { 120, 226 } }, GOLD, SHADE)
        stroke({ { 102, 201 }, { 100, 206 }, { 109, 216 } }, 3, BONE, false)
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
        -- 两块剥落碎片与主体留明显空隙，不借绘制裁剪掩盖越界。
        emblem({ { 195, 78 }, { 207, 76 }, { 215, 87 }, { 204, 91 } }, BONE, GOLD)
        emblem({ { 60, 171 }, { 76, 178 }, { 72, 192 }, { 60, 184 } }, GOLD, SHADE)
        boneSword(141, 131, math.pi / 4, 1.15)
    end
end

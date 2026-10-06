-- 回响客基础4与二转213–216：仅绘制职业装备主体，不创建画布、不读图、不落盘。
-- 底板/预乘降采样/安装由主生成器负责；主协调冻结后统一官方build。
-- 配置对照：4回响（延迟追加伤害）；213风回（回响命中叠攻速）；214瞳回（回响必暴击）；
-- 215瞄回（物理穿透+10）；216重回（超过100%的攻速转换为回响伤害）。
-- 职业感优先：短弓箭囊 / 长弓臂甲 / 风帽猎手 / 精准穿甲弩 / 绞盘重弩。
-- 几何来源：从ReviewEcho107/108提取反曲弓贝塞尔、握柄/弦扣与实体箭轴向辅助；
-- 不截取绘图调用序号，不依赖ReviewEcho的调用顺序，不改原审核模块。
-- 新轮廓与原辅助以显式仿射坐标组合；不沿用残影、两层箭、光晕或机制图解。

---@class AdvancementBatchEchoDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field ellipse fun(cx: number, cy: number, rx: number, ry: number, top: number[], bottom?: number[])
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d AdvancementBatchEchoDraw
---@param id number
return function(d, id)
    assert(id == 4 or id == 213 or id == 214 or id == 215 or id == 216,
        "BatchEcho只绘制基础4及二转213/214/215/216")
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE
    local CENTER, LIMIT = 139.5, 110

    -- 所有实际路径点连同圆头描边都限定在半径110内，外圈114不参与主体绘制。
    -- 圆盘为凸集，端点/顶点安全即可保证线段/多边形安全；emblem按父7px暗描边计。
    ---@param points number[][]
    ---@param padding number
    local function check(points, padding)
        for _, p in ipairs(points) do
            local dx, dy = p[1] - CENTER, p[2] - CENTER
            assert(math.sqrt(dx * dx + dy * dy) + padding <= LIMIT,
                "BatchEcho主体或描边越界：" .. tostring(id))
        end
    end

    ---@param points number[][]
    ---@param top number[]
    ---@param bottom? number[]
    local function polygon(points, top, bottom)
        check(points, 0)
        d.polygon(points, top, bottom)
    end

    ---@param points number[][]
    ---@param top? number[]
    ---@param bottom? number[]
    local function emblem(points, top, bottom)
        check(points, 3.5)
        d.emblem(points, top or BONE, bottom or GOLD)
    end

    ---@param points number[][]
    ---@param width number
    ---@param color number[]
    ---@param closed? boolean
    local function stroke(points, width, color, closed)
        check(points, width * 0.5)
        d.stroke(points, width, color, closed or false)
    end

    ---@param x0 number
    ---@param y0 number
    ---@param x1 number
    ---@param y1 number
    ---@param width number
    ---@param color number[]
    local function line(x0, y0, x1, y1, width, color)
        check({ { x0, y0 }, { x1, y1 } }, width * 0.5)
        d.line(x0, y0, x1, y1, width, color)
    end

    ---@param x number
    ---@param y number
    ---@param rx number
    ---@param ry number
    ---@param top number[]
    ---@param bottom? number[]
    local function ellipse(x, y, rx, ry, top, bottom)
        -- 以外接圆作保守边界，不用裁剪把越界形状硬截回去。
        check({ { x, y } }, math.max(rx, ry))
        d.ellipse(x, y, rx, ry, top, bottom)
    end

    -- 复用几何的坐标源明确固定为ReviewEcho弓身中心(101,141)，不引用图像/旧环。
    ---@param cx number
    ---@param cy number
    ---@param sx number
    ---@param sy number
    ---@param degrees number
    ---@return fun(x: number, y: number): number[]
    local function bowSpace(cx, cy, sx, sy, degrees)
        local angle = degrees * math.pi / 180
        local cosine, sine = math.cos(angle), math.sin(angle)
        return function(x, y)
            local dx, dy = (x - 101) * sx, (y - 141) * sy
            return { cx + dx * cosine - dy * sine, cy + dx * sine + dy * cosine }
        end
    end

    ---@param map fun(x: number, y: number): number[]
    ---@param points number[][]
    ---@param x1 number
    ---@param y1 number
    ---@param x2 number
    ---@param y2 number
    ---@param x3 number
    ---@param y3 number
    local function mappedCurve(map, points, x1, y1, x2, y2, x3, y3)
        local a, b, c = map(x1, y1), map(x2, y2), map(x3, y3)
        d.curve(points, a[1], a[2], b[1], b[2], c[1], c[2])
    end

    -- ReviewEcho107/108共用反曲弓轮廓：开放弓腹、骨白弓臂、铜侧面、皮革握柄。
    -- 仿射改变长短/朝向而不改变封闭轮廓拓扑；描边保持父渲染器7px宽。
    ---@param map fun(x: number, y: number): number[]
    local function recurvedBow(map)
        local bow = { map(132, 59) }
        mappedCurve(map, bow, 122, 66, 126, 78, 118, 89)
        mappedCurve(map, bow, 108, 104, 72, 103, 64, 130)
        mappedCurve(map, bow, 55, 155, 91, 183, 116, 196)
        mappedCurve(map, bow, 127, 203, 124, 215, 132, 221)
        mappedCurve(map, bow, 143, 218, 141, 210, 135, 202)
        mappedCurve(map, bow, 132, 191, 133, 184, 118, 174)
        mappedCurve(map, bow, 102, 163, 88, 155, 86, 139)
        mappedCurve(map, bow, 83, 120, 113, 116, 129, 99)
        mappedCurve(map, bow, 141, 85, 144, 68, 132, 59)
        emblem(bow, BONE, GOLD)

        local side = { map(72, 134) }
        mappedCurve(map, side, 65, 155, 102, 179, 122, 190)
        mappedCurve(map, side, 120, 179, 102, 170, 93, 157)
        mappedCurve(map, side, 84, 146, 89, 139, 87, 128)
        mappedCurve(map, side, 82, 130, 76, 131, 72, 134)
        polygon(side, GOLD, SHADE)
        local bevel = { map(128, 66) }
        mappedCurve(map, bevel, 125, 91, 103, 103, 84, 113)
        mappedCurve(map, bevel, 76, 118, 69, 125, 68, 135)
        stroke(bevel, 3.4, BONE)

        local string = { map(133, 66), map(123, 140), map(134, 214) }
        stroke(string, 7, DARK)
        stroke(string, 3.2, BONE)
        emblem({ map(68, 129), map(82, 128), map(87, 151), map(76, 158), map(65, 146) }, GOLD, SHADE)
        for _, band in ipairs({ { 69, 134, 82, 132 }, { 70, 143, 84, 141 }, { 75, 151, 85, 148 } }) do
            local a, b = map(band[1], band[2]), map(band[3], band[4])
            line(a[1], a[2], b[1], b[2], 3, DARK)
        end
        emblem({ map(127, 59), map(136, 59), map(139, 68), map(131, 74), map(126, 69) }, GOLD, SHADE)
        emblem({ map(126, 211), map(136, 208), map(140, 217), map(132, 224), map(126, 219) }, GOLD, SHADE)
    end

    -- ReviewEcho实体箭的轴向构造：宽杆/双羽尾/金属刃；本批只画真实装填箭。
    -- 细长刃/宽重刃属于装备结构区别，不用额外箭头代表穿透或层数。
    ---@param sx number
    ---@param sy number
    ---@param tx number
    ---@param ty number
    ---@param widthScale number
    ---@param headLength number
    local function loadedArrow(sx, sy, tx, ty, widthScale, headLength)
        local dx, dy = tx - sx, ty - sy
        local length = math.sqrt(dx * dx + dy * dy)
        local ux, uy = dx / length, dy / length
        ---@param along number
        ---@param across number
        ---@return number[]
        local function p(along, across)
            local side = across * widthScale
            return { sx + ux * along - uy * side, sy + uy * along + ux * side }
        end
        emblem({ p(-10, -4), p(length - headLength + 6, -4),
            p(length - headLength + 6, 4), p(-10, 4) }, BONE, GOLD)
        emblem({ p(-18, -14), p(5, -14), p(19, -3), p(-5, -3) }, BONE, GOLD)
        emblem({ p(-5, 3), p(19, 3), p(5, 14), p(-18, 14) }, GOLD, SHADE)
        emblem({ p(length, 0), p(length - headLength, -13),
            p(length - headLength + 7, 0), p(length - headLength, 13) }, BONE, GOLD)
        polygon({ p(length, 0), p(length - headLength + 7, 0),
            p(length - headLength, 13) }, GOLD, SHADE)
        local a, b = p(8, -1.8), p(length - headLength + 3, -1.8)
        line(a[1], a[2], b[1], b[2], 2.5, BONE)
    end

    -- 皮革箭囊：箭头入袋，露出两枚完整羽尾与硬囊口；不是同向两层机制箭。
    ---@param x number
    ---@param y number
    local function quiver(x, y)
        for _, offset in ipairs({ -13, 13 }) do
            line(x + offset, y - 55, x + offset + 13, y + 24, 10, DARK)
            line(x + offset, y - 55, x + offset + 13, y + 24, 4.5, BONE)
            emblem({ { x + offset - 9, y - 69 }, { x + offset + 5, y - 63 },
                { x + offset + 7, y - 45 }, { x + offset - 4, y - 50 } }, BONE, GOLD)
        end
        emblem({ { x - 31, y - 19 }, { x + 26, y - 24 }, { x + 30, y - 7 },
            { x + 20, y + 71 }, { x + 3, y + 81 }, { x - 15, y + 73 } }, GOLD, SHADE)
        polygon({ { x - 22, y - 8 }, { x + 18, y - 12 }, { x + 13, y + 64 },
            { x + 3, y + 70 }, { x - 8, y + 64 } }, SHADE, DARK)
        emblem({ { x - 31, y - 19 }, { x + 26, y - 24 }, { x + 30, y - 10 },
            { x - 27, y - 5 } }, BONE, GOLD)
        emblem({ { x - 18, y + 31 }, { x + 21, y + 27 }, { x + 20, y + 43 },
            { x - 15, y + 48 } }, GOLD, SHADE)
        emblem({ { x - 3, y + 27 }, { x + 11, y + 26 }, { x + 11, y + 46 },
            { x - 3, y + 47 } }, BONE, GOLD)
        line(x - 24, y + 1, x - 12, y + 61, 3, GOLD)
        line(x + 4, y + 32, x + 4, y + 42, 3.5, DARK)
    end

    -- 三片连射护臂：厚皮革底、开放绑带与三块叠接硬片，层数只作为实物板甲分节。
    ---@param x number
    ---@param y number
    local function bracer(x, y)
        emblem({ { x - 23, y - 49 }, { x + 21, y - 54 }, { x + 29, y + 43 },
            { x + 13, y + 55 }, { x - 20, y + 49 } }, GOLD, SHADE)
        polygon({ { x - 13, y - 43 }, { x + 12, y - 46 }, { x + 18, y + 43 },
            { x - 12, y + 41 } }, SHADE, DARK)
        for _, offset in ipairs({ -31, 0, 31 }) do
            emblem({ { x - 24, y + offset - 10 }, { x + 22, y + offset - 14 },
                { x + 24, y + offset + 7 }, { x - 22, y + offset + 13 } }, BONE, GOLD)
            polygon({ { x - 19, y + offset + 4 }, { x + 22, y + offset },
                { x + 24, y + offset + 7 }, { x - 22, y + offset + 13 } }, GOLD, SHADE)
        end
        line(x + 1, y - 40, x + 5, y + 39, 5, DARK)
        line(x - 7, y - 38, x - 3, y + 39, 2.8, BONE)
    end

    if id == 4 then
        -- 回响客：朴素短反曲弓＋背挂箭囊，先建立游侠轮廓，再谈延迟追加伤害。
        -- 预留大块负空间，基础职不画漂浮箭/声波/计时符号。
        quiver(171, 135)
        recurvedBow(bowSpace(103, 142, 0.94, 0.97, -7))
    elseif id == 213 then
        -- 风回：轻量长弓配分节射手护臂，表现持续命中后的快速引弦。
        -- 弓比基础职更长且上/下开放；前方只有一支真正搭弦的箭。
        bracer(174, 161)
        recurvedBow(bowSpace(105, 137, 0.88, 1.08, -7))
        loadedArrow(106, 142, 221, 111, 0.82, 31)
    elseif id == 214 then
        -- 瞳回：风帽狙手＋侧挂短弓与长刃箭，保证暴击对应稳定瞄准的职业身份。
        -- 窄视窗嵌入真实兜帽，不另画眼睛徽记/瞄准十字或星芒。
        recurvedBow(bowSpace(197, 147, 0.63, 0.77, 5))
        local hood = { { 94, 94 } }
        d.curve(hood, 101, 69, 119, 55, 137, 53)
        d.curve(hood, 158, 60, 176, 79, 183, 105)
        d.curve(hood, 188, 142, 183, 181, 163, 202)
        d.curve(hood, 151, 213, 127, 216, 105, 204)
        d.curve(hood, 87, 184, 86, 132, 94, 94)
        emblem(hood, GOLD, SHADE)
        polygon({ { 101, 103 }, { 118, 87 }, { 136, 75 }, { 162, 99 },
            { 172, 128 }, { 162, 173 }, { 138, 195 }, { 113, 179 }, { 99, 139 } }, DARK)
        emblem({ { 98, 109 }, { 107, 85 }, { 136, 62 }, { 143, 77 },
            { 118, 104 }, { 112, 146 }, { 120, 181 }, { 103, 172 }, { 94, 140 } }, BONE, GOLD)
        emblem({ { 146, 79 }, { 163, 93 }, { 176, 119 }, { 174, 159 },
            { 164, 182 }, { 148, 195 }, { 139, 185 }, { 156, 162 }, { 164, 126 } }, BONE, GOLD)
        emblem({ { 100, 181 }, { 120, 184 }, { 139, 202 }, { 157, 184 },
            { 169, 191 }, { 157, 215 }, { 139, 222 }, { 119, 214 } }, GOLD, SHADE)
        line(121, 127, 151, 125, 10, SHADE)
        line(124, 128, 151, 126, 4.5, BONE)
        loadedArrow(83, 178, 104, 84, 0.66, 37)
    else
        -- 两类弩都具备真实横弓臂、绷弦、纵向弩床、皮革握把和单支装填弩矢。
        -- 瞄回为窄臂长穿甲矢；重回为宽叠片弓臂与绞盘蓄力，非同图换色。
        if id == 215 then
            emblem({ { 127, 104 }, { 151, 104 }, { 156, 183 }, { 168, 210 },
                { 162, 225 }, { 140, 232 }, { 124, 221 }, { 128, 183 } }, GOLD, SHADE)
            polygon({ { 133, 110 }, { 145, 110 }, { 150, 183 }, { 141, 214 },
                { 132, 212 } }, SHADE, DARK)
            -- 窄长反曲臂保留开阔的弦三角，弩床细长且不装笨重配件。
            emblem({ { 57, 88 }, { 70, 90 }, { 87, 108 }, { 118, 112 },
                { 139, 107 }, { 161, 112 }, { 192, 108 }, { 210, 90 },
                { 222, 88 }, { 217, 111 }, { 196, 126 }, { 164, 129 },
                { 139, 120 }, { 114, 129 }, { 82, 126 }, { 61, 111 } }, BONE, GOLD)
            polygon({ { 61, 104 }, { 85, 117 }, { 115, 120 }, { 139, 114 },
                { 164, 120 }, { 193, 117 }, { 218, 104 }, { 214, 114 },
                { 194, 126 }, { 165, 127 }, { 139, 119 }, { 113, 127 }, { 83, 124 } }, GOLD, SHADE)
            stroke({ { 63, 94 }, { 139, 165 }, { 216, 94 } }, 8, DARK)
            stroke({ { 63, 94 }, { 139, 165 }, { 216, 94 } }, 3.8, BONE)
            emblem({ { 121, 129 }, { 157, 129 }, { 157, 147 }, { 121, 147 } }, GOLD, SHADE)
            loadedArrow(139, 161, 139, 43, 0.64, 39)
            -- 握把绑带是厚实皮革结构；侧面小圆轴为扣弦机，不是瞄准徽章。
            emblem({ { 122, 190 }, { 152, 189 }, { 158, 209 }, { 128, 216 } }, BONE, GOLD)
            line(127, 198, 151, 195, 4.5, DARK)
            line(132, 207, 154, 203, 4.5, DARK)
            ellipse(163, 173, 8, 8, DARK)
            ellipse(163, 173, 4.5, 4.5, GOLD, SHADE)
        else
            emblem({ { 120, 116 }, { 160, 116 }, { 164, 184 }, { 184, 210 },
                { 177, 226 }, { 143, 235 }, { 114, 223 }, { 113, 205 }, { 124, 181 } }, BONE, GOLD)
            polygon({ { 132, 119 }, { 149, 119 }, { 155, 184 }, { 164, 209 },
                { 146, 221 }, { 128, 207 } }, GOLD, SHADE)
            -- 宽重弓臂大块铜侧面，尖端前扣；与窄精弩的薄臂完全不同。
            emblem({ { 46, 114 }, { 57, 100 }, { 75, 108 }, { 84, 122 },
                { 110, 117 }, { 139, 111 }, { 169, 117 }, { 195, 122 },
                { 204, 108 }, { 221, 100 }, { 233, 114 }, { 226, 140 },
                { 206, 153 }, { 176, 149 }, { 140, 137 }, { 104, 149 },
                { 74, 153 }, { 53, 140 } }, BONE, GOLD)
            polygon({ { 52, 126 }, { 77, 137 }, { 107, 132 }, { 140, 124 },
                { 173, 132 }, { 202, 137 }, { 227, 126 }, { 222, 141 },
                { 205, 150 }, { 175, 146 }, { 140, 136 }, { 104, 146 }, { 75, 150 }, { 57, 140 } }, GOLD, SHADE)
            stroke({ { 58, 116 }, { 139, 169 }, { 221, 116 } }, 11, DARK)
            stroke({ { 58, 116 }, { 139, 169 }, { 221, 116 } }, 5.5, BONE)
            -- 中央加厚弓桥与宽刃弩矢连成整件武器，不额外画攻速标记。
            emblem({ { 112, 125 }, { 167, 125 }, { 171, 146 }, { 109, 146 } }, GOLD, SHADE)
            loadedArrow(139, 159, 139, 60, 1.16, 36)
            emblem({ { 112, 184 }, { 168, 184 }, { 175, 205 }, { 168, 216 },
                { 116, 216 }, { 106, 205 } }, GOLD, SHADE)
            line(120, 188, 120, 208, 6, DARK)
            line(140, 188, 140, 211, 6, DARK)
            line(160, 188, 160, 208, 6, DARK)
            -- 双绞盘和短回绳表达储能重弩；轮盘贴在弩床上，不作光环底盘。
            for _, x in ipairs({ 110, 171 }) do
                ellipse(x, 175, 11.5, 11.5, DARK)
                ellipse(x, 175, 8, 8, BONE, GOLD)
                line(x - 3, 175, x + 3, 175, 4.5, SHADE)
            end
            stroke({ { 110, 179 }, { 110, 188 }, { 128, 191 } }, 7, DARK)
            stroke({ { 110, 179 }, { 110, 188 }, { 128, 191 } }, 3.5, GOLD)
            stroke({ { 171, 179 }, { 171, 188 }, { 155, 191 } }, 7, DARK)
            stroke({ { 171, 179 }, { 171, 188 }, { 155, 191 } }, 3.5, GOLD)
        end
    end
end

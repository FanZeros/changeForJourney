-- 第一批司仪职业主体：6 / 221战祷 / 222血祷 / 223大赦 / 224罚忏。
-- 基于 generate_advancement_trials 与 Review 模块的 CPU 闭包接口，不另建绘图管线。
-- 只绘主体：底板、Image、像素、降采样、PNG、安装和 Dispose 均由父生成器负责。
-- 111/112 是已审核骨白旧铜圣铃，只借用材质语言；白名单明确拒绝重绘它们。
-- 280设计空间，中心139.5；所有几何连描边在半径108内，越界直接断言而非裁切。
-- 五图按职业器物区分：手铃 / 持铃仪式护腕 / 续命祷灯 / 展开祷书 / 罩铃权杖。
-- 不画技能流程、数字、文字、爱心加号、箭头、人物、皇冠、十字、光晕或第二底盘。

---@class AdvancementBatchPrayerDraw
---@field polygon fun(points: number[][], top: number[], bottom?: number[], opacity?: number)
---@field line fun(x0: number, y0: number, x1: number, y1: number, width: number, color: number[], opacity?: number)
---@field stroke fun(points: number[][], width: number, color: number[], closed?: boolean, opacity?: number)
---@field ellipse fun(cx: number, cy: number, rx: number, ry: number, top: number[], bottom?: number[])
---@field arc fun(cx: number, cy: number, rx: number, ry: number, first: number, last: number, width: number, color: number[])
---@field curve fun(points: number[][], c1x: number, c1y: number, c2x: number, c2y: number, endx: number, endy: number)
---@field emblem fun(points: number[][], top?: number[], bottom?: number[])
---@field star fun(cx: number, cy: number, radius: number, color: number[])
---@field DARK number[]
---@field GOLD number[]
---@field BONE number[]
---@field SHADE number[]

---@param d AdvancementBatchPrayerDraw
---@param id integer
return function(d, id)
    assert(id == 6 or id == 221 or id == 222 or id == 223 or id == 224,
        "BatchPrayer只允许6/221/222/223/224，禁止重绘111/112")
    local DARK, GOLD, BONE, SHADE = d.DARK, d.GOLD, d.BONE, d.SHADE
    local curve = d.curve
    local CENTER, LIMIT = 139.5, 108

    -- 这些薄封装只检查父闭包的几何包络，不接管像素、裁剪或绘制语义。
    -- 圆形安全域是凸集；线段和填充多边形只需验证端点/顶点及圆头描边半宽。
    ---@param x number
    ---@param y number
    ---@param padding number
    local function inBounds(x, y, padding)
        local dx, dy = x - CENTER, y - CENTER
        assert(math.sqrt(dx * dx + dy * dy) + padding <= LIMIT,
            "BatchPrayer主体越过108安全半径，id=" .. tostring(id))
    end

    ---@param points number[][]
    ---@param padding number
    local function checkPoints(points, padding)
        for _, p in ipairs(points) do inBounds(p[1], p[2], padding) end
    end

    ---@param points number[][]
    ---@param top number[]
    ---@param bottom number[]|nil
    ---@param opacity number|nil
    local function polygon(points, top, bottom, opacity)
        checkPoints(points, 0)
        d.polygon(points, top, bottom, opacity)
    end

    ---@param points number[][]
    ---@param width number
    ---@param color number[]
    ---@param closed boolean|nil
    ---@param opacity number|nil
    local function stroke(points, width, color, closed, opacity)
        checkPoints(points, width * 0.5)
        d.stroke(points, width, color, closed, opacity)
    end

    ---@param x0 number
    ---@param y0 number
    ---@param x1 number
    ---@param y1 number
    ---@param width number
    ---@param color number[]
    ---@param opacity number|nil
    local function line(x0, y0, x1, y1, width, color, opacity)
        inBounds(x0, y0, width * 0.5)
        inBounds(x1, y1, width * 0.5)
        d.line(x0, y0, x1, y1, width, color, opacity)
    end

    ---@param cx number
    ---@param cy number
    ---@param rx number
    ---@param ry number
    ---@param top number[]
    ---@param bottom number[]|nil
    local function ellipse(cx, cy, rx, ry, top, bottom)
        -- 外接圆比真实椭圆更严格，避免只检查四个端点却漏掉斜向极值。
        inBounds(cx, cy, math.max(rx, ry))
        d.ellipse(cx, cy, rx, ry, top, bottom)
    end

    ---@param cx number
    ---@param cy number
    ---@param rx number
    ---@param ry number
    ---@param first number
    ---@param last number
    ---@param width number
    ---@param color number[]
    local function arc(cx, cy, rx, ry, first, last, width, color)
        inBounds(cx, cy, math.max(rx, ry) + width * 0.5)
        d.arc(cx, cy, rx, ry, first, last, width, color)
    end

    ---@param points number[][]
    ---@param top number[]|nil
    ---@param bottom number[]|nil
    local function emblem(points, top, bottom)
        -- 父 emblem 固定使用7px暗描边，不能按细金线1.5px来估边界。
        checkPoints(points, 3.5)
        d.emblem(points, top, bottom)
    end

    -- 共用圣铃只统一工艺，不统一五图轮廓。基础铃简洁；进阶铃多一圈厚铜套箍。
    -- 局部坐标投影不修改父生成器的中心、底板或缩放；曲线仍由父 curve 展开。
    ---@param cx number
    ---@param cy number
    ---@param size number
    ---@param refined boolean
    local function bell(cx, cy, size, refined)
        ---@param points number[][]
        ---@return number[][]
        local function project(points)
            local result = {}
            for _, p in ipairs(points) do
                result[#result + 1] = { cx + p[1] * size, cy + p[2] * size }
            end
            return result
        end

        ---@param points number[][]
        ---@param width number
        ---@param color number[]
        ---@param closed boolean|nil
        local function edge(points, width, color, closed)
            stroke(project(points), width * size, color, closed)
        end

        -- 完整提环、短柄、外张钟口和可见铃舌承担识别，不依赖任何技能徽记。
        arc(cx, cy - 59 * size, 10 * size, 10 * size, 0, 360, 9 * size, DARK)
        arc(cx, cy - 59 * size, 10 * size, 10 * size, 0, 360, 4 * size, GOLD)
        arc(cx, cy - 59 * size, 10 * size, 10 * size, 200, 306, 1.7 * size, BONE)
        edge({ { 0, -48 }, { 0, -31 } }, 10, DARK, false)
        edge({ { -1, -47 }, { -1, -32 } }, 5, GOLD, false)
        edge({ { -2, -45 }, { -2, -34 } }, 1.5, BONE, false)

        local body = { { -35, 27 } }
        curve(body, -26, 13, -29, -15, -17, -25)
        curve(body, -10, -33, 10, -33, 17, -25)
        curve(body, 29, -15, 26, 13, 35, 27)
        curve(body, 48, 31, 48, 38, 35, 41)
        curve(body, 15, 46, -15, 46, -35, 41)
        curve(body, -48, 38, -48, 31, -35, 27)
        edge(body, 8, DARK, true)
        polygon(project(body), BONE, SHADE)
        -- 一整片铜暗面和单侧宽高光：先建立体积，再留少量刻边。
        polygon(project({ { 4, -29 }, { 16, -24 }, { 24, -11 }, { 27, 13 },
            { 38, 30 }, { 23, 37 }, { 14, 18 }, { 10, -9 } }), GOLD, SHADE)
        edge(body, 1.6, GOLD, true)
        local highlight = { { -12, -23 } }
        curve(highlight, -23, -13, -17, 6, -29, 24)
        edge(highlight, 3.8, BONE, false)
        ellipse(cx, cy + 35 * size, 43 * size, 7 * size, GOLD, BONE)
        ellipse(cx, cy + 37 * size, 33 * size, 4.6 * size, DARK, SHADE)
        edge({ { 0, 37 }, { 0, 53 } }, 5.5, DARK, false)
        edge({ { -1, 38 }, { -1, 53 } }, 3, GOLD, false)
        ellipse(cx, cy + 56 * size, 7 * size, 5.5 * size, BONE, SHADE)

        if refined then
            -- 实体颈箍与椭圆嵌件，不画十字星/加号；小图仍靠钟口和提环识别。
            polygon(project({ { -19, -19 }, { 19, -19 }, { 22, -10 }, { -22, -10 } }), GOLD, SHADE)
            edge({ { -18, -17 }, { 18, -17 } }, 2.3, BONE, false)
            ellipse(cx, cy + 8 * size, 8 * size, 11 * size, DARK)
            ellipse(cx - size, cy + 7 * size, 5.3 * size, 8 * size, GOLD, SHADE)
            edge({ { -2, 2 }, { -3, 10 } }, 1.6, BONE, false)
        else
            -- 基础司仪只留一条制造接缝，细节明显少于已审核的一转和本批二转。
            edge({ { 9, -7 }, { 11, 14 } }, 1.8, SHADE, false)
        end
    end

    if id == 6 then
        -- 司仪：一枚大手铃。职业来自圣铃的实体器形，不将“致命抵挡/反噬”画成流程。
        -- 简单骨白罩壳、铜口、完整提环；无护盾、灯火、祷书或附加底板抢主体。
        bell(139.5, 144, 1.25, false)
        return
    end

    if id == 221 then
        -- 战祷，父111：保护队友后下一击增伤。选择“执铃战地仪式护腕”，不是加剑箭。
        -- 单只手甲不是巨大全身角色；宽袖口/骨白束带/持铃拇指将它区别于普通骑士拳套。
        -- 右上圣铃先画，提环被手指握住；斜向腕甲和下垂布带形成独有不对称轮廓。
        bell(184, 132, 0.66, true)
        emblem({ { 99, 167 }, { 151, 164 }, { 166, 207 }, { 154, 226 },
            { 111, 222 }, { 89, 208 } }, GOLD, SHADE)
        polygon({ { 106, 174 }, { 145, 171 }, { 156, 207 }, { 147, 217 },
            { 116, 213 }, { 99, 202 } }, BONE, GOLD)
        polygon({ { 138, 174 }, { 148, 174 }, { 157, 205 }, { 147, 216 },
            { 138, 211 } }, GOLD, SHADE)
        stroke({ { 101, 185 }, { 148, 181 } }, 10, DARK, false)
        stroke({ { 102, 183 }, { 147, 179 } }, 5.5, BONE, false)
        stroke({ { 103, 203 }, { 152, 207 } }, 8, DARK, false)
        stroke({ { 104, 201 }, { 151, 205 } }, 4, GOLD, false)
        -- 袖口束带是软质护具边缘，不是飘在后方的装饰旗帜或箭头。
        emblem({ { 92, 171 }, { 106, 174 }, { 99, 193 }, { 98, 211 },
            { 87, 215 }, { 84, 200 } }, BONE, GOLD)
        line(93, 181, 90, 201, 3, SHADE)

        local glove = { { 105, 171 }, { 97, 152 }, { 108, 122 }, { 110, 103 },
            { 121, 87 }, { 153, 85 }, { 166, 99 }, { 165, 122 },
            { 152, 151 }, { 151, 168 } }
        emblem(glove, BONE, GOLD)
        polygon({ { 143, 96 }, { 158, 101 }, { 159, 121 }, { 146, 149 },
            { 144, 165 }, { 131, 167 }, { 137, 134 } }, GOLD, SHADE)
        stroke({ { 109, 155 }, { 119, 130 }, { 120, 111 } }, 4, BONE, false)
        -- 大片掌甲只留一条斜脊；三个粗指节是护具结构，而非技能层数示意。
        emblem({ { 117, 106 }, { 128, 93 }, { 154, 93 }, { 160, 108 },
            { 152, 118 }, { 123, 119 } }, GOLD, SHADE)
        for _, x in ipairs({ 126, 139, 152 }) do
            line(x, 97, x + 1, 110, 3.7, DARK)
            line(x - 2, 97, x - 1, 107, 1.8, BONE)
        end
        -- 右侧弯曲拇指包住铃环，不能读成第二把武器。
        local thumb = { { 146, 127 } }
        curve(thumb, 152, 109, 164, 92, 180, 91)
        curve(thumb, 190, 91, 194, 98, 189, 105)
        curve(thumb, 181, 112, 172, 111, 165, 125)
        curve(thumb, 161, 134, 151, 136, 146, 127)
        emblem(thumb, BONE, GOLD)
        stroke({ { 159, 116 }, { 169, 103 }, { 181, 99 } }, 3, BONE, false)
        ellipse(125, 193, 7, 10, DARK)
        ellipse(124, 192, 4.5, 7, GOLD, SHADE)
        line(123, 189, 122, 194, 1.8, BONE)
        return
    end

    if id == 222 then
        -- 血祷，父111：40%触发并按原本伤害回复。用“续命祷灯”而非血滴/回复加号。
        -- 狭长提灯、骨白护柱、宽暗窗和一整块灯芯；承接圣铃工艺，但不是再画一枚铃。
        -- 光来自实体骨白灯芯，没有发光晕、霓虹、声波或伤害返还箭。
        arc(140, 64, 13, 12, 0, 360, 9, DARK)
        arc(140, 64, 13, 12, 0, 360, 4.4, GOLD)
        arc(140, 64, 13, 12, 200, 310, 1.8, BONE)
        line(140, 76, 140, 87, 10, DARK)
        line(138, 76, 138, 86, 4.5, GOLD)
        emblem({ { 102, 103 }, { 114, 89 }, { 130, 83 }, { 150, 83 },
            { 166, 89 }, { 178, 103 }, { 178, 111 }, { 102, 111 } }, BONE, GOLD)
        polygon({ { 147, 87 }, { 163, 93 }, { 174, 105 }, { 150, 105 } }, GOLD, SHADE)
        line(110, 104, 168, 104, 4, BONE)
        emblem({ { 105, 112 }, { 175, 112 }, { 180, 184 }, { 164, 203 },
            { 116, 203 }, { 100, 184 } }, GOLD, SHADE)
        polygon({ { 117, 117 }, { 163, 117 }, { 166, 177 }, { 156, 191 },
            { 124, 191 }, { 113, 177 } }, DARK)
        -- 两根实体护柱围住灯室；不是另加盾牌/徽章底盘。
        emblem({ { 102, 110 }, { 113, 111 }, { 115, 177 }, { 123, 195 },
            { 113, 198 }, { 102, 181 } }, BONE, GOLD)
        emblem({ { 167, 111 }, { 178, 110 }, { 178, 181 }, { 167, 198 },
            { 157, 195 }, { 165, 177 } }, GOLD, SHADE)
        line(107, 117, 108, 174, 3.3, BONE)
        line(171, 116, 171, 176, 2.4, GOLD)
        -- 厚蜡芯和单片骨白火舌构成中心亮块，不以密纹/粒子制造“精细”。
        emblem({ { 131, 151 }, { 149, 151 }, { 151, 184 }, { 128, 184 } }, BONE, GOLD)
        polygon({ { 143, 154 }, { 148, 154 }, { 150, 179 }, { 143, 180 } }, GOLD, SHADE)
        local flame = { { 140, 115 } }
        curve(flame, 140, 128, 128, 130, 129, 141)
        curve(flame, 130, 155, 151, 157, 154, 143)
        curve(flame, 156, 133, 146, 123, 140, 115)
        emblem(flame, BONE, GOLD)
        polygon({ { 142, 130 }, { 149, 142 }, { 142, 149 }, { 139, 141 } }, GOLD, SHADE)
        emblem({ { 111, 196 }, { 169, 196 }, { 178, 205 }, { 169, 216 },
            { 111, 216 }, { 102, 205 } }, GOLD, SHADE)
        line(112, 201, 168, 201, 3.4, BONE)
        line(117, 212, 163, 212, 2.8, SHADE)
        -- 只一条礼仪绑带沿灯脚外侧垂下，平切布端避免箭头化。
        emblem({ { 103, 176 }, { 115, 181 }, { 106, 193 }, { 102, 209 },
            { 91, 220 }, { 83, 211 }, { 91, 196 } }, BONE, GOLD)
        stroke({ { 105, 183 }, { 98, 197 }, { 96, 209 } }, 3.2, SHADE, false)
        return
    end

    if id == 223 then
        -- 大赦，父112：延缓治疗三倍，低生命队友必定治疗暴击。选择主持大赦的展开祷书。
        -- 开阔书页/厚书脊/礼仪书签体现高阶救护身份；不把倍率画成三枚铃或治疗星芒。
        -- 铜质书壳在页块下面，只属于书的厚度，绝非第二层背景底盘。
        local cover = { { 60, 99 }, { 101, 103 }, { 139, 119 }, { 177, 103 },
            { 219, 99 }, { 219, 180 }, { 204, 195 }, { 171, 190 },
            { 139, 206 }, { 107, 190 }, { 75, 195 }, { 60, 180 } }
        emblem(cover, GOLD, SHADE)
        polygon({ { 66, 172 }, { 104, 177 }, { 137, 195 }, { 137, 202 },
            { 104, 185 }, { 74, 190 }, { 65, 179 } }, GOLD, SHADE)
        polygon({ { 143, 195 }, { 177, 177 }, { 213, 172 }, { 213, 180 },
            { 204, 189 }, { 174, 185 }, { 143, 202 } }, SHADE, DARK)
        local leftPage = { { 61, 91 } }
        curve(leftPage, 83, 86, 115, 92, 138, 109)
        curve(leftPage, 135, 132, 134, 168, 138, 193)
        curve(leftPage, 112, 177, 86, 171, 64, 177)
        curve(leftPage, 59, 154, 58, 113, 61, 91)
        local rightPage = { { 142, 109 } }
        curve(rightPage, 165, 92, 196, 86, 217, 91)
        curve(rightPage, 221, 113, 221, 154, 215, 177)
        curve(rightPage, 195, 171, 168, 177, 142, 193)
        curve(rightPage, 146, 168, 146, 132, 142, 109)
        emblem(leftPage, BONE, GOLD)
        emblem(rightPage, BONE, GOLD)
        -- 每页一个宽明面、一条厚页沿，不写伪文字，也不铺满神秘符号。
        polygon({ { 125, 108 }, { 133, 112 }, { 130, 176 }, { 123, 177 },
            { 111, 170 }, { 118, 144 } }, GOLD, SHADE)
        polygon({ { 198, 96 }, { 211, 96 }, { 215, 157 }, { 208, 169 },
            { 195, 167 }, { 202, 137 } }, GOLD, SHADE)
        local leftEdge = { { 68, 99 } }
        curve(leftEdge, 88, 96, 114, 103, 126, 111)
        stroke(leftEdge, 3.5, BONE, false)
        local rightEdge = { { 153, 111 } }
        curve(rightEdge, 173, 98, 195, 97, 209, 100)
        stroke(rightEdge, 3.5, BONE, false)
        local pageFoot = { { 69, 166 } }
        curve(pageFoot, 90, 162, 112, 168, 127, 180)
        stroke(pageFoot, 2.7, SHADE, false)
        local otherFoot = { { 152, 180 } }
        curve(otherFoot, 173, 168, 196, 162, 211, 166)
        stroke(otherFoot, 2.7, SHADE, false)
        stroke({ { 139.5, 113 }, { 139.5, 185 } }, 8, DARK, false)
        line(137, 116, 137, 178, 2.6, GOLD)
        -- 两枚上角厚包是书壳工艺；没有皇冠形页顶或另附护盾。
        for _, x in ipairs({ 68, 211 }) do
            emblem({ { x - 6, 100 }, { x + 5, 99 }, { x + 5, 119 },
                { x + 1, 124 }, { x - 6, 118 } }, GOLD, SHADE)
            line(x - 3, 104, x - 3, 114, 2.1, BONE)
        end
        -- 无字礼仪书签和小圣铃连接两大页块；铃纹比基础精细但不争主体。
        emblem({ { 132, 173 }, { 148, 173 }, { 149, 203 }, { 140, 213 },
            { 131, 203 } }, GOLD, SHADE)
        bell(139.5, 201, 0.44, true)
        return
    end

    -- 罚忏，父112：治疗时40%概率造成三倍暗影伤害，不是主动全屏雷击。
    -- “罩铃执仪权杖”以暗色钟室、长柄和礼仪束带表达审罚职责，不画伤害投射/十字。
    -- 与大赦横向书翼形成明显对照；封闭拱罩没有冠齿、宝石列或皇冠尖。
    emblem({ { 104, 218 }, { 117, 225 }, { 172, 128 }, { 155, 121 } }, GOLD, SHADE)
    polygon({ { 106, 216 }, { 111, 219 }, { 161, 128 }, { 157, 126 } }, BONE, GOLD)
    line(115, 216, 165, 131, 2.7, SHADE)
    ellipse(109, 224, 8, 6.5, DARK)
    ellipse(108, 222.5, 5.5, 4.3, GOLD, SHADE)
    line(105, 220, 110, 220, 2, BONE)

    local hood = { { 177, 53 } }
    curve(hood, 157, 54, 146, 68, 147, 86)
    curve(hood, 147, 111, 161, 130, 177, 140)
    curve(hood, 195, 129, 208, 108, 208, 86)
    curve(hood, 208, 68, 196, 54, 177, 53)
    emblem(hood, BONE, GOLD)
    local chamber = { { 177, 64 } }
    curve(chamber, 162, 64, 157, 75, 158, 88)
    curve(chamber, 159, 106, 166, 121, 177, 130)
    curve(chamber, 189, 120, 198, 104, 198, 88)
    curve(chamber, 198, 74, 191, 64, 177, 64)
    polygon(chamber, SHADE, DARK)
    stroke(chamber, 2.5, GOLD, true)
    stroke({ { 155, 82 }, { 158, 104 }, { 169, 122 } }, 3.5, BONE, false)
    stroke({ { 203, 89 }, { 199, 110 }, { 185, 132 } }, 3, SHADE, false)
    bell(177, 101, 0.48, true)
    -- 粗铜下箍接住罩铃与杖柄，没有第二杖头/魔法符阵。
    emblem({ { 163, 126 }, { 181, 135 }, { 174, 147 }, { 155, 138 } }, GOLD, SHADE)
    line(163, 131, 177, 138, 2.6, BONE)
    -- 骨白礼仪布带横卷于握柄，宽面与自然折角；末端平切，不读成指向箭。
    local sash = { { 136, 160 } }
    curve(sash, 147, 165, 164, 166, 180, 157)
    curve(sash, 182, 165, 176, 176, 164, 180)
    curve(sash, 154, 183, 140, 178, 128, 174)
    curve(sash, 128, 168, 131, 163, 136, 160)
    emblem(sash, BONE, GOLD)
    polygon({ { 155, 170 }, { 170, 168 }, { 177, 164 }, { 172, 174 },
        { 161, 179 }, { 153, 176 } }, GOLD, SHADE)
    emblem({ { 137, 175 }, { 148, 179 }, { 141, 198 }, { 135, 211 },
        { 122, 208 }, { 129, 194 } }, BONE, GOLD)
    stroke({ { 138, 184 }, { 134, 197 }, { 129, 205 } }, 2.8, SHADE, false)
    -- 两道粗握柄缠带与杖身斜轴一致，末端留完整圆钝铜头。
    line(116, 197, 127, 203, 8, DARK)
    line(117, 195, 128, 201, 4.4, GOLD)
    line(110, 208, 121, 214, 7, DARK)
    line(111, 206, 122, 212, 3.8, BONE)
end

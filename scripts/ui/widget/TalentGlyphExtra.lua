local M = {}

local function path(vg, points)
    nvgBeginPath(vg)
    for i, p in ipairs(points) do
        if i == 1 then nvgMoveTo(vg, p[1], p[2]) else nvgLineTo(vg, p[1], p[2]) end
    end
    nvgClosePath(vg)
    nvgFill(vg)
    nvgStroke(vg)
end

local function line(vg, x1, y1, x2, y2, width)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeWidth(vg, width)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function circle(vg, x, y, r)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFill(vg)
    nvgStroke(vg)
end

local function ring(vg, x, y, r, width)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function shield(vg)
    path(vg, { { 25, 23 }, { 50, 17 }, { 75, 23 }, { 71, 56 }, { 64, 70 }, { 50, 82 }, { 36, 70 }, { 29, 56 } })
end

local function blade(vg)
    path(vg, { { 50, 15 }, { 58, 27 }, { 55, 65 }, { 45, 65 }, { 42, 27 } })
    line(vg, 35, 66, 65, 66, 6)
    line(vg, 50, 69, 50, 81, 7)
    circle(vg, 50, 83, 4)
end

local function heart(vg, cx, cy, size)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, size, size)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 18)
    nvgBezierTo(vg, -42, -5, -15, -31, 0, -14)
    nvgBezierTo(vg, 15, -31, 42, -5, 0, 18)
    nvgClosePath(vg)
    nvgFill(vg)
    nvgStroke(vg)
    nvgRestore(vg)
end

local function bow(vg)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 43, 18)
    nvgBezierTo(vg, 81, 27, 81, 73, 43, 82)
    nvgStrokeWidth(vg, 6)
    nvgStroke(vg)
    nvgRestore(vg)
    line(vg, 43, 18, 43, 82, 2.4)
    line(vg, 20, 50, 77, 50, 3)
    path(vg, { { 70, 42 }, { 84, 50 }, { 70, 58 } })
end

local function arrow(vg)
    line(vg, 27, 75, 69, 33, 5)
    path(vg, { { 63, 26 }, { 81, 20 }, { 75, 38 } })
    path(vg, { { 20, 70 }, { 28, 62 }, { 39, 62 }, { 28, 73 } })
    path(vg, { { 30, 80 }, { 38, 72 }, { 38, 61 }, { 27, 72 } })
end

M[30] = function(vg)
    line(vg, 31, 79, 61, 24, 8)
    path(vg, { { 22, 34 }, { 39, 22 }, { 57, 20 }, { 73, 23 }, { 85, 35 }, { 72, 32 }, { 59, 29 }, { 46, 29 }, { 32, 34 } })
end

M[37] = bow

M[38] = function(vg)
    line(vg, 33, 81, 59, 24, 7)
    path(vg, { { 36, 20 }, { 60, 30 }, { 71, 18 }, { 84, 30 }, { 80, 48 }, { 68, 59 }, { 51, 58 }, { 53, 42 }, { 36, 35 } })
end

M[40] = function(vg)
    heart(vg, 50, 43, 1.2)
    line(vg, 32, 73, 68, 73, 4)
    line(vg, 40, 80, 60, 80, 4)
end

M[49] = function(vg)
    ring(vg, 59, 41, 19, 4)
    arrow(vg)
end

M[53] = function(vg)
    line(vg, 31, 79, 62, 31, 7)
    circle(vg, 65, 27, 10)
    path(vg, { { 53, 22 }, { 48, 15 }, { 45, 26 }, { 49, 35 }, { 61, 40 }, { 73, 32 }, { 79, 21 }, { 75, 12 }, { 68, 17 }, { 70, 27 }, { 61, 31 } })
end

M[59] = function(vg)
    line(vg, 25, 68, 74, 32, 7)
    for _, p in ipairs({ { 23, 58 }, { 32, 71 }, { 64, 28 }, { 73, 41 } }) do
        path(vg, { { p[1]-5, p[2]-8 }, { p[1]+2, p[2]-12 }, { p[1]+9, p[2] }, { p[1]+2, p[2]+4 } })
    end
end

M[60] = function(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, 50, 50, 25, 28)
    nvgFill(vg)
    nvgStroke(vg)
    circle(vg, 50, 17, 5)
    for _, p in ipairs({ { 27, 31 }, { 73, 31 }, { 27, 70 }, { 73, 70 } }) do
        circle(vg, p[1], p[2], 4)
    end
end

M[113] = function(vg)
    ring(vg, 50, 50, 29, 3.4)
    ring(vg, 50, 50, 21, 2.4)
    path(vg, { { 50, 28 }, { 63, 50 }, { 50, 72 }, { 37, 50 } })
    for _, p in ipairs({ { 50, 17 }, { 83, 50 }, { 50, 83 }, { 17, 50 } }) do circle(vg,p[1],p[2],3) end
end

M[115] = function(vg)
    nvgSave(vg)
    nvgTranslate(vg, 50, 50)
    nvgRotate(vg, -0.58)
    nvgTranslate(vg, -50, -50)
    blade(vg)
    nvgRestore(vg)
    nvgSave(vg)
    nvgTranslate(vg, 50, 50)
    nvgRotate(vg, 0.58)
    nvgTranslate(vg, -50, -50)
    blade(vg)
    nvgRestore(vg)
end

M[116] = function(vg)
    shield(vg)
    nvgSave(vg)
    nvgTranslate(vg, 50, 50)
    nvgScale(vg, 0.67, 0.67)
    nvgTranslate(vg, -50, -50)
    ring(vg,50,47,20,2.8)
    nvgRestore(vg)
end

M[117] = function(vg)
    ring(vg,50,50,30,4)
    shield(vg)
end

M[124] = function(vg)
    heart(vg,41,62,1.04)
    path(vg, { { 69.5, 16 }, { 74.5, 16 }, { 74.5, 22.5 }, { 81, 22.5 }, { 81, 27.5 }, { 74.5, 27.5 }, { 74.5, 34 }, { 69.5, 34 }, { 69.5, 27.5 }, { 63, 27.5 }, { 63, 22.5 }, { 69.5, 22.5 } })
end

M[125] = function(vg)
    path(vg, { { 49, 22 }, { 58, 20 }, { 57, 28 }, { 51, 37 }, { 57, 48 }, { 66, 39 }, { 86, 24 }, { 78, 44 }, { 64, 59 }, { 56, 60 }, { 63, 79 }, { 51, 70 }, { 43, 83 }, { 43, 64 }, { 35, 58 }, { 19, 46 }, { 12, 27 }, { 34, 41 }, { 43, 49 }, { 43, 37 } })
end

M[127] = function(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg,26,26,48,48,7)
    nvgFill(vg)
    nvgStroke(vg)
end

M[128] = function(vg)
    ring(vg,50,39,17,4)
    line(vg,39,26,42,67,4)
    line(vg,50,23,50,73,4)
    line(vg,61,26,58,67,4)
    path(vg, { { 31, 26 }, { 37, 32 }, { 39, 66 }, { 47, 77 }, { 58, 70 }, { 63, 32 }, { 69, 26 }, { 67, 66 }, { 56, 82 }, { 45, 84 }, { 33, 70 } })
end

M[129] = function(vg)
    path(vg, { { 18, 58 }, { 21, 42 }, { 34, 31 }, { 61, 29 }, { 76, 37 }, { 81, 57 }, { 71, 69 }, { 47, 68 }, { 30, 75 }, { 21, 69 } })
    path(vg, { { 22, 44 }, { 11, 24 }, { 36, 34 } })
    path(vg, { { 39, 32 }, { 47, 13 }, { 52, 32 } })
    path(vg, { { 64, 32 }, { 83, 17 }, { 76, 44 } })
end

M[133] = function(vg)
    path(vg, { { 38, 73 }, { 38, 40 }, { 42, 27 }, { 50, 16 }, { 58, 27 }, { 62, 40 }, { 62, 73 } })
    path(vg, { { 36, 77 }, { 64, 77 }, { 64, 83 }, { 36, 83 } })
end

M[134] = function(vg)
    blade(vg)
    path(vg, { { 42, 40 }, { 30, 31 }, { 22, 32 }, { 30, 46 }, { 40, 51 } })
    path(vg, { { 58, 40 }, { 70, 31 }, { 78, 32 }, { 70, 46 }, { 60, 51 } })
end

M[135] = function(vg)
    blade(vg)
    path(vg, { { 22, 84 }, { 27, 67 }, { 38, 60 }, { 45, 69 }, { 53, 64 }, { 64, 63 }, { 75, 76 }, { 78, 86 } })
end

M[136] = function(vg)
    path(vg, { { 19, 61 }, { 25, 54 }, { 40, 61 }, { 57, 62 }, { 60, 67 }, { 43, 69 }, { 62, 73 }, { 76, 58 }, { 82, 60 }, { 70, 79 }, { 50, 85 }, { 30, 73 }, { 19, 71 } })
    heart(vg,52,41,0.82)
end

return M

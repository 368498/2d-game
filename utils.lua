local utils = {}

function utils.sign(x)
    return (x > 0 and 1) or (x < 0 and -1) or 0
end

function utils.rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

function utils.circleRectOverlap(cx, cy, cr, rx, ry, rw, rh)
    local closestX = math.max(rx, math.min(cx, rx + rw))
    local closestY = math.max(ry, math.min(cy, ry + rh))
    local dx = cx - closestX
    local dy = cy - closestY
    return (dx * dx + dy * dy) < (cr * cr)
end

return utils 
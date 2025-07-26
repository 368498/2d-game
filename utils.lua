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

-- Speed utility functions
function utils.getNearestSpeedTier(val, tiers)
    local best, bestDist = tiers[1], math.abs(val - tiers[1].value)
    for _, tier in ipairs(tiers) do
        local dist = math.abs(val - tier.value)
        if dist < bestDist then
            best, bestDist = tier, dist
        end
    end
    return best
end

function utils.getTierIndex(tierName, tiers)
    for i, tier in ipairs(tiers) do
        if tier.name == tierName then
            return i
        end
    end
    return 1
end

return utils 
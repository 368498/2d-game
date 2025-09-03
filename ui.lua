local config = require 'config'
local ui = {}

function ui.draw(player, enemy)
    -- UI: Draw speed tier meter (UI), charge bar, cooldowns, debug info LAST
    local SPEED_TIERS = player.SPEED_TIERS or {
        {name = 'slowed', value = 130, color = {0.5, 0.5, 1}},
        {name = 'normal', value = 240, color = {1, 1, 1}},
        {name = 'fast', value = 360, color = {1, 0.8, 0.2}},
        {name = 'superfast', value = 600, color = {1, 0.2, 0.2}}
    }
    local meterX, meterY = config.UI_METER_X, config.UI_METER_Y
    local pipSize = config.UI_PIP_SIZE
    local pipSpacing = config.UI_PIP_SPACING
    love.graphics.setFont(love.graphics.newFont(config.UI_FONT_SIZE))
    love.graphics.setColor(1, 1, 1, 0.8)
    for i, tier in ipairs(SPEED_TIERS) do
        local x = meterX + (i-1) * pipSpacing
        local y = meterY
        -- Draw pip background
        love.graphics.setColor(0.18, 0.18, 0.22, 0.5)
        love.graphics.circle('fill', x, y, pipSize/2)
        -- Highlight if current tier
        if player.speedTier and player.speedTier.value == tier.value then
            love.graphics.setColor(tier.color[1], tier.color[2], tier.color[3], 1)
            love.graphics.setLineWidth(4)
            love.graphics.circle('line', x, y, pipSize/2 + 2)
            love.graphics.setLineWidth(1)
        end
        -- Draw pip fill
        love.graphics.setColor(tier.color[1], tier.color[2], tier.color[3], 0.85)
        love.graphics.circle('fill', x, y, pipSize/2 - 3)
    end
    love.graphics.setColor(1, 1, 1, 1)
    
    -- #TODO HP hearts
    local heartsX, heartsY = meterX, meterY + 28
    local hp = player.health or 0
    local maxHp = player.maxHealth or hp
    for i = 1, maxHp do
        local x = heartsX + (i-1) * (pipSpacing * 0.65)
        local y = heartsY
        if i <= hp then
            love.graphics.setColor(1, 0.3, 0.3, 1)
        else
            love.graphics.setColor(0.3, 0.15, 0.15, 0.6)
        end
        love.graphics.circle('fill', x, y, 7)
    end
    love.graphics.setColor(1, 1, 1, 1)
    -- Draw cooldown indicators for both attacks
    local px, py, ps = player.x, player.y, player.size
    local cx, cy = px + ps / 2, py + ps + 6
    local w = ps
    if player.attack.cooldownTimer > 0 then
        local pct = player.attack.cooldownTimer / player.attack.cooldown
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.rectangle('fill', cx - w/2, cy, w * (1 - pct), 6)
        love.graphics.setColor(1, 1, 1, 1)
    end
    if player.altAttack.cooldownTimer > 0 then
        local pct = player.altAttack.cooldownTimer / player.altAttack.cooldown
        love.graphics.setColor(1, 0.5, 0, 0.7)
        love.graphics.rectangle('fill', cx - w/2, cy + 10, w * (1 - pct), 6)
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- Draw altAttack charge bar if charging
    local tierName = player.speedTier and player.speedTier.name or 'normal'
    if player.altAttack.charging and (tierName == 'fast' or tierName == 'superfast') then
        local px, py, ps = player.x, player.y, player.size
        local cx, cy = px + ps / 2, py + ps + 24
        local w = ps
        local pct = player.altAttack.charge / player.altAttack.maxCharge
        local allowedPct = (player.altAttack.maxAllowedCharge or 1) / 3
        -- Draw background bar (full length, dimmed)
        love.graphics.setColor(0.3, 0.3, 0.3, 0.4)
        love.graphics.rectangle('fill', cx - w/2, cy, w, 8)
        -- Draw allowed region (bright)
        love.graphics.setColor(1, 0.5, 0, 0.7)
        love.graphics.rectangle('fill', cx - w/2, cy, w * allowedPct, 8)
        -- Draw current charge (overlay)
        love.graphics.setColor(1, 0.8, 0.2, 0.9)
        love.graphics.rectangle('fill', cx - w/2, cy, math.min(w * pct, w * allowedPct), 8)
        -- Draw a cap line at the allowed limit (if not superfast)
        if allowedPct < 1 then
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(cx - w/2 + w * allowedPct, cy, cx - w/2 + w * allowedPct, cy + 8)
            love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- Debug render removed
end

return ui 
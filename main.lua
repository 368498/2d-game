-- main.lua
local player = require 'player'
local enemy = require 'enemy'
local ui = require 'ui'
local config = require 'config'
local map = require 'map'
local utils = require 'utils'

local SPEED_TIERS = {
    {name = 'slowed', value = 130, color = {0.5, 0.5, 1}, accel = 1200, friction = 1100, punch = 1},
    {name = 'normal', value = 240, color = {1, 1, 1}, accel = 1200, friction = 900, punch = 1.5},
    {name = 'fast', value = 360, color = {1, 0.8, 0.2}, accel = 900, friction = 600, punch = 2.2},
    {name = 'superfast', value = 600, color = {1, 0.2, 0.2}, accel = 800, friction = 400, punch = 3.2}
}

local ENEMY_SPEED_TIERS = {
    {name = 'slowed', value = 60, color = {0.5, 1, 0.5}},
    {name = 'normal', value = 120, color = {1, 1, 1}},
    {name = 'fast', value = 200, color = {0.2, 0.8, 1}},
    {name = 'superfast', value = 320, color = {1, 0.2, 1}}
}

function getNearestSpeedTier(val)
    local best, bestDist = SPEED_TIERS[1], math.abs(val - SPEED_TIERS[1].value)
    for _, tier in ipairs(SPEED_TIERS) do
        local dist = math.abs(val - tier.value)
        if dist < bestDist then
            best, bestDist = tier, dist
        end
    end
    return best
end

function getNearestEnemySpeedTier(val)
    local best, bestDist = ENEMY_SPEED_TIERS[1], math.abs(val - ENEMY_SPEED_TIERS[1].value)
    for _, tier in ipairs(ENEMY_SPEED_TIERS) do
        local dist = math.abs(val - tier.value)
        if dist < bestDist then
            best, bestDist = tier, dist
        end
    end
    return best
end

function love.load()
    player.load()
    map.init(30, 22, config.TILE_SIZE)
    enemy.initAll(map)
end

function love.update(dt)
    enemy.updateAll(dt, map, map.getTilemap())
    player.update(dt, map, map.getTilemap(), enemy.getAll())
    -- Enemy speed tier logic
    for i, e in ipairs(enemy.getAll()) do
        if e.defeated then goto continue_enemy end
        if e.knockbackTimer and e.knockbackTimer > 0 then
            local nextX = e.x + e.knockbackVx * dt
            local nextY = e.y + e.knockbackVy * dt
            -- Check if any corner hits a wall
            local es = e.size
            local hitWall = false
            for _, corner in ipairs({
                {nextX, nextY},
                {nextX + es - 1, nextY},
                {nextX, nextY + es - 1},
                {nextX + es - 1, nextY + es - 1}
            }) do
                if map.isWallAt(corner[1], corner[2]) then
                    hitWall = true
                    break
                end
            end
            if hitWall then
                e.defeated = true
                e.defeatEffectTimer = 0.28
                goto continue_enemy
            end
            -- Check for collision with other enemies
            for j, other in ipairs(enemy.getAll()) do
                if other ~= e and not other.defeated then
                    local overlap = not (nextX + es < other.x or nextX > other.x + other.size or nextY + es < other.y or nextY > other.y + other.size)
                    if overlap then
                        other.defeated = true
                        other.defeatEffectTimer = 0.28
                    end
                end
            end
            e.x = nextX
            e.y = nextY
            e.knockbackTimer = e.knockbackTimer - dt
            if e.knockbackTimer <= 0 then
                -- Enter recovery/transition state
                e.knockbackVx = 0
                e.knockbackVy = 0
                e.knockbackTimer = 0
                e.vx = 0
                e.vy = 0
                e.recoveryTimer = 0.15
                e._recoveryElapsed = 0
                -- Store target velocity for smooth blend
                local dir = (e.vx >= 0) and 1 or -1
                e._recoveryTargetVx = dir * (e.speedTier and e.speedTier.value or 120)
            end
        elseif e.recoveryTimer and e.recoveryTimer > 0 then
            local total = 0.15
            local elapsed = (e._recoveryElapsed or 0) + dt
            e._recoveryElapsed = elapsed
            local t = math.min(1, elapsed / total)
            -- Lerp vx from 0 to target
            e.vx = (e._recoveryTargetVx or 0) * t
            e.vy = 0
            e.recoveryTimer = e.recoveryTimer - dt
            if e.recoveryTimer <= 0 then
                -- Snap to target at end
                e.vx = e._recoveryTargetVx or 0
                e.vy = 0
                e._recoveryElapsed = nil
                e._recoveryTargetVx = nil
            end
        else
            -- Normal movement logic
            if e.targetVx then
                if math.abs(e.vx - e.targetVx) < 1 then
                    e.vx = e.targetVx
                    e.targetVx = nil
                else
                    e.vx = e.vx + utils.sign(e.targetVx - e.vx) * 200 * dt
                end
            end
            -- (No clamping of enemy.vx to tier speed)
            if e.targetVy then
                if math.abs(e.vy - e.targetVy) < 1 then
                    e.vy = e.targetVy
                    e.targetVy = nil
                else
                    e.vy = e.vy + utils.sign(e.targetVy - e.vy) * 200 * dt
                end
            end
            e.x = e.x + e.vx * dt
            e.y = e.y + (e.vy or 0) * dt
            if e.x < e.minX then
                e.x = e.minX
                e.vx = -e.vx
            elseif e.x > e.maxX then
                e.x = e.maxX
                e.vx = -e.vx
            end
            if e.y < 0 then e.y = 0; e.vy = -e.vy end
            if e.y > 720 - e.size then e.y = 720 - e.size; e.vy = -e.vy end
        end
        ::continue_enemy::
    end
    -- Update defeat effect timers
    for _, e in ipairs(enemy.getAll()) do
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            e.defeatEffectTimer = e.defeatEffectTimer - dt
        end
    end

    -- Player-enemy collision: enemy has priority, push player out
    local px, py, ps = player.x, player.y, player.size
    for i, e in ipairs(enemy.getAll()) do
        local ex, ey, es = e.x, e.y, e.size
        local playerRadius = ps * 0.45
        local playerCenterX = px + ps/2
        local playerCenterY = py + ps/2
        if utils.circleRectOverlap(playerCenterX, playerCenterY, playerRadius, ex, ey, es, es) then
            -- Find the minimal push direction
            local overlapLeft = (playerCenterX + playerRadius) - ex
            local overlapRight = (ex + es) - (playerCenterX - playerRadius)
            local overlapTop = (playerCenterY + playerRadius) - ey
            local overlapBottom = (ey + es) - (playerCenterY - playerRadius)
            local minOverlap = math.min(overlapLeft, overlapRight, overlapTop, overlapBottom)
            if minOverlap == overlapLeft then
                player.x = ex - ps
            elseif minOverlap == overlapRight then
                player.x = ex + es
            elseif minOverlap == overlapTop then
                player.y = ey - ps
            else
                player.y = ey + es
            end
            -- Optionally, zero out velocity in the direction of the push
            if minOverlap == overlapLeft or minOverlap == overlapRight then
                player.vx = 0
            else
                player.vy = 0
            end
        end
    end
    -- Charge the altAttack if charging
    if player.altAttack.charging then
        player.altAttack.charge = math.min(player.altAttack.charge + dt, player.altAttack.maxCharge)
    end

    -- Self-charge: Hold 'take' (space) while standing still to gain a tier
    local isTakeHeld = love.keyboard.isDown('space')
    local isMoving = math.abs(player.vx) > 0.1 or math.abs(player.vy) > 0.1
    local maxTier = #SPEED_TIERS
    local currentTierIdx = 1
    for i, tier in ipairs(SPEED_TIERS) do
        if player.speedTier and player.speedTier.name == tier.name then
            currentTierIdx = i
            break
        end
    end
    -- Charge durations by tier (slower at higher tiers)
    local chargeDurations = {1.2, 2.0, 3.0, 4.0} -- slowed, normal, fast, superfast (slower charge)
    local chargeDuration = chargeDurations[currentTierIdx] or 1.0
    if isTakeHeld and not isMoving and player.selfChargeCooldown <= 0 and player.selfChargeReady and currentTierIdx < maxTier and not player.attack.active and player.attack.cooldownTimer == 0 then
        if not player.selfChargeActive then
            player.selfChargeActive = true
            player.selfChargeTimer = 0
        end
        player.selfChargeTimer = player.selfChargeTimer + dt
        if player.selfChargeTimer >= chargeDuration then
            -- Gain one tier
            local nextTier = SPEED_TIERS[currentTierIdx + 1]
            player.targetSpeed = nextTier.value
            player.selfChargeActive = false
            player.selfChargeTimer = 0
            player.selfChargeCooldown = 0.2 -- short cooldown to prevent double-trigger
            player.selfChargeReady = false -- require button release
        end
    else
        player.selfChargeActive = false
        player.selfChargeTimer = 0
        if not isTakeHeld then
            player.selfChargeReady = true
        end
    end
    if player.selfChargeCooldown > 0 then
        player.selfChargeCooldown = player.selfChargeCooldown - dt
        if player.selfChargeCooldown < 0 then player.selfChargeCooldown = 0 end
    end
end

function love.keypressed(key)
    player.keypressed(key)
end

function love.keyreleased(key)
    player.keyreleased(key)
end

function love.draw()
    -- Set solid background color
    love.graphics.clear(0.09, 0.09, 0.13, 1) -- deep blue-grey
    -- Draw tilemap walls
    for y = 1, map.height do
        for x = 1, map.width do
            if map.getTilemap()[y][x] == 1 then
                love.graphics.setColor(0.12, 0.12, 0.14, 1)
                love.graphics.rectangle('fill', (x-1)*map.tileSize, (y-1)*map.tileSize, map.tileSize, map.tileSize)
                love.graphics.setColor(0.3, 0.3, 0.35, 1)
                love.graphics.rectangle('line', (x-1)*map.tileSize, (y-1)*map.tileSize, map.tileSize, map.tileSize)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    player.draw()
    enemy.drawAll()
    -- Draw defeat visual effects for defeated enemies
    for _, e in ipairs(enemy.getAll()) do
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            local half = e.size / 2
            local cx = e.x + half
            local cy = e.y + half
            local duration = 0.28
            local t = 1 - (e.defeatEffectTimer / duration)
            -- Kinetic: expand faster, more overshoot, quick white flash at start
            local radius = half + t * 64 + 16 * math.sin(t * math.pi)
            if t < 0.12 then
                love.graphics.setColor(1, 1, 1, 0.85 * (1-t/0.12))
                love.graphics.circle('fill', cx, cy, radius * 0.7)
            end
            love.graphics.setColor(1, 0.2, 0.2, 0.8 * (1-t))
            love.graphics.circle('fill', cx, cy, radius)
            love.graphics.setColor(1, 1, 1, 0.7 * (1-t))
            love.graphics.circle('line', cx, cy, radius + 4)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
    -- Draw hit flash if active
    if player.hitFlash.active then
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.circle('fill', player.hitFlash.x, player.hitFlash.y, 24 * player.hitFlash.timer / 0.15)
        love.graphics.setColor(1, 1, 1)
    end
    -- Self-charge VFX: shrinking circle at player if charging
    local maxTier = #SPEED_TIERS
    local currentTierIdx = 1
    for i, tier in ipairs(SPEED_TIERS) do
        if player.speedTier and player.speedTier.name == tier.name then
            currentTierIdx = i
            break
        end
    end
    -- Charge durations by tier (slower at higher tiers)
    local chargeDurations = {1.2, 2.0, 3.0, 4.0} -- slowed, normal, fast, superfast (slower charge)
    local chargeDuration = chargeDurations[currentTierIdx] or 1.0
    if player.selfChargeActive and currentTierIdx < maxTier then
        local px, py, ps = player.x, player.y, player.size
        local cx, cy = px + ps / 2, py + ps / 2
        local pct = player.selfChargeTimer / (chargeDuration or 1.0)
        if pct > 1 then pct = 1 end
        local startRadius = ps * 13.2 -- much bigger
        local endRadius = ps * 0.2
        local startOpacity = 0
        local endOpacity = 0.001
        local radius = startRadius - (startRadius - endRadius) * pct
        local opacity 
        if radius < endRadius then radius = endRadius end
        love.graphics.setColor(1, 1, 1, opacity)
        love.graphics.setLineWidth(3)
        love.graphics.circle('line', cx, cy, radius)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
    ui.draw(player, enemy)
end
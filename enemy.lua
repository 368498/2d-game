local config = require 'config'
local utils = require 'utils'

local enemy = {}

enemy.enemies = {}

function enemy.initAll(map)
    local enemyStartTier = config.ENEMY_SPEED_TIERS[2] 
    enemy.enemies = {
        {
            x = 2 * config.TILE_SIZE, y = 2 * config.TILE_SIZE,
            size = config.PLAYER_SIZE,
            vx = enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        },
        {
            x = 25 * config.TILE_SIZE, y = 15 * config.TILE_SIZE,
            size = config.PLAYER_SIZE,
            vx = -enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        },
        {
            x = 15 * config.TILE_SIZE, y = 10 * config.TILE_SIZE,
            size = config.PLAYER_SIZE,
            vx = enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        }
    }
end

function enemy.updateAll(dt, map, tilemap)
    for i, e in ipairs(enemy.enemies) do

        if e.defeated then goto continue_enemy end
        
        if e.knockbackTimer and e.knockbackTimer > 0 then
            -- Knocked Back Enemy Movement
            local nextX = e.x + e.knockbackVx * dt
            local nextY = e.y + e.knockbackVy * dt
            local es = e.size
            local hitWall = false

            for _, corner in ipairs({
                {nextX, nextY},
                {nextX + es - 1, nextY},
                {nextX, nextY + es - 1},
                {nextX + es - 1, nextY + es - 1}
            }) do
                local tileX = math.floor(corner[1] / map.tileSize) + 1
                local tileY = math.floor(corner[2] / map.tileSize) + 1
                if tileX < 1 or tileX > map.width or tileY < 1 or tileY > map.height then
                    hitWall = true
                    break
                end
                if tilemap[tileY] and tilemap[tileY][tileX] == 1 then
                    hitWall = true
                    break
                end
            end

            -- Defeat by hitting wall in knockback state
            if hitWall then
                e.defeated = true
                e.defeatEffectTimer = 0.28
                goto continue_enemy
            end

            -- Defeat by hitting another enemy in knockback state
            for j, other in ipairs(enemy.enemies) do
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
                e.knockbackVx = 0
                e.knockbackVy = 0
                e.knockbackTimer = 0
                e.vx = 0
                e.vy = 0
                e.recoveryTimer = 0.15
                e._recoveryElapsed = 0
                local dir = (e.vx >= 0) and 1 or -1
                e._recoveryTargetVx = dir * (e.speedTier and e.speedTier.value or 120)
            end

        elseif e.recoveryTimer and e.recoveryTimer > 0 then
            -- Enemy attack recovery window
            local total = 0.15
            local elapsed = (e._recoveryElapsed or 0) + dt
            e._recoveryElapsed = elapsed
            local t = math.min(1, elapsed / total)
            e.vx = (e._recoveryTargetVx or 0) * t
            e.vy = 0
            e.recoveryTimer = e.recoveryTimer - dt

            if e.recoveryTimer <= 0 then
                e.vx = e._recoveryTargetVx or 0
                e.vy = 0
                e._recoveryElapsed = nil
                e._recoveryTargetVx = nil
            end

        else
            -- Normal enemy movement
            if e.targetVx then
                if math.abs(e.vx - e.targetVx) < 1 then
                    e.vx = e.targetVx
                    e.targetVx = nil
                else
                    e.vx = e.vx + utils.sign(e.targetVx - e.vx) * 200 * dt
                end
            end
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
    for _, e in ipairs(enemy.enemies) do
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            e.defeatEffectTimer = e.defeatEffectTimer - dt
        end
    end
end

function enemy.drawAll()
    for i, e in ipairs(enemy.enemies) do
        if e.defeated then goto continue_draw_enemy end

        love.graphics.setColor(e.speedTier and e.speedTier.color or {1,1,1})
        local half = e.size / 2
        love.graphics.setLineWidth(6)
        love.graphics.polygon('line',
            e.x + half, e.y, 
            e.x + e.size, e.y + half, 
            e.x + half, e.y + e.size, 
            e.x, e.y + half 
        )
        local c = e.speedTier and e.speedTier.color or {1,1,1}
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.polygon('fill',
            e.x + half, e.y,
            e.x + e.size, e.y + half,
            e.x + half, e.y + e.size, 
            e.x, e.y + half 
        )
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        ::continue_draw_enemy::
    end
    for _, e in ipairs(enemy.enemies) do
        -- Enemy death VFX
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            local half = e.size / 2
            local cx = e.x + half
            local cy = e.y + half
            local duration = config.ENEMY_DEFEAT_EFFECT_DURATION
            local t = 1 - (e.defeatEffectTimer / duration)
            local radius = half + t * config.ENEMY_DEFEAT_VFX_EXPAND + config.ENEMY_DEFEAT_VFX_OSC * math.sin(t * math.pi)
            if t < config.ENEMY_DEFEAT_FLASH_THRESHOLD then
                love.graphics.setColor(1, 1, 1, 0.85 * (1-t/config.ENEMY_DEFEAT_FLASH_THRESHOLD))
                love.graphics.circle('fill', cx, cy, radius * 0.7)
            end
            love.graphics.setColor(1, 0.2, 0.2, 0.8 * (1-t))
            love.graphics.circle('fill', cx, cy, radius)
            love.graphics.setColor(1, 1, 1, 0.7 * (1-t))
            love.graphics.circle('line', cx, cy, radius + 4)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

function enemy.getAll()
    return enemy.enemies
end

return enemy 
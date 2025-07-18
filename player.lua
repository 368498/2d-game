local config = require 'config'
local utils = require 'utils'

local player = {}

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

local function getNearestSpeedTier(val)
    local best, bestDist = SPEED_TIERS[1], math.abs(val - SPEED_TIERS[1].value)
    for _, tier in ipairs(SPEED_TIERS) do
        local dist = math.abs(val - tier.value)
        if dist < bestDist then
            best, bestDist = tier, dist
        end
    end
    return best
end

local function getNearestEnemySpeedTier(val)
    local best, bestDist = ENEMY_SPEED_TIERS[1], math.abs(val - ENEMY_SPEED_TIERS[1].value)
    for _, tier in ipairs(ENEMY_SPEED_TIERS) do
        local dist = math.abs(val - tier.value)
        if dist < bestDist then
            best, bestDist = tier, dist
        end
    end
    return best
end

function player.load()
    player.x = 5 * config.TILE_SIZE
    player.y = 5 * config.TILE_SIZE
    player.size = config.PLAYER_SIZE
    player.vx = 0
    player.vy = 0
    player.speed = 130
    player.targetSpeed = 130
    player.speedRamp = config.PLAYER_SPEED_RAMP
    player.accel = config.PLAYER_ACCEL
    player.friction = config.PLAYER_FRICTION
    player.facing = 'down'
    player.attack = { active = false, timer = 0, duration = config.ATTACK_DURATION, cooldown = config.ATTACK_COOLDOWN, cooldownTimer = 0, type = 'steal' }
    player.altAttack = { active = false, timer = 0, duration = config.ALT_ATTACK_DURATION, cooldown = config.ALT_ATTACK_COOLDOWN, cooldownTimer = 0, type = 'give', charge = 0, maxCharge = config.ALT_ATTACK_MAX_CHARGE, charging = false, chargeLevel = 1 }
    player.lastAttackTier = nil
    player.lastAltAttackTier = nil
    player.hitFlash = {active = false, x = 0, y = 0, timer = 0}
    player.selfChargeActive = false
    player.selfChargeTimer = 0
    player.selfChargeCooldown = 0
    player.selfChargeReady = true
end

function player.update(dt, map, tilemap, enemies)
    -- Scale acceleration and friction with speed for better control
    local baseSpeed = 100
    local accelScale = player.speed / baseSpeed
    local frictionScale = player.speed / baseSpeed
    local scaledAccel = config.PLAYER_ACCEL * accelScale
    local scaledFriction = config.PLAYER_FRICTION * frictionScale

    -- Snap targetSpeed to nearest tier
    local tier = getNearestSpeedTier(player.targetSpeed)
    player.targetSpeed = tier.value
    -- Snap speed to nearest tier as it ramps
    if player.speed < player.targetSpeed then
        player.speed = math.min(player.targetSpeed, player.speed + player.speedRamp * dt)
    elseif player.speed > player.targetSpeed then
        player.speed = math.max(player.targetSpeed, player.speed - player.speedRamp * dt)
    end
    if math.abs(player.speed - player.targetSpeed) < 2 then
        player.speed = player.targetSpeed
    end
    player.speedTier = tier

    -- Use tier-specific accel/friction
    local scaledAccel = tier.accel
    local scaledFriction = tier.friction

    local moveX, moveY = 0, 0
    if love.keyboard.isDown('up') then moveY = moveY - 1 end
    if love.keyboard.isDown('down') then moveY = moveY + 1 end
    if love.keyboard.isDown('left') then moveX = moveX - 1 end
    if love.keyboard.isDown('right') then moveX = moveX + 1 end

    -- Update facing direction if moving
    if moveX ~= 0 or moveY ~= 0 then
        if math.abs(moveX) > math.abs(moveY) then
            player.facing = moveX > 0 and 'right' or 'left'
        else
            player.facing = moveY > 0 and 'down' or 'up'
        end
    end

    -- Normalize diagonal movement
    if moveX ~= 0 and moveY ~= 0 then
        local norm = 1 / math.sqrt(2)
        moveX, moveY = moveX * norm, moveY * norm
    end

    local prevVx, prevVy = player.vx, player.vy

    -- Turn assist: boost accel if input is sharply different from velocity
    local turnAssist = 1
    if (moveX ~= 0 or moveY ~= 0) and (player.vx ~= 0 or player.vy ~= 0) then
        local inputLen = math.sqrt(moveX^2 + moveY^2)
        local velLen = math.sqrt(player.vx^2 + player.vy^2)
        if inputLen > 0 and velLen > 0 then
            local dot = (moveX * player.vx + moveY * player.vy) / (inputLen * velLen)
            local angle = math.acos(math.max(-1, math.min(1, dot)))
            turnAssist = 1 + 1.5 * (angle / math.pi)
        end
    end

    -- Acceleration
    player.vx = player.vx + scaledAccel * moveX * dt * turnAssist
    player.vy = player.vy + scaledAccel * moveY * dt * turnAssist

    -- Direction change boost
    if moveX ~= 0 and utils.sign(moveX) ~= utils.sign(prevVx) then
        player.vx = player.vx + scaledAccel * moveX * dt * 2 * turnAssist
    end
    if moveY ~= 0 and utils.sign(moveY) ~= utils.sign(prevVy) then
        player.vy = player.vy + scaledAccel * moveY * dt * 2 * turnAssist
    end

    -- Friction
    if moveX == 0 then
        if player.vx > 0 then
            player.vx = math.max(0, player.vx - scaledFriction * dt)
        elseif player.vx < 0 then
            player.vx = math.min(0, player.vx + scaledFriction * dt)
        end
    end
    if moveY == 0 then
        if player.vy > 0 then
            player.vy = math.max(0, player.vy - scaledFriction * dt)
        elseif player.vy < 0 then
            player.vy = math.min(0, player.vy + scaledFriction * dt)
        end
    end

    -- Clamp velocity
    local maxSpeed = player.speed
    local len = math.sqrt(player.vx^2 + player.vy^2)
    if len > maxSpeed then
        player.vx = player.vx / len * maxSpeed
        player.vy = player.vy / len * maxSpeed
    end

    -- Update position in pixels
    local nextX = player.x + player.vx * dt
    local nextY = player.y + player.vy * dt
    local ps = player.size
    local blocked = false
    for _, corner in ipairs({
        {nextX, nextY},
        {nextX + ps - 1, nextY},
        {nextX, nextY + ps - 1},
        {nextX + ps - 1, nextY + ps - 1}
    }) do
        if map and tilemap and map.tileSize and tilemap then
            local tileX = math.floor(corner[1] / map.tileSize) + 1
            local tileY = math.floor(corner[2] / map.tileSize) + 1
            if tileX < 1 or tileX > map.width or tileY < 1 or tileY > map.height then
                blocked = true
                break
            end
            if tilemap[tileY] and tilemap[tileY][tileX] == 1 then
                blocked = true
                break
            end
        end
    end
    if not blocked then
        player.x = nextX
        player.y = nextY
    else
        player.vx = 0
        player.vy = 0
    end

    -- Update player angle for facing direction
    if math.abs(player.vx) > 1 or math.abs(player.vy) > 1 then
        player.angle = math.atan2(player.vy, player.vx) + math.pi/2
    end

    -- Self-charge logic, attack logic, and other player-specific update code should be added here.
    -- (You can continue moving the rest of the logic from main.lua as needed.)
    -- Attack timer and cooldown for both attacks
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active then
            atk.timer = atk.timer - dt
            if atk.timer <= 0 then
                atk.active = false
                atk.cooldownTimer = atk.cooldown
            end
        elseif atk.cooldownTimer > 0 then
            atk.cooldownTimer = atk.cooldownTimer - dt
            if atk.cooldownTimer < 0 then
                atk.cooldownTimer = 0
            end
        end
    end
    -- On-hit effect: check collision for both attacks
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active and enemies then
            local ps = player.size
            local cx, cy = player.x + ps/2, player.y + ps/2
            local angle = player.angle or 0
            -- Place attack circle in front of player
            local attackDist = ps * 0.7
            local attackRadius = ps * 0.45
            local circleX = cx + math.cos(angle - math.pi/2) * attackDist
            local circleY = cy + math.sin(angle - math.pi/2) * attackDist
            for i, enemy in ipairs(enemies) do
                local ex, ey, es = enemy.x, enemy.y, enemy.size
                if utils.circleRectOverlap(circleX, circleY, attackRadius, ex, ey, es, es) then
                    local idx = 1
                    for i, t in ipairs(SPEED_TIERS) do if t.value == player.targetSpeed then idx = i end end
                    local tier = SPEED_TIERS[idx]
                    -- Get enemy tier index
                    local enemySpeed = math.abs(enemy.vx)
                    local enemyIdx = 1
                    for i, t in ipairs(ENEMY_SPEED_TIERS) do if t.value == enemy.targetSpeed then enemyIdx = i end end
                    if atk.type == 'steal' then
                        if enemyIdx > 1 and player.lastAttackTier ~= idx then
                            if idx < #SPEED_TIERS then
                                player.targetSpeed = SPEED_TIERS[idx+1].value
                            end
                            player.lastAttackTier = idx
                            local newEnemyIdx = math.max(1, enemyIdx-1)
                            if newEnemyIdx ~= enemyIdx then
                                enemy.targetSpeed = ENEMY_SPEED_TIERS[newEnemyIdx].value
                                for i, t in ipairs(ENEMY_SPEED_TIERS) do
                                    if t.value == enemy.targetSpeed then
                                        enemy.speedTier = t
                                        enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        enemy.targetVx = nil
                                    end
                                end
                                for i, t in ipairs(SPEED_TIERS) do
                                    if t.value == player.targetSpeed then
                                        player.speedTier = t
                                        local len = math.sqrt(player.vx^2 + player.vy^2)
                                        if len > 0 then
                                            player.vx = player.vx / len * t.value
                                            player.vy = player.vy / len * t.value
                                        else
                                            player.vx = t.value
                                            player.vy = 0
                                        end
                                    end
                                end
                                atk.active = false
                                atk.timer = 0
                                player.hitFlash.active = true
                                player.hitFlash.x = circleX
                                player.hitFlash.y = circleY
                                player.hitFlash.timer = 0.15
                            end
                        end
                    elseif atk.type == 'give' then
                        local tiersToGive = player.altAttack.chargeLevel or 1
                        if idx == 1 or enemyIdx == #ENEMY_SPEED_TIERS then
                            if enemyIdx == #ENEMY_SPEED_TIERS and player.lastAltAttackTier ~= idx then
                                player.lastAltAttackTier = idx
                                local dx = (enemy.x + enemy.size/2) - (player.x + player.size/2)
                                local dy = (enemy.y + enemy.size/2) - (player.y + player.size/2)
                                local dist = math.sqrt(dx*dx + dy*dy)
                                if dist == 0 then dist = 1 end
                                local knockbackStrength = 220 * tiersToGive * 0.3
                                local duration = (0.18 + 0.08 * (tiersToGive-1)) * 0.3
                                enemy.knockbackVx = (dx / dist) * knockbackStrength
                                enemy.knockbackVy = (dy / dist) * knockbackStrength
                                enemy.knockbackTimer = duration
                                atk.active = false
                                atk.timer = 0
                                player.hitFlash.active = true
                                player.hitFlash.x = circleX
                                player.hitFlash.y = circleY
                                player.hitFlash.timer = 0.15
                                player.altAttack.charge = 0
                                player.altAttack.chargeLevel = 1
                            end
                        else
                            if player.lastAltAttackTier ~= idx then
                                local newIdx = math.max(1, idx - tiersToGive)
                                local newEnemyIdx = math.min(#ENEMY_SPEED_TIERS, enemyIdx + tiersToGive)
                                if newEnemyIdx ~= enemyIdx then
                                    player.targetSpeed = SPEED_TIERS[newIdx].value
                                    player.lastAltAttackTier = idx
                                    enemy.targetSpeed = ENEMY_SPEED_TIERS[newEnemyIdx].value
                                    for i, t in ipairs(ENEMY_SPEED_TIERS) do
                                        if t.value == enemy.targetSpeed then
                                            enemy.speedTier = t
                                            enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        end
                                    end
                                    for i, t in ipairs(SPEED_TIERS) do
                                        if t.value == player.targetSpeed then
                                            player.speedTier = t
                                            local len = math.sqrt(player.vx^2 + player.vy^2)
                                            if len > 0 then
                                                player.vx = player.vx / len * t.value
                                                player.vy = player.vy / len * t.value
                                            else
                                                player.vx = t.value
                                                player.vy = 0
                                            end
                                        end
                                    end
                                    local dx = (enemy.x + enemy.size/2) - (player.x + player.size/2)
                                    local dy = (enemy.y + enemy.size/2) - (player.y + player.size/2)
                                    local dist = math.sqrt(dx*dx + dy*dy)
                                    if dist == 0 then dist = 1 end
                                    local knockbackStrength = 220 * tiersToGive
                                    local duration = 0.18 + 0.08 * (tiersToGive-1)
                                    enemy.knockbackVx = (dx / dist) * knockbackStrength
                                    enemy.knockbackVy = (dy / dist) * knockbackStrength
                                    enemy.knockbackTimer = duration
                                    atk.active = false
                                    atk.timer = 0
                                    player.hitFlash.active = true
                                    player.hitFlash.x = circleX
                                    player.hitFlash.y = circleY
                                    player.hitFlash.timer = 0.15
                                    player.altAttack.charge = 0
                                    player.altAttack.chargeLevel = 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not player.attack.active then player.lastAttackTier = nil end
    if not player.altAttack.active then player.lastAltAttackTier = nil end
    if player.hitFlash.active then
        player.hitFlash.timer = player.hitFlash.timer - dt
        if player.hitFlash.timer <= 0 then
            player.hitFlash.active = false
        end
    end
end

function player.draw()
    -- Draw player as a rounded arrowhead (Google Maps puck style) with colored outline
    love.graphics.setColor(player.speedTier and player.speedTier.color or {1,1,1})
    local px, py, ps = player.x, player.y, player.size
    local cx, cy = px + ps / 2, py + ps / 2
    local angle = player.angle or 0
    local tip = {0, -ps/2}
    local left = {-ps/2.2, ps/3}
    local right = {ps/2.2, ps/3}
    local base = {0, ps/2.1}
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(angle)
    love.graphics.setLineWidth(6)
    love.graphics.polygon('line', tip[1], tip[2], right[1], right[2], base[1], base[2], left[1], left[2])
    love.graphics.setColor(1, 0.2, 0.5)
    love.graphics.polygon('fill', tip[1], tip[2], right[1], right[2], base[1], base[2], left[1], left[2])
    love.graphics.setColor(1, 0.2, 0.5)
    love.graphics.arc('fill', 0, ps/3, ps/2.2, math.pi*0.15, math.pi*0.85)
    love.graphics.pop()
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    -- Draw both attacks with distinct VFX
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active then
            local ps = player.size
            local cx, cy = player.x + ps/2, player.y + ps/2
            local angle = player.angle or 0
            local attackLength = ps
            local attackWidth = ps * 0.8
            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.rotate(angle)
            if atk.type == 'steal' then
                love.graphics.setColor(1, 1, 1, 0.3)
                for i = 1, 3 do
                    love.graphics.rectangle('fill', -attackWidth/2 - i, -ps/2 - attackLength - i, attackWidth + 2*i, attackLength + 2*i)
                end
                love.graphics.setColor(1, 1, 1)
                love.graphics.rectangle('fill', -attackWidth/2, -ps/2 - attackLength, attackWidth, attackLength)
            else
                local t = love.timer.getTime()
                local pulse = 0.2 * math.sin(t * 10)
                love.graphics.setColor(1, 0.5 + 0.2 * math.sin(t * 8), 0, 0.7)
                love.graphics.rectangle('fill', -attackWidth/2 - pulse, -ps/2 - attackLength - pulse, attackWidth + 2*pulse, attackLength + 2*pulse, 12, 12)
                love.graphics.setColor(1, 0.5, 0)
                love.graphics.rectangle('fill', -attackWidth/2, -ps/2 - attackLength, attackWidth, attackLength, 12, 12)
            end
            love.graphics.pop()
            love.graphics.setColor(1, 1, 1)
        end
    end
    -- (Continue moving the rest of the player drawing logic from main.lua as needed.)
    if player.hitFlash.active then
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.circle('fill', player.hitFlash.x, player.hitFlash.y, config.PLAYER_HIT_FLASH_RADIUS * player.hitFlash.timer / config.PLAYER_HIT_FLASH_DURATION)
        love.graphics.setColor(1, 1, 1)
    end
end

function player.keypressed(key)
    if key == 'space' and not player.attack.active and player.attack.cooldownTimer == 0 then
        player.attack.active = true
        player.attack.timer = player.attack.duration
    end
    if key == 'z' and not player.altAttack.active and player.altAttack.cooldownTimer == 0 and not player.altAttack.charging then
        local tierName = player.speedTier and player.speedTier.name or 'normal'
        if tierName == 'superfast' then
            player.altAttack.maxAllowedCharge = 3
            player.altAttack.charging = true
            player.altAttack.charge = 0
        elseif tierName == 'fast' then
            player.altAttack.maxAllowedCharge = 2
            player.altAttack.charging = true
            player.altAttack.charge = 0
        else
            player.altAttack.maxAllowedCharge = 1
            player.altAttack.charging = true
            player.altAttack.charge = 0
        end
    end
end

function player.keyreleased(key)
    if key == 'z' and player.altAttack.charging and not player.altAttack.active and player.altAttack.cooldownTimer == 0 then
        player.altAttack.charging = false
        local maxCharge = player.altAttack.maxAllowedCharge or 1
        local tierName = player.speedTier and player.speedTier.name or 'normal'
        local chargeLevel
        if tierName == 'superfast' or tierName == 'fast' then
            chargeLevel = math.min(maxCharge, math.max(1, math.floor(player.altAttack.charge / 0.7) + 1))
        else
            chargeLevel = 1
        end
        player.altAttack.chargeLevel = chargeLevel
        player.altAttack.active = true
        player.altAttack.timer = player.altAttack.duration
    end
end

return player 
local config = require 'config'
local utils = require 'utils'

local player = {}

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
    player.aimDirection = {x = 0, y = -1} -- Default aim up
    player.lastInputType = 'keyboard' -- Track last input type for priority

    player.attack = { active = false, timer = 0, duration = config.ATTACK_DURATION, cooldown = config.ATTACK_COOLDOWN, cooldownTimer = 0, type = 'steal' }
    player.altAttack = { active = false, timer = 0, duration = config.ALT_ATTACK_DURATION, cooldown = config.ALT_ATTACK_COOLDOWN, cooldownTimer = 0, type = 'give', charge = 0, maxCharge = config.ALT_ATTACK_MAX_CHARGE, charging = false, chargeLevel = 1 }
    player.lastAttackTier = nil
    player.lastAltAttackTier = nil
    player.hitFlash = {active = false, x = 0, y = 0, timer = 0}
    player.selfChargeActive = false
    player.selfChargeTimer = 0
    player.selfChargeCooldown = 0
    player.selfChargeReady = true

    -- HPs
    player.maxHealth = config.PLAYER_MAX_HEALTH or 5
    player.health = player.maxHealth
    player.invulnTimer = 0
    player.damageFlashTimer = 0
end

function player.update(dt, map, tilemap, enemies)
    -- iFrame timer
    if player.invulnTimer and player.invulnTimer > 0 then
        player.invulnTimer = player.invulnTimer - dt
        if player.invulnTimer < 0 then player.invulnTimer = 0 end
    end
    if player.damageFlashTimer and player.damageFlashTimer > 0 then
        player.damageFlashTimer = player.damageFlashTimer - dt
        if player.damageFlashTimer < 0 then player.damageFlashTimer = 0 end
    end
    -- Control feel settings
    local baseSpeed = 100
    local accelScale = player.speed / baseSpeed
    local frictionScale = player.speed / baseSpeed
    local scaledAccel = config.PLAYER_ACCEL * accelScale
    local scaledFriction = config.PLAYER_FRICTION * frictionScale

    -- Snap targetSpeed to nearest speed tier
    local tier = utils.getNearestSpeedTier(player.targetSpeed, config.SPEED_TIERS)
    player.targetSpeed = tier.value

    if player.speed < player.targetSpeed then
        player.speed = math.min(player.targetSpeed, player.speed + player.speedRamp * dt)
    elseif player.speed > player.targetSpeed then
        player.speed = math.max(player.targetSpeed, player.speed - player.speedRamp * dt)
    end

    if math.abs(player.speed - player.targetSpeed) < 2 then
        player.speed = player.targetSpeed
    end
    player.speedTier = tier

    --tier-specific accel/friction
    local scaledAccel = tier.accel
    local scaledFriction = tier.friction

    local moveX, moveY = 0, 0
    if love.keyboard.isDown('w') then moveY = moveY - 1 end
    if love.keyboard.isDown('s') then moveY = moveY + 1 end
    if love.keyboard.isDown('a') then moveX = moveX - 1 end
    if love.keyboard.isDown('d') then moveX = moveX + 1 end

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

    -- Turn assist to boost accel if input is sharply different from velocity
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

    -- Update position pixels
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

    -- Update player angle to facing direction
    if math.abs(player.vx) > 1 or math.abs(player.vy) > 1 then
        player.angle = math.atan2(player.vy, player.vx) + math.pi/2
    end

    -- Handle aim direction with priority: last input received wins
    local keyboardAimX, keyboardAimY = 0, 0
    if love.keyboard.isDown('right') then keyboardAimX = keyboardAimX + 1 end
    if love.keyboard.isDown('left') then keyboardAimX = keyboardAimX - 1 end
    if love.keyboard.isDown('down') then keyboardAimY = keyboardAimY + 1 end
    if love.keyboard.isDown('up') then keyboardAimY = keyboardAimY - 1 end
    
    -- Check for keyboard input
    if keyboardAimX ~= 0 or keyboardAimY ~= 0 then
        local len = math.sqrt(keyboardAimX * keyboardAimX + keyboardAimY * keyboardAimY)
        player.aimDirection.x = keyboardAimX / (len ~= 0 and len or 1)
        player.aimDirection.y = keyboardAimY / (len ~= 0 and len or 1)
        player.lastInputType = 'keyboard'
    end
    
    -- Check for mouse input (only if no keyboard input this frame)
    if keyboardAimX == 0 and keyboardAimY == 0 then
        local mouseX, mouseY = love.mouse.getPosition()
        local playerCenterX = player.x + player.size / 2
        local playerCenterY = player.y + player.size / 2
        local dx = mouseX - playerCenterX
        local dy = mouseY - playerCenterY
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 5 then -- Only update if mouse is far enough from player
            player.aimDirection.x = dx / distance
            player.aimDirection.y = dy / distance
            player.lastInputType = 'mouse'
        end
    end

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
    -- On-hit effect: check collision 
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active and enemies then
            local ps = player.size
            local cx, cy = player.x + ps/2, player.y + ps/2

            local attackDist = ps * 0.7
            local attackRadius = ps * 0.45

            local circleX = cx + player.aimDirection.x * attackDist
            local circleY = cy + player.aimDirection.y * attackDist
            
            for i, enemy in ipairs(enemies) do
                local ex, ey, es = enemy.x, enemy.y, enemy.size
                if utils.circleRectOverlap(circleX, circleY, attackRadius, ex, ey, es, es) then
                    local idx = 1
                    for i, t in ipairs(config.SPEED_TIERS) do if t.value == player.targetSpeed then idx = i end end
                    local tier = config.SPEED_TIERS[idx]
                    -- Get enemy tier index
                    local enemySpeed = math.abs(enemy.vx)
                    local enemyIdx = 1
                    for i, t in ipairs(config.ENEMY_SPEED_TIERS) do if t.value == enemy.targetSpeed then enemyIdx = i end end
                    if atk.type == 'steal' then
                        if enemyIdx > 1 and player.lastAttackTier ~= idx then
                            if idx < #config.SPEED_TIERS then
                                player.targetSpeed = config.SPEED_TIERS[idx+1].value
                            end
                            player.lastAttackTier = idx
                            local newEnemyIdx = math.max(1, enemyIdx-1)
                            if newEnemyIdx ~= enemyIdx then
                                enemy.targetSpeed = config.ENEMY_SPEED_TIERS[newEnemyIdx].value
                                for i, t in ipairs(config.ENEMY_SPEED_TIERS) do
                                    if t.value == enemy.targetSpeed then
                                        enemy.speedTier = t
                                        enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        enemy.targetVx = nil
                                    end
                                end
                                for i, t in ipairs(config.SPEED_TIERS) do
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
                        if idx == 1 or enemyIdx == #config.ENEMY_SPEED_TIERS then
                            if enemyIdx == #config.ENEMY_SPEED_TIERS and player.lastAltAttackTier ~= idx then
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
                                local newEnemyIdx = math.min(#config.ENEMY_SPEED_TIERS, enemyIdx + tiersToGive)
                                if newEnemyIdx ~= enemyIdx then
                                    player.targetSpeed = config.SPEED_TIERS[newIdx].value
                                    player.lastAltAttackTier = idx
                                    enemy.targetSpeed = config.ENEMY_SPEED_TIERS[newEnemyIdx].value
                                    for i, t in ipairs(config.ENEMY_SPEED_TIERS) do
                                        if t.value == enemy.targetSpeed then
                                            enemy.speedTier = t
                                            enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        end
                                    end
                                    for i, t in ipairs(config.SPEED_TIERS) do
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

function player.takeDamage(amount)
    if player.invulnTimer and player.invulnTimer > 0 then return end
    player.health = math.max(0, (player.health or player.maxHealth) - (amount or 1))
    player.invulnTimer = config.PLAYER_IFRAME_TIME or 0.8
    player.damageFlashTimer = config.PLAYER_DAMAGE_FLASH_DURATION or 0.25
    --  knockback away from impact direction 
    local knockMagnitude = (config.PLAYER_HIT_KNOCKBACK or 120)
    if player.vx ~= 0 or player.vy ~= 0 then
        local len = math.sqrt(player.vx*player.vx + player.vy*player.vy)
        if len > 0 then
            player.vx = -player.vx / len * knockMagnitude
            player.vy = -player.vy / len * knockMagnitude
        end
    end
    if love and love.audio and love.audio.newSource then
        -- #TODO assets added later
    end
end

function player.isDead()
    return (player.health or 0) <= 0
end

function player.draw()
    local blink = false
    if (player.invulnTimer or 0) > 0 then
        local t = love.timer.getTime()
        blink = (math.floor(t * 20) % 2) == 0
    end
    if blink then
        love.graphics.setColor(1, 1, 1, 0.35)
    else
        love.graphics.setColor(player.speedTier and player.speedTier.color or {1,1,1})
    end
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
    
    -- Draw aim direction arrow
    local px, py, ps = player.x, player.y, player.size
    local cx, cy = px + ps / 2, py + ps / 2

    local aimAngle = math.atan2(player.aimDirection.y, player.aimDirection.x)

    local arrowLength = ps * 0.4
    local arrowWidth = ps * 0.15
    local arrowStartX = cx + math.cos(aimAngle) * (ps * 0.6)
    local arrowStartY = cy + math.sin(aimAngle) * (ps * 0.6)
    local arrowEndX = cx + math.cos(aimAngle) * (ps * 0.6 + arrowLength)
    local arrowEndY = cy + math.sin(aimAngle) * (ps * 0.6 + arrowLength)
    
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(3)
    love.graphics.line(arrowStartX, arrowStartY, arrowEndX, arrowEndY)
    
    --  arrow head
    local headAngle1 = aimAngle + math.pi * 0.75
    local headAngle2 = aimAngle - math.pi * 0.75
    local headLength = ps * 0.2
    local head1X = arrowEndX + math.cos(headAngle1) * headLength
    local head1Y = arrowEndY + math.sin(headAngle1) * headLength
    local head2X = arrowEndX + math.cos(headAngle2) * headLength
    local head2Y = arrowEndY + math.sin(headAngle2) * headLength
    
    love.graphics.line(arrowEndX, arrowEndY, head1X, head1Y)
    love.graphics.line(arrowEndX, arrowEndY, head2X, head2Y)
    
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    
    -- Draw attacks
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active then
            local ps = player.size
            local cx, cy = player.x + ps/2, player.y + ps/2

            -- Calculate angle from aim direction for visual effects
            local angle = math.atan2(player.aimDirection.y, player.aimDirection.x) + math.pi/2
            
            --VFX tuning by  tier
            local tierName = (player.speedTier and player.speedTier.name) or 'normal'
            local sizeMul, alphaMul, pulseMul
            if tierName == 'slowed' then
                sizeMul, alphaMul, pulseMul = 0.9, 0.9, 0.9
            elseif tierName == 'fast' then
                sizeMul, alphaMul, pulseMul = 1.15, 1.1, 1.1
            elseif tierName == 'superfast' then
                sizeMul, alphaMul, pulseMul = 1.3, 1.2, 1.25
            else -- normal
                sizeMul, alphaMul, pulseMul = 1.0, 1.0, 1.0
            end
            
            local attackLength = ps * (1.0 * sizeMul)
            local attackWidth = ps * (0.8 * sizeMul)
            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.rotate(angle)
            if atk.type == 'steal' then
                local baseAlpha = 0.26 * alphaMul
                love.graphics.setColor(1, 1, 1, baseAlpha)
                local passes = tierName == 'superfast' and 4 or (tierName == 'fast' and 3 or 2)
                for i = 1, passes do
                    love.graphics.rectangle('fill', -attackWidth/2 - i, -ps/2 - attackLength - i, attackWidth + 2*i, attackLength + 2*i)
                end
                love.graphics.setColor(1, 1, 1, math.min(1, 0.85 * alphaMul))
                love.graphics.rectangle('fill', -attackWidth/2, -ps/2 - attackLength, attackWidth, attackLength)
            else
                local t = love.timer.getTime()
                local pulse = (0.2 * sizeMul) * math.sin(t * (10 * pulseMul))
                love.graphics.setColor(1, 0.5 + 0.2 * math.sin(t * (8 * pulseMul)), 0, math.min(1, 0.7 * alphaMul))
                love.graphics.rectangle('fill', -attackWidth/2 - pulse, -ps/2 - attackLength - pulse, attackWidth + 2*pulse, attackLength + 2*pulse, 12, 12)
                love.graphics.setColor(1, 0.5, 0, math.min(1, 0.95 * alphaMul))
                love.graphics.rectangle('fill', -attackWidth/2, -ps/2 - attackLength, attackWidth, attackLength, 12, 12)
            end
            love.graphics.pop()
            love.graphics.setColor(1, 1, 1)
        end
    end

    if player.hitFlash.active then
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.circle('fill', player.hitFlash.x, player.hitFlash.y, config.PLAYER_HIT_FLASH_RADIUS * player.hitFlash.timer / config.PLAYER_HIT_FLASH_DURATION)
        love.graphics.setColor(1, 1, 1)
    end
end

function player.keypressed(key)
    -- 'take' attack
    if key == 'space' and not player.attack.active and player.attack.cooldownTimer == 0 then
        player.attack.active = true
        player.attack.timer = player.attack.duration
    end
    -- 'give' attack
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


function player.mousepressed(x, y, button, istouch, presses)
    if button == 1 then -- Left click
        if not player.attack.active and player.attack.cooldownTimer == 0 then
            player.attack.active = true
            player.attack.timer = player.attack.duration
        end
    elseif button == 2 then -- Right click 
        if not player.altAttack.active and player.altAttack.cooldownTimer == 0 and not player.altAttack.charging then
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
end

function player.mousereleased(x, y, button, istouch, presses)
    if button == 2 and player.altAttack.charging and not player.altAttack.active and player.altAttack.cooldownTimer == 0 then
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
-- main.lua

function math.sign(x)
    return (x > 0 and 1) or (x < 0 and -1) or 0
end

-- Helper: Check rectangle overlap
local function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- Helper: Check circle-rectangle overlap for more natural collision (player as circle, enemy as rect)
local function circleRectOverlap(cx, cy, cr, rx, ry, rw, rh)
    local closestX = math.max(rx, math.min(cx, rx + rw))
    local closestY = math.max(ry, math.min(cy, ry + rh))
    local dx = cx - closestX
    local dy = cy - closestY
    return (dx * dx + dy * dy) < (cr * cr)
end

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
    -- Load assets, initialize game state
    player = {
        x = 5 * 32, y = 5 * 32, -- start in pixels
        size = 32,
        vx = 0, vy = 0,
        speed = 130,
        targetSpeed = 130,
        speedRamp = 200, -- slower ramp
        accel = 300,
        friction = 260,
        facing = 'down',
        attack = { active = false, timer = 0, duration = 0.15, cooldown = 0.4, cooldownTimer = 0, type = 'steal' },
        altAttack = { active = false, timer = 0, duration = 0.15, cooldown = 0.4, cooldownTimer = 0, type = 'give', charge = 0, maxCharge = 2.0, charging = false, chargeLevel = 1 },
        lastAttackTier = nil,
        lastAltAttackTier = nil,
        hitFlash = {active = false, x = 0, y = 0, timer = 0}
    }
    map = {
        width = 30, -- was 10
        height = 22, -- was 10
        tileSize = 32
    }
    -- Tilemap: 1 = wall, 0 = empty
    tilemap = {}
    for y = 1, map.height do
        tilemap[y] = {}
        for x = 1, map.width do
            if x == 1 or x == map.width or y == 1 or y == map.height then
                tilemap[y][x] = 1 -- border wall
            else
                tilemap[y][x] = 0 -- empty
            end
        end
    end
    local enemyStartTier = ENEMY_SPEED_TIERS[2] -- 'normal' tier
    enemies = {
        {
            x = 2 * 32, y = 2 * 32,
            size = 32,
            vx = enemyStartTier.value,
            vy = 0,
            minX = 2 * 32,
            maxX = 27 * 32,
            speed = enemyStartTier.value,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier
        },
        {
            x = 25 * 32, y = 15 * 32,
            size = 32,
            vx = -enemyStartTier.value,
            vy = 0,
            minX = 2 * 32,
            maxX = 27 * 32,
            speed = enemyStartTier.value,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier
        }
    }
end

-- Helper: check if a world position is a wall tile
function isWallAt(px, py)
    local tileX = math.floor(px / map.tileSize) + 1
    local tileY = math.floor(py / map.tileSize) + 1
    if tileX < 1 or tileX > map.width or tileY < 1 or tileY > map.height then
        return true
    end
    return tilemap[tileY] and tilemap[tileY][tileX] == 1
end

function love.update(dt)
    -- Scale acceleration and friction with speed for better control
    local baseSpeed = 100
    local accelScale = player.speed / baseSpeed
    local frictionScale = player.speed / baseSpeed
    local scaledAccel = 300 * accelScale
    local scaledFriction = 260 * frictionScale

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
            -- dot = 1: same direction, dot = -1: opposite, dot = 0: perpendicular
            local angle = math.acos(math.max(-1, math.min(1, dot)))
            -- Boost more as angle increases (up to 2x at 90+ degrees)
            turnAssist = 1 + 1.5 * (angle / math.pi)
        end
    end

    -- Acceleration
    player.vx = player.vx + scaledAccel * moveX * dt * turnAssist
    player.vy = player.vy + scaledAccel * moveY * dt * turnAssist

    -- Direction change boost
    if moveX ~= 0 and math.sign(moveX) ~= math.sign(prevVx) then
        player.vx = player.vx + scaledAccel * moveX * dt * 2 * turnAssist
    end
    if moveY ~= 0 and math.sign(moveY) ~= math.sign(prevVy) then
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
    -- Check collision with walls (AABB corners)
    local ps = player.size
    local blocked = false
    for _, corner in ipairs({
        {nextX, nextY},
        {nextX + ps - 1, nextY},
        {nextX, nextY + ps - 1},
        {nextX + ps - 1, nextY + ps - 1}
    }) do
        if isWallAt(corner[1], corner[2]) then
            blocked = true
            break
        end
    end
    if not blocked then
        player.x = nextX
        player.y = nextY
    else
        -- If blocked, zero out velocity in that direction
        player.vx = 0
        player.vy = 0
    end

    -- Enemy speed tier logic
    -- Remove automatic enemy speed tier logic and clamping
    -- (enemy.targetSpeed and enemy.speedTier are only set by player attacks)
    -- Smoothly ramp enemy.vx toward enemy.targetVx if set
    for i, enemy in ipairs(enemies) do
        if enemy.targetVx then
            if math.abs(enemy.vx - enemy.targetVx) < 1 then
                enemy.vx = enemy.targetVx
                enemy.targetVx = nil
            else
                enemy.vx = enemy.vx + math.sign(enemy.targetVx - enemy.vx) * 200 * dt
            end
        end
        -- (No clamping of enemy.vx to tier speed)
        -- Smoothly ramp enemy.vy toward enemy.targetVy if set
        if enemy.targetVy then
            if math.abs(enemy.vy - enemy.targetVy) < 1 then
                enemy.vy = enemy.targetVy
                enemy.targetVy = nil
            else
                enemy.vy = enemy.vy + math.sign(enemy.targetVy - enemy.vy) * 200 * dt
            end
        end
        -- Enemy movement: back and forth horizontally, now with vy
        enemy.x = enemy.x + enemy.vx * dt
        enemy.y = enemy.y + (enemy.vy or 0) * dt
        if enemy.x < enemy.minX then
            enemy.x = enemy.minX
            enemy.vx = -enemy.vx
        elseif enemy.x > enemy.maxX then
            enemy.x = enemy.maxX
            enemy.vx = -enemy.vx
        end
        -- Clamp enemy.y to window bounds
        if enemy.y < 0 then enemy.y = 0; enemy.vy = -enemy.vy end
        if enemy.y > 720 - enemy.size then enemy.y = 720 - enemy.size; enemy.vy = -enemy.vy end
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
    -- On-hit effect: check collision for both attacks
    for _, atk in ipairs({player.attack, player.altAttack}) do
        if atk.active then
            local ps = player.size
            local cx, cy = player.x + ps/2, player.y + ps/2
            local angle = player.angle or 0
            local attackLength = ps
            local attackWidth = ps * 0.8
            -- Center of attack area in local space is (0, -ps/2 - attackLength/2)
            local localAx, localAy = 0, -ps/2 - attackLength/2
            local cosA, sinA = math.cos(angle), math.sin(angle)
            local worldAx = cx + localAx * cosA - localAy * sinA
            local worldAy = cy + localAx * sinA + localAy * cosA
            for i, enemy in ipairs(enemies) do
                local ex, ey, es = enemy.x, enemy.y, enemy.size
                if rectsOverlap(
                    cx + (-attackWidth/2) * cosA - (-ps/2 - attackLength) * sinA,
                    cy + (-attackWidth/2) * sinA + (-ps/2 - attackLength) * cosA,
                    attackWidth, attackLength, ex, ey, es, es) then
                    local idx = 1
                    for i, t in ipairs(SPEED_TIERS) do if t.value == player.targetSpeed then idx = i end end
                    local tier = SPEED_TIERS[idx]
                    -- Get enemy tier index
                    local enemySpeed = math.abs(enemy.vx)
                    local enemyIdx = 1
                    for i, t in ipairs(ENEMY_SPEED_TIERS) do if t.value == enemy.targetSpeed then enemyIdx = i end end
                    if atk.type == 'steal' then
                        -- Only allow if enemy is not at slowest tier, and don't go below it
                        if enemyIdx > 1 and player.lastAttackTier ~= idx then
                            if idx < #SPEED_TIERS then
                                player.targetSpeed = SPEED_TIERS[idx+1].value
                            end
                            player.lastAttackTier = idx
                            -- Lower enemy tier, but not below 1
                            local newEnemyIdx = math.max(1, enemyIdx-1)
                            if newEnemyIdx ~= enemyIdx then -- Only affect if tier changes
                                enemy.targetSpeed = ENEMY_SPEED_TIERS[newEnemyIdx].value
                                -- Snap enemy tier and velocity
                                for i, t in ipairs(ENEMY_SPEED_TIERS) do
                                    if t.value == enemy.targetSpeed then
                                        enemy.speedTier = t
                                        enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        enemy.targetVx = nil -- Clamp to tier speed, prevent ramping
                                    end
                                end
                                -- Snap player tier and velocity
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
                                -- End attack instantly and flash at contact point (center of attack area)
                                atk.active = false
                                atk.timer = 0
                                player.hitFlash.active = true
                                player.hitFlash.x = worldAx
                                player.hitFlash.y = worldAy
                                player.hitFlash.timer = 0.15
                                -- Only apply velocity reduction if tier changed (removed punch/knockback)
                            end
                        end
                    elseif atk.type == 'give' then
                        -- Only allow if enemy is not at highest tier for tier change
                        local tiersToGive = player.altAttack.chargeLevel or 1
                        if idx == 1 or enemyIdx == #ENEMY_SPEED_TIERS then
                            -- At slowed speed or enemy at max, do nothing for tier or velocity
                        else
                            if player.lastAltAttackTier ~= idx then
                                -- Transfer as many tiers as chargeLevel, but not below tier 1 or above enemy max
                                local newIdx = math.max(1, idx - tiersToGive)
                                local newEnemyIdx = math.min(#ENEMY_SPEED_TIERS, enemyIdx + tiersToGive)
                                if newEnemyIdx ~= enemyIdx then -- Only affect if tier changes
                                    player.targetSpeed = SPEED_TIERS[newIdx].value
                                    player.lastAltAttackTier = idx
                                    enemy.targetSpeed = ENEMY_SPEED_TIERS[newEnemyIdx].value
                                    -- Snap enemy tier and velocity
                                    for i, t in ipairs(ENEMY_SPEED_TIERS) do
                                        if t.value == enemy.targetSpeed then
                                            enemy.speedTier = t
                                            enemy.vx = (enemy.vx > 0 and 1 or -1) * t.value
                                        end
                                    end
                                    -- Snap player tier and velocity
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
                                    -- End attack instantly and flash at contact point (center of attack area)
                                    atk.active = false
                                    atk.timer = 0
                                    player.hitFlash.active = true
                                    player.hitFlash.x = worldAx
                                    player.hitFlash.y = worldAy
                                    player.hitFlash.timer = 0.15
                                    player.altAttack.charge = 0
                                    player.altAttack.chargeLevel = 1
                                    -- Removed punch/knockback/velocity boost
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Calculate angle based on velocity (so triangle points in movement direction)
    if math.abs(player.vx) > 1 or math.abs(player.vy) > 1 then
        player.angle = math.atan2(player.vy, player.vx) + math.pi/2
    end
    if not player.attack.active then player.lastAttackTier = nil end
    if not player.altAttack.active then player.lastAltAttackTier = nil end
    -- Update hitFlash timer
    if player.hitFlash.active then
        player.hitFlash.timer = player.hitFlash.timer - dt
        if player.hitFlash.timer <= 0 then
            player.hitFlash.active = false
        end
    end

    -- Player-enemy collision: enemy has priority, push player out
    local px, py, ps = player.x, player.y, player.size
    for i, enemy in ipairs(enemies) do
        local ex, ey, es = enemy.x, enemy.y, enemy.size
        local playerRadius = ps * 0.45
        local playerCenterX = px + ps/2
        local playerCenterY = py + ps/2
        if circleRectOverlap(playerCenterX, playerCenterY, playerRadius, ex, ey, es, es) then
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
end

function love.keypressed(key)
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
            -- Normal/slowed: cannot charge, only tap (no charge bar)
            player.altAttack.maxAllowedCharge = 1
            player.altAttack.charging = true -- allow key-up to trigger
            player.altAttack.charge = 0
        end
    end
end

function love.keyreleased(key)
    if key == 'z' and player.altAttack.charging and not player.altAttack.active and player.altAttack.cooldownTimer == 0 then
        player.altAttack.charging = false
        -- Calculate charge level (1 tier per 0.7s, up to max allowed by tier)
        local maxCharge = player.altAttack.maxAllowedCharge or 1
        local tierName = player.speedTier and player.speedTier.name or 'normal'
        local chargeLevel
        if tierName == 'superfast' or tierName == 'fast' then
            chargeLevel = math.min(maxCharge, math.max(1, math.floor(player.altAttack.charge / 0.7) + 1))
        else
            chargeLevel = 1 -- always 1 for normal/slowed
        end
        player.altAttack.chargeLevel = chargeLevel
        player.altAttack.active = true
        player.altAttack.timer = player.altAttack.duration
    end
end

function love.draw()
    -- Set solid background color
    love.graphics.clear(0.09, 0.09, 0.13, 1) -- deep blue-grey
    -- Draw tilemap walls
    for y = 1, map.height do
        for x = 1, map.width do
            if tilemap[y][x] == 1 then
                love.graphics.setColor(0.12, 0.12, 0.14, 1)
                love.graphics.rectangle('fill', (x-1)*map.tileSize, (y-1)*map.tileSize, map.tileSize, map.tileSize)
                love.graphics.setColor(0.3, 0.3, 0.35, 1)
                love.graphics.rectangle('line', (x-1)*map.tileSize, (y-1)*map.tileSize, map.tileSize, map.tileSize)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    -- Draw player as a rounded arrowhead (Google Maps puck style) with colored outline
    love.graphics.setColor(player.speedTier and player.speedTier.color or {1,1,1})
    local px, py, ps = player.x, player.y, player.size
    local cx, cy = px + ps / 2, py + ps / 2
    local angle = player.angle or 0
    -- Arrowhead shape: tip, rounded base left, rounded base right, and a control point for the curve
    local tip = {0, -ps/2}
    local left = {-ps/2.2, ps/3}
    local right = {ps/2.2, ps/3}
    local base = {0, ps/2.1}
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(angle)
    love.graphics.setLineWidth(6)
    love.graphics.polygon('line', tip[1], tip[2], right[1], right[2], base[1], base[2], left[1], left[2])
    -- Red-pink fill
    love.graphics.setColor(1, 0.2, 0.5)
    love.graphics.polygon('fill', tip[1], tip[2], right[1], right[2], base[1], base[2], left[1], left[2])
    -- Draw rounded base (arc)
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
                -- White, sharp-edged rectangle with glow
                love.graphics.setColor(1, 1, 1, 0.3)
                for i = 1, 3 do
                    love.graphics.rectangle('fill', -attackWidth/2 - i, -ps/2 - attackLength - i, attackWidth + 2*i, attackLength + 2*i)
                end
                love.graphics.setColor(1, 1, 1)
                love.graphics.rectangle('fill', -attackWidth/2, -ps/2 - attackLength, attackWidth, attackLength)
            else
                -- Orange, rounded rectangle with pulsing effect
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
    -- Draw enemies as diamonds with colored outlines based on speed tier
    for i, enemy in ipairs(enemies) do
        love.graphics.setColor(enemy.speedTier and enemy.speedTier.color or {1,1,1})
        local half = enemy.size / 2
        love.graphics.setLineWidth(6)
        love.graphics.polygon('line',
            enemy.x + half, enemy.y, -- top
            enemy.x + enemy.size, enemy.y + half, -- right
            enemy.x + half, enemy.y + enemy.size, -- bottom
            enemy.x, enemy.y + half -- left
        )
        love.graphics.setColor(0, 0.7, 1)
        love.graphics.polygon('fill',
            enemy.x + half, enemy.y, -- top
            enemy.x + enemy.size, enemy.y + half, -- right
            enemy.x + half, enemy.y + enemy.size, -- bottom
            enemy.x, enemy.y + half -- left
        )
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
    end
    -- Draw hit flash if active
    if player.hitFlash.active then
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.circle('fill', player.hitFlash.x, player.hitFlash.y, 24 * player.hitFlash.timer / 0.15)
        love.graphics.setColor(1, 1, 1)
    end
    -- UI: Draw speed tier meter (UI), charge bar, cooldowns, debug info LAST
    local meterX, meterY = 32, 24
    local pipSize = 22
    local pipSpacing = 32
    love.graphics.setFont(love.graphics.newFont(16))
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("SPEED", meterX, meterY - 22)
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
    -- Debugging output
    love.graphics.setColor(1, 1, 1, 0.8)
    local debugY = 8
    love.graphics.print(string.format("Player: tier=%s, speed=%.1f, vx=%.1f, vy=%.1f, target=%.1f",
        player.speedTier and player.speedTier.name or '?', player.speed or 0, player.vx or 0, player.vy or 0, player.targetSpeed or 0), 8, debugY)
    debugY = debugY + 18
    for i, enemy in ipairs(enemies) do
        love.graphics.print(string.format("Enemy %d: tier=%s, speed=%.1f, vx=%.1f, vy=%.1f, target=%.1f",
            i,
            enemy.speedTier and enemy.speedTier.name or '?',
            math.abs(enemy.vx or 0), enemy.vx or 0, enemy.vy or 0, enemy.targetSpeed or 0),
            8, debugY)
        debugY = debugY + 18
    end
    love.graphics.setColor(1, 1, 1, 1)
end 
local config = require 'config'
local utils = require 'utils'

local enemy = {}

enemy.enemies = {}

enemy._spawner = {
	enabled = false,
	timer = 0,
	nextInterval = 0
}

function enemy.initAll(map, player)
    local enemyStartTier = config.ENEMY_SPEED_TIERS[2] 
    enemy.enemies = {
        {
            x = 2 * config.TILE_SIZE, y = 2 * config.TILE_SIZE,
            type = 'bouncer',
            size = config.PLAYER_SIZE,
            vx = enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            player = player,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        },
        {
            x = 25 * config.TILE_SIZE, y = 15 * config.TILE_SIZE,
            type = 'bouncer',
            size = config.PLAYER_SIZE,
            vx = -enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            player = player,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        },
        {
            x = 15 * config.TILE_SIZE, y = 10 * config.TILE_SIZE,
            type = 'follower',
            size = config.PLAYER_SIZE,
            vx = enemyStartTier.value,
            vy = 0,
            minX = 2 * config.TILE_SIZE,
            maxX = 27 * config.TILE_SIZE,
            speed = enemyStartTier.value,
            player = player,
            targetSpeed = enemyStartTier.value,
            speedTier = enemyStartTier,
            knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
            defeated = false, defeatEffectTimer = 0
        }
    }

	-- init spawning director
	local spawnCfg = config.SPAWN or {}
	enemy._spawner.enabled = spawnCfg.enabled ~= false
	enemy._spawner.timer = -(spawnCfg.initialDelay or 0)
	enemy._spawner.nextInterval = spawnCfg.interval or 3
end

function enemy.moveFollower(dt, map, tilemap, e)
    -- follower enemy movement
    local deltaX = e.player.x - e.x
    local deltaY = e.player.y - e.y
    local distanceToPlayer = math.sqrt(deltaX * deltaX + deltaY * deltaY)

    if distanceToPlayer > 1 then
        -- Normalise direction
        local dirX = deltaX / distanceToPlayer
        local dirY = deltaY / distanceToPlayer

        local speed = e.speed or 100
        e.vx = dirX * speed
        e.vy = dirY * speed

        e.x = e.x + e.vx * dt
        e.y = e.y + e.vy * dt
    else
        --at target
        e.vx, e.vy = 0, 0
    end
end


function enemy.moveBouncer(dt, map, tilemap, e)
    -- Bouncer enemy movement
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

function enemy.updateKnockback(e, dt, map, tilemap)
    -- Knocked Back Enemy Movement
    local nextX = e.x + e.knockbackVx * dt
    local nextY = e.y + e.knockbackVy * dt
    local enemySize = e.size
    local hitWall = false

    for _, corner in ipairs({
        {nextX, nextY},
        {nextX + enemySize - 1, nextY},
        {nextX, nextY + enemySize - 1},
        {nextX + enemySize - 1, nextY + enemySize - 1}
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
        return
    end

    -- Defeat by hitting another enemy in knockback state
    for j, other in ipairs(enemy.enemies) do
        if other ~= e and not other.defeated then
            local overlap = not (nextX + enemySize < other.x or nextX > other.x + other.size or nextY + enemySize < other.y or nextY > other.y + other.size)
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
        local dir = (e.knockbackVx >= 0) and 1 or -1
        e.knockbackVx = 0
        e.knockbackVy = 0
        e.knockbackTimer = 0
        e.vx = 0
        e.vy = 0
        e.recoveryTimer = 0.15
        e._recoveryElapsed = 0
        e._recoveryTargetVx = dir * (e.speedTier and e.speedTier.value or 120)
    end
end

function enemy.updateRecovery(e, dt)
     -- Enemy attack recovery window
    local recoveryTotalDuration = 0.15
    local elapsedTime = (e._recoveryElapsed or 0) + dt
    e._recoveryElapsed = elapsedTime
    local progress = math.min(1, elapsedTime / recoveryTotalDuration)
    e.vx = (e._recoveryTargetVx or 0) * progress
    e.vy = 0
    e.recoveryTimer = e.recoveryTimer - dt

    if e.recoveryTimer <= 0 then
        e.vx = e._recoveryTargetVx or 0
        e.vy = 0
        e._recoveryElapsed = nil
        e._recoveryTargetVx = nil
    end
end

function enemy.updateAll(dt, map, tilemap)
    for i, e in ipairs(enemy.enemies) do

        if e.defeated then goto continue_enemy end
        
        if e.knockbackTimer and e.knockbackTimer > 0 then
            enemy.updateKnockback(e, dt, map, tilemap)
        elseif e.recoveryTimer and e.recoveryTimer > 0 then
            enemy.updateRecovery(e, dt)
        else
            if e.type == 'bouncer' then
                -- Normal enemy movement
                enemy.moveBouncer(dt, map, tilemap, e)
            else
                enemy.moveFollower(dt, map, tilemap, e)
            end
        end
        ::continue_enemy::
    end
    for _, e in ipairs(enemy.enemies) do
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            e.defeatEffectTimer = e.defeatEffectTimer - dt
        end
    end

	-- Spawning director
	local spawnCfg = config.SPAWN or {}
	if enemy._spawner.enabled and spawnCfg.enabled ~= false then
		enemy._spawner.timer = enemy._spawner.timer + dt
		if enemy._spawner.timer >= enemy._spawner.nextInterval then
			enemy._spawner.timer = 0

            -- update next interval based on decay rate for scaling difficulty
			enemy._spawner.nextInterval = math.max((enemy._spawner.nextInterval or (spawnCfg.interval or 3)) * (1 - (spawnCfg.intervalDecay or 0)), spawnCfg.intervalMin or 1)

			enemy.trySpawn(map, tilemap)
		end
	end
end

function enemy.drawAll()
    for i, e in ipairs(enemy.enemies) do
        if e.defeated then goto continue_draw_enemy end

        love.graphics.setColor(e.speedTier and e.speedTier.color or {1,1,1})
        local halfSize = e.size / 2
        love.graphics.setLineWidth(6)
        love.graphics.polygon('line',
            e.x + halfSize, e.y, 
            e.x + e.size, e.y + halfSize, 
            e.x + halfSize, e.y + e.size, 
            e.x, e.y + halfSize 
        )
        local tierColor = e.speedTier and e.speedTier.color or {1,1,1}
        love.graphics.setColor(tierColor[1], tierColor[2], tierColor[3])
        love.graphics.polygon('fill',
            e.x + halfSize, e.y,
            e.x + e.size, e.y + halfSize,
            e.x + halfSize, e.y + e.size, 
            e.x, e.y + halfSize 
        )
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        ::continue_draw_enemy::
    end
    for _, e in ipairs(enemy.enemies) do
        -- Enemy death VFX
        if e.defeatEffectTimer and e.defeatEffectTimer > 0 then
            local halfSize = e.size / 2
            local centerX = e.x + halfSize
            local centerY = e.y + halfSize
            local duration = config.ENEMY_DEFEAT_EFFECT_DURATION
            local progress = 1 - (e.defeatEffectTimer / duration)
            local radius = halfSize + progress * config.ENEMY_DEFEAT_VFX_EXPAND + config.ENEMY_DEFEAT_VFX_OSC * math.sin(progress * math.pi)
            if progress < config.ENEMY_DEFEAT_FLASH_THRESHOLD then
                love.graphics.setColor(1, 1, 1, 0.85 * (1-progress/config.ENEMY_DEFEAT_FLASH_THRESHOLD))
                love.graphics.circle('fill', centerX, centerY, radius * 0.7)
            end
            love.graphics.setColor(1, 0.2, 0.2, 0.8 * (1-t))
            love.graphics.circle('fill', centerX, centerY, radius)
            love.graphics.setColor(1, 1, 1, 0.7 * (1-t))
            love.graphics.circle('line', centerX, centerY, radius + 4)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

function enemy.getAll()
    return enemy.enemies
end

-- Helper spawn functions
local function isTileBlocked(tilemap, map, tileX, tileY)
	if tileX < 1 or tileX > map.width or tileY < 1 or tileY > map.height then return true end
	return tilemap[tileY] and tilemap[tileY][tileX] == 1
end

local function isAreaFree(tilemap, map, x, y, size)
	local corners = {
		{x, y},
		{x + size - 1, y},
		{x, y + size - 1},
		{x + size - 1, y + size - 1}
	}
	for _, c in ipairs(corners) do
		local tx = math.floor(c[1] / map.tileSize) + 1
		local ty = math.floor(c[2] / map.tileSize) + 1
		if isTileBlocked(tilemap, map, tx, ty) then return false end
	end
	return true
end

function enemy.trySpawn(map, tilemap)
	local spawnCfg = config.SPAWN or {}
	local maxEnemies = spawnCfg.maxEnemies or 12

	-- clean up defeated enemies before counting
	local aliveCount = 0
	for _, e in ipairs(enemy.enemies) do
		if not e.defeated then aliveCount = aliveCount + 1 end
	end
	if aliveCount >= maxEnemies then return end

	local playerRef = enemy.enemies[1] and enemy.enemies[1].player
	if not playerRef then return end

	local size = config.PLAYER_SIZE
	local safeR = spawnCfg.safeRadius or 120

	local candidates = {}
	if spawnCfg.edgeSpawn then
		-- get positions along edges for spawning foes
		local pxCount = 10
		for i=0,pxCount do
			local fx = i/(pxCount)
			local x1 = 1 * map.tileSize
			local x2 = (map.width-2) * map.tileSize - size
			local yTop = 1 * map.tileSize
			local yBot = (map.height-2) * map.tileSize - size
			table.insert(candidates, {x1 + fx*(x2 - x1), yTop})
			table.insert(candidates, {x1 + fx*(x2 - x1), yBot})
		end
		for i=0,pxCount do
			local fy = i/(pxCount)
			local y1 = 1 * map.tileSize
			local y2 = (map.height-2) * map.tileSize - size
			local xL = 1 * map.tileSize
			local xR = (map.width-2) * map.tileSize - size
			table.insert(candidates, {xL, y1 + fy*(y2 - y1)})
			table.insert(candidates, {xR, y1 + fy*(y2 - y1)})
		end
	else
		-- random candidate locations
		for i=1,24 do
			local x = math.random(1 * map.tileSize, (map.width-2) * map.tileSize - size)
			local y = math.random(1 * map.tileSize, (map.height-2) * map.tileSize - size)
			table.insert(candidates, {x, y})
		end
	end

	local px = playerRef.x + size/2
	local py = playerRef.y + size/2

	for _, pos in ipairs(candidates) do
		local x, y = pos[1], pos[2]
		local candidateCenterX = x + size/2
		local candidateCenterY = y + size/2
		local deltaX = candidateCenterX - px
		local deltaY = candidateCenterY - py
		local distanceSquared = deltaX*deltaX + deltaY*deltaY
		if distanceSquared >= safeR*safeR and isAreaFree(tilemap, map, x, y, size) then
			enemy.spawnOne(x, y, playerRef)
			return
		end
	end
end

function enemy.spawnOne(x, y, player)
	local tier = config.ENEMY_SPEED_TIERS[2]
	local newEnemy = {
		x = x, y = y,
		type = (math.random() < 0.5) and 'bouncer' or 'follower',
		size = config.PLAYER_SIZE,
		vx = 0,
		vy = 0,
		minX = 2 * config.TILE_SIZE,
		maxX = 27 * config.TILE_SIZE,
		speed = tier.value,
		player = player,
		targetSpeed = tier.value,
		speedTier = tier,
		knockbackTimer = 0, knockbackVx = 0, knockbackVy = 0, recoveryTimer = 0,
		defeated = false, defeatEffectTimer = 0
	}
	-- initial direction
	if newEnemy.type == 'bouncer' then
		newEnemy.vx = (math.random() < 0.5) and tier.value or -tier.value
	end
	table.insert(enemy.enemies, newEnemy)
end

return enemy

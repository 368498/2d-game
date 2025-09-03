-- main.lua
local player = require 'player'
local enemy = require 'enemy'
local ui = require 'ui'
local config = require 'config'
local map = require 'map'
local utils = require 'utils'

-- helper functions
local function getCurrentTierIndex()
    for i, tier in ipairs(config.SPEED_TIERS) do
        if player.speedTier and player.speedTier.name == tier.name then
            return i
        end
    end
    return 1
end

local function handlePlayerEnemyCollision()
    local px, py, ps = player.x, player.y, player.size
    for i, e in ipairs(enemy.getAll()) do
        local ex, ey, es = e.x, e.y, e.size
        local playerRadius = ps * 0.45
        local playerCenterX = px + ps/2
        local playerCenterY = py + ps/2
        if utils.circleRectOverlap(playerCenterX, playerCenterY, playerRadius, ex, ey, es, es) then
            -- Find minimal push direction
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
            
            -- zero out velocity in push direction        
            if minOverlap == overlapLeft or minOverlap == overlapRight then
                player.vx = 0
            else
                player.vy = 0
            end

            -- Apply damage if not iframes
            if (player.invulnTimer or 0) <= 0 then
                if player.takeDamage then player.takeDamage(1) end
            end
        end
    end
end

local function updateAltAttack(dt)
    if player.altAttack.charging then
        player.altAttack.charge = math.min(player.altAttack.charge + dt, player.altAttack.maxCharge)
    end
end

local function updateSelfCharge(dt)
    local isTakeHeld = love.keyboard.isDown('space')
    local isMoving = math.abs(player.vx) > 0.1 or math.abs(player.vy) > 0.1
    local maxTier = #config.SPEED_TIERS
    local currentTierIdx = getCurrentTierIndex()
    local chargeDuration = config.CHARGE_DURATIONS[currentTierIdx] or 1.0
    
    if isTakeHeld and not isMoving and player.selfChargeCooldown <= 0 and player.selfChargeReady and currentTierIdx < maxTier and not player.attack.active and player.attack.cooldownTimer == 0 then
        if not player.selfChargeActive then
            player.selfChargeActive = true
            player.selfChargeTimer = 0
        end
        player.selfChargeTimer = player.selfChargeTimer + dt
        if player.selfChargeTimer >= chargeDuration then
            local nextTier = config.SPEED_TIERS[currentTierIdx + 1]
            player.targetSpeed = nextTier.value
            player.selfChargeActive = false
            player.selfChargeTimer = 0
            player.selfChargeCooldown = 0.2 -- short cooldown to prevent double-trigger
            player.selfChargeReady = false 
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

local function drawTilemap()
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
end

local function drawHitFlash()
    if player.hitFlash.active then
        love.graphics.setColor(1, 1, 0, 0.7)
        love.graphics.circle('fill', player.hitFlash.x, player.hitFlash.y, 24 * player.hitFlash.timer / 0.15)
        love.graphics.setColor(1, 1, 1)
    end
end


local function drawSelfChargeVFX()
    local maxTier = #config.SPEED_TIERS
    local currentTierIdx = getCurrentTierIndex()
    local chargeDuration = config.CHARGE_DURATIONS[currentTierIdx] or 1.0
    
    if player.selfChargeActive and currentTierIdx < maxTier then
        local px, py, ps = player.x, player.y, player.size
        local cx, cy = px + ps / 2, py + ps / 2
        local pct = player.selfChargeTimer / (chargeDuration or 1.0)
        if pct > 1 then pct = 1 end
        local startRadius = ps * 13.2
        local endRadius = ps * 0.2
        local startOpacity = 0
        local endOpacity = 0.8
        local radius = startRadius - (startRadius - endRadius) * pct
        local opacity = startOpacity + (endOpacity + startOpacity) * pct
        if radius < endRadius then radius = endRadius end
        love.graphics.setColor(1, 1, 1, opacity)
        love.graphics.setLineWidth(2)
        love.graphics.circle('line', cx, cy, radius)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- Controls hint init
local controlsHintTimer = 0
local controlsHintText = nil
local controlsHintFont = nil

function love.load()
    math.randomseed(os.time())
    player.load()
    map.init(30, 22, config.TILE_SIZE)
    enemy.initAll(map, player)
    -- controls hint setup
    controlsHintTimer = 10
    controlsHintText = "Move: WASD  |  Aim: Arrows or Mouse  |  Take: Space or Left Click  |  Give: Z or Right Click"
    controlsHintFont = love.graphics.newFont(16)
end

function love.update(dt)
    enemy.updateAll(dt, map, map.getTilemap())
    player.update(dt, map, map.getTilemap(), enemy.getAll())

    handlePlayerEnemyCollision()
    updateAltAttack(dt)
    updateSelfCharge(dt)
    -- Controls hint time
    if controlsHintTimer and controlsHintTimer > 0 then
        controlsHintTimer = controlsHintTimer - dt
        if controlsHintTimer < 0 then controlsHintTimer = 0 end
    end

    -- #TODO Game Over
    if player.isDead and player.isDead() then
        player.load()
        enemy.initAll(map, player)
    end
end

function love.keypressed(key)
    player.keypressed(key)
end

function love.keyreleased(key)
    player.keyreleased(key)
end

function love.mousepressed(x, y, button, istouch, presses)
    player.mousepressed(x, y, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
    player.mousereleased(x, y, button, istouch, presses)
end

function love.draw()
    -- background color
    love.graphics.clear(0.09, 0.09, 0.13, 1) 

    drawTilemap()
    love.graphics.setColor(1, 1, 1, 1)
    player.draw()
    enemy.drawAll()
    drawHitFlash()
    drawSelfChargeVFX()
    ui.draw(player, enemy)
    -- Draw controls hint overlay last
    if controlsHintTimer and controlsHintTimer > 0 and controlsHintText then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local prevFont = love.graphics.getFont()
        if controlsHintFont then love.graphics.setFont(controlsHintFont) end
        local text = controlsHintText
        local tw = love.graphics.getFont():getWidth(text)
        local th = love.graphics.getFont():getHeight()
        local x = (w - tw) / 2
        local y = 42
        --shadow
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.print(text, x + 2, y + 2)
        -- text
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x, y)
        if prevFont then love.graphics.setFont(prevFont) end
    end
end
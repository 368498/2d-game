local config = require 'config'

local map = {}

local tilemap = {}
map.tilemap = tilemap
map.width = 0
map.height = 0
map.tileSize = config.TILE_SIZE

function map.init(width, height, tileSize)
    map.width = width
    map.height = height
    map.tileSize = tileSize or config.TILE_SIZE
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
    map.tilemap = tilemap
end

function map.isWallAt(px, py)
    local tileX = math.floor(px / map.tileSize) + 1
    local tileY = math.floor(py / map.tileSize) + 1
    if tileX < 1 or tileX > map.width or tileY < 1 or tileY > map.height then
        return true
    end
    return tilemap[tileY] and tilemap[tileY][tileX] == 1
end

function map.getTilemap()
    return tilemap
end

return map 
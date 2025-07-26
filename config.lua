local config = {}

config.SPEED_TIERS = {
    {name = 'slowed', value = 130, color = {0.5, 0.5, 1}, accel = 1200, friction = 1100, punch = 1},
    {name = 'normal', value = 240, color = {1, 1, 1}, accel = 1200, friction = 900, punch = 1.5},
    {name = 'fast', value = 360, color = {1, 0.8, 0.2}, accel = 900, friction = 600, punch = 2.2},
    {name = 'superfast', value = 600, color = {1, 0.2, 0.2}, accel = 800, friction = 400, punch = 3.2}
}

config.ENEMY_SPEED_TIERS = {
    {name = 'slowed', value = 60, color = {0.5, 1, 0.5}},
    {name = 'normal', value = 120, color = {1, 1, 1}},
    {name = 'fast', value = 200, color = {0.2, 0.8, 1}},
    {name = 'superfast', value = 320, color = {1, 0.2, 1}}
}

-- Charge durations for player
config.CHARGE_DURATIONS = {1.2, 2.0, 3.0, 4.0} -- slowed, normal, fast, superfast (slower charge at higher tier)

-- Map/Tile
config.TILE_SIZE = 32

-- player
config.PLAYER_SIZE = 32
config.PLAYER_SPEED_RAMP = 200
config.PLAYER_ACCEL = 300
config.PLAYER_FRICTION = 260

-- Player Attacks
config.ATTACK_DURATION = 0.15
config.ATTACK_COOLDOWN = 0.4
config.ALT_ATTACK_DURATION = 0.15
config.ALT_ATTACK_COOLDOWN = 0.4
config.ALT_ATTACK_MAX_CHARGE = 2.0
config.CHARGE_PER_TIER = 0.7

-- Enemies
config.ENEMY_DEFEAT_EFFECT_DURATION = 0.28
config.ENEMY_RECOVERY_DURATION = 0.15
config.ENEMY_KNOCKBACK_BASE = 220
config.ENEMY_KNOCKBACK_DURATION_BASE = 0.18
config.ENEMY_KNOCKBACK_DURATION_PER_TIER = 0.08
config.ENEMY_DEFEAT_VFX_EXPAND = 64
config.ENEMY_DEFEAT_VFX_OSC = 16
config.ENEMY_DEFEAT_FLASH_THRESHOLD = 0.12

-- Player
config.PLAYER_HIT_FLASH_RADIUS = 24
config.PLAYER_HIT_FLASH_DURATION = 0.15

-- UI Elements
config.UI_METER_X = 32
config.UI_METER_Y = 24
config.UI_PIP_SIZE = 22
config.UI_PIP_SPACING = 32
config.UI_FONT_SIZE = 16
config.UI_DEBUG_Y_START = 8
config.UI_DEBUG_Y_STEP = 18

return config 
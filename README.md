# My 2D Roguelike (LÖVE)

A simple top-down adventure game scaffold using [LÖVE (Love2D)](https://love2d.org/).

## Getting Started

1. **Install LÖVE:**
   - Download from [https://love2d.org/](https://love2d.org/)

2. **Run the Game:**
   - Drag the project folder onto `love.exe` (Windows), or
   - Run from command line:
     ```
     love .
     ```

## Project Structure

- `main.lua` — Main game logic (player, map, input)
- `conf.lua` — Window configuration
- `assets/` — (Create this folder for images, sounds, etc.)

## Next Steps
- Add sprites and sounds to the `assets/` folder
- Expand the map and player logic
- Implement enemies, items, and more! 

## Enemy Spawning

Enemy spawning is configurable in `config.lua` under `SPAWN`:

- `enabled` (bool): Toggle spawning on/off.
- `initialDelay` (seconds): Delay before the first spawn.
- `interval` (seconds): Base time between spawns.
- `intervalMin` (seconds): Lower bound for the spawn interval.
- `intervalDecay` (0..1): Each spawn reduces the next interval by this fraction.
- `maxEnemies` (int): Maximum concurrent alive enemies.
- `safeRadius` (pixels): Minimum distance from the player when spawning.
- `edgeSpawn` (bool): If true, spawns at arena edges; otherwise anywhere safe.

Spawns pick either a `bouncer` or `follower` and avoid walls/blocked tiles. You can tune difficulty by adjusting `interval`, `intervalDecay`, and `maxEnemies`.
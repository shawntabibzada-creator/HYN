# Code Duel

A free-for-all Roblox game. Every round, all players get a random 4-digit
code floating above their head and are dropped into a freshly, randomly
generated arena. Read other players' codes, then type them into your guess
box to eliminate them. Guess wrong — no one alive has that code — and *you*
die instead. Everyone also has a flashbang, usable once every 6 seconds, to
blind nearby enemies. Last player alive wins the round.

## How it works

- **Codes**: each player is assigned a unique random `0000`-`9999` code at
  the start of every round, shown in a billboard above their head
  (`src/ServerScriptService/GameServer.server.lua`).
- **Guessing**: type a 4-digit code and submit. If it matches a living
  player, they're eliminated and you get credit for the kill. If it matches
  no one, you're eliminated instead.
- **Flashbang**: press `F` or tap the on-screen button. Every player within
  40 studs (other than you) gets their screen flashed white for ~2.2
  seconds. 6-second cooldown per player, shown on the button.
- **Map**: procedurally regenerated every round — bounded arena, boundary
  walls, and a random scatter of cover blocks — via
  `src/ReplicatedStorage/Modules/MapGenerator.lua`.
- **Rounds**: a 15-second intermission, then the round runs until one
  player is left standing (needs 2+ players to start). Wins/Kills are
  tracked in leaderstats.

## Project layout (Rojo)

```
default.project.json
src/
  ReplicatedStorage/
    Modules/
      CodeUtils.lua       -- code generation/validation
      MapGenerator.lua     -- random arena generation
  ServerScriptService/
    GameServer.server.lua  -- round loop, elimination, flashbang logic
  StarterPlayer/
    StarterPlayerScripts/
      ClientMain.client.lua -- guess box, flashbang UI, banners, flash overlay
```

RemoteEvents (`SubmitCodeGuess`, `ThrowFlashbang`, `FlashbangEffect`,
`FlashbangCooldown`, `PlayerEliminated`, `RoundStatus`) are declared
directly in `default.project.json` under `ReplicatedStorage/Remotes`.

## Running it in Roblox Studio

This repo uses [Rojo](https://rojo.space/) to sync plain Lua files into
Studio.

1. Install the Rojo Studio plugin (from the Roblox plugin marketplace) and
   the Rojo CLI (`cargo install rojo`, or via [aftman](https://github.com/LPGhatguy/aftman)/[rokit](https://github.com/rojo-rbx/rokit)).
2. From the repo root, run:
   ```
   rojo serve
   ```
3. In Roblox Studio, open the Rojo plugin panel and click **Connect**.
4. Press **Play** (or **Play Here**) to test. Open a second local server
   (Test > Start Server and 2 Players, or a two-account local test) since
   the game needs at least 2 players to start a round.

## Tuning

All key numbers live at the top of `GameServer.server.lua`:
`MIN_PLAYERS`, `INTERMISSION_TIME`, `FLASHBANG_COOLDOWN`,
`FLASHBANG_RADIUS`, `FLASHBANG_DURATION`. Arena size and obstacle count are
at the top of `MapGenerator.lua`.

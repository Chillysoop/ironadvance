# Iron Advance

Turn-based run-and-gun squad game built in Godot 4.3: aim every shot, lob grenades, topple towers onto the Jackals.
Each soldier carries a deck through a 3-mission campaign. Mid-mission level-ups offer a pick of 1 of 3
(new card, stat boost or ability) and the Quartermaster sells cards, gear and services between missions.

## Play (auto-updating)
Download the launcher once from the [launcher release](../../releases/tag/launcher):
Windows `IronAdvance-Windows.zip`, macOS `IronAdvance-Mac.zip`, Linux `IronAdvance-Linux.zip`.

Every time it starts, the launcher:
1. reads `latest.json` from the newest release,
2. downloads that build's game pack (under 1 MB) if it is new and checks its SHA-256,
3. deletes every older build and any half-finished download,
4. starts the game. With no connection it plays the last build it downloaded.

Builds are stored in the launcher's user data folder (`%APPDATA%\Godot\app_userdata\Iron Advance Launcher\builds` on Windows,
`~/Library/Application Support/Godot/app_userdata/Iron Advance Launcher/builds` on macOS,
`~/.local/share/godot/app_userdata/Iron Advance Launcher/builds` on Linux). The build number shows on the title screen.

The launcher is unsigned: on Windows choose More info → Run anyway; on macOS right-click the app → Open the first time.

## How releases work
- Pushing to `main` with changes under `game/` runs **Release game build**: it exports `IronAdvance-1.0.<run>.pck`
  and a `latest.json` manifest and publishes them as release `v1.0.<run>`. Players get it on next launch.
- Changes under `launcher/` run **Release launcher**, which rebuilds the three launcher apps on the `launcher` release.
  The launcher is the Godot runtime plus a tiny updater, so it only needs replacing when Godot itself is upgraded.
  If a build needs a newer engine than the player's launcher, the launcher says so and links to the new one.

## Layout
- `game/` the Godot project. `scripts/battle.gd` is the simulation, `terrain.gd` the destructible grid,
  `world_view.gd` the world and in-world plates, `backdrop.gd` the animated parallax sky,
  `decor.gd` ground life (grass, set dressing, critters, cosmetic idle gunfire), `foreground.gd` close silhouettes and ambient particles, `hud.gd` the HUD, `shop.gd` the Quartermaster,
  `run.gd` campaign state (decks, XP, perks, gear, scrip), `data.gd` all cards, perks, gear, enemies and missions.
  Missions are strings of level segments in `data.gd` (`SEGMENTS`): ridges, trenches and cliffs, multi-floor forts,
  collapsing bridges, piers, cranes, minefields, steel-grating catwalks and chain-link fences (bullets and grenades pass through both). `terrain.gd` builds them.
- `game/tools/gen_art.py`, `gen_sfx.py` regenerate every sprite and sound (Python 3 + Pillow; gen_art.py also needs NumPy).
- `game/tools/test_runner.gd` scripted tests and an autoplayer:
  `godot --path game -- --iatest --scenario=flow --out=/tmp/shots` (title, start, aim, arc, topple, level, shop, flow, bot, campaign, alive).
  `--scenario=levels` photographs every screen of each mission and walks a soldier through to list blocked spots;
  `--scenario=hazards` sets off each set piece and prints PASS/FAIL; `--scenario=soldat` checks the Soldat borrowings (grating, fences, bodies, recoil, bonus pads, Jet Boots); `--scenario=bot --mission=N` autoplays mission N.
- `launcher/` the updater. Point it at another host with `--manifest=URL` or a `launcher.cfg` next to the executable
  (`[update]` / `manifest="..."`); `--offline` skips the check.

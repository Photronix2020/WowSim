# WowSim — run a WoW addon on Windows

WowSim runs an addon's Lua code in a real **Lua 5.1** interpreter (the same Lua version WoW uses) with a fake WoW API. It draws the addon's frames in a browser page, so you can see the addon, click it and tweak it without starting the game. It never touches the game, the AddOns folder or your WTF files.

## Start it

Double-click **`WowSim.bat`**. It opens <http://localhost:8642/>. Closing the console window stops WowSim.

Or run `python server.py --addon ..\ForeCast\ForeCast` with the miniconda Python (it has `lupa`).

On another machine: `pip install -r requirements.txt` (lupa ships a real Lua 5.1 build; Pillow measures text and decodes .tga/.blp). WowSim looks for addons in the folder above it (`<Addon>\<Addon>\<Addon>.toc` layout) and in the WoW Forever AddOns folder (read-only). The API docs and Blizzard helper code come from a clone of [wow-ui-source-forever](https://github.com/Ketho/wow-ui-source-forever) at `..\API`; without it WowSim still runs, with fewer stubs.

## What you can do

- **Addons tab**: tick one or more addons (your Addondev ones, or the installed ones, read-only) and press **Load**. From here you can also open their option panels and run their slash commands.
- **Game view**: click, drag, scroll, type into edit boxes, and hover for tooltips. Ctrl+wheel or the zoom box zooms in. Enter or `/` opens chat, where `/fc`, `/pack` and `/reload` all work.
- **Auto-reload**: save an addon file and WowSim reloads it within about a second. SavedVariables carry over, so you can edit with Claude and watch the result.
- **Player tab**: the fake character. Class, level, combat, health and power, the target, party size, zone and money all fire the real events (`PLAYER_REGEN_DISABLED`, `PLAYER_TARGET_CHANGED`, `UNIT_HEALTH`, …). **Use class preset** fills the spellbook. Spell names and icons come from Wowhead's classic data and are cached in `cache\spells.json`.
- **Events tab**: fire any of the 1,800+ documented events, with arguments. This tab also logs the addon messages the addon sends.
- **Console**: run Lua inside the addon's world, for example `ForeCastDB.hudScale` or `PackTrackFrame:GetPoint()`.
- **Errors**: Lua errors with stack traces, grouped by message.
- **Inspect**: like `/fstack`. Hover a frame to see its name, size, strata, level and anchors.
- **More**: view or reset the simulated SavedVariables (`saved\<Addon>.lua`). It also lists the "faked APIs the addon called", meaning functions that exist in the game but only return empty defaults here.

## How it works

| Piece | File |
|---|---|
| HTTP server, addon loader (TOC incl. `[AllowLoadGameType camelot]`), SavedVariables, file watcher | `server.py` |
| Frames, regions, anchors/layout, scripts, events, input, animations | `lua/widgets.lua` |
| Draw list sent to the browser | `lua/scene.lua` |
| Fake character, units, spells, chat, timers, sounds, colors | `lua/api.lua` |
| Blizzard templates, GameTooltip, StaticPopup, Settings window, UIDropDownMenu | `lua/templates.lua` |
| Stand-ins for Minimap, PlayerFrame, action bar, WorldMapFrame…; FrameXML helpers | `lua/blizzard.lua` |
| Reads `Addondev\API\…\Blizzard_APIDocumentationGenerated` → `Enum`, events, stubs for every documented function | `lua/docs.lua` |
| Renderer and control panel | `web/` |

It also loads some of Blizzard's own utility code from the API mirror, such as `SecondsFormatter`, the `Spell`/`Item` mixins and `TableUtil`. It only adds names that WowSim doesn't already define.

### Blizzard game data (`assets.py`)

On first use WowSim downloads game data for the exact Forever build and caches it in `cache\blizzard\`. None of it is part of this repo.

- **Global strings**: the client's ~27,000 `GlobalStrings` (`ITEM_LEVEL`, `ERR_NOT_IN_COMBAT`, …), from [wago.tools](https://wago.tools) DB2 exports.
- **Texture atlases**: `SetAtlas`, `GetAtlasInfo` and `useSize` return the real file, texture coordinates and size (~20,000 atlases).
- **Real UI art and fonts**: a texture path or file ID is mapped to its file with the [community listfile](https://github.com/wowdev/wow-listfile) (one-time ~150 MB download, reduced to a small index of interface and font files). The file is then fetched once from wago.tools and converted to PNG. Text uses the real Friz Quadrata and Arial Narrow, both for drawing and for measuring string widths.

The build is read from `..\API\version.txt` (default `1.60.1.70009`). Set `"blizzardData": false` in `config.json` to work offline. WowSim then falls back to the CSS look-alikes and Windows fonts. The idea of using exact-build DB2 data and real assets comes from [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim), a far larger Rust simulator that also supports WoW Forever.

## Limits

- **Templates still use look-alikes.** Textures and atlases addons set themselves use real Blizzard art (above). The templates WowSim builds (panel buttons, checkboxes, sliders, dialog frames, backdrop borders) are still drawn in CSS. Art that can't be found shows as a faint dashed outline (turn off with **Art outlines**).
- **Art comes from the current client.** Files are fetched by file ID, so the odd texture may look slightly different from Forever's.
- **The game world is not simulated.** There are no real combat, auras, cooldowns or quests unless you fire events yourself. Secret values from Forever's combat restrictions aren't modelled either.
- **XML frame definitions** (`<Frame>` in .xml) aren't built. `<Script>`/`<Include>` files are loaded, which is enough for libraries such as Ace3.
- Large third-party addons that hook deep into Blizzard frames may still error. Your own addons (ForeCast, PackTrack, VibeCraft, Wish Is My Command, QuiverShift, Smite Club) load cleanly.

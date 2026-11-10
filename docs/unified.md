# King Maker 2.0: one addon

Decided with the player 2026-11-10: the eleven King addons become **one addon, King Maker**, with one window (a
sidebar of pages in the Oracle style), one minimap button (the crown) and one settings page. Released publicly as
2.0 with an automatic move of every player's 1.x data. Oracle stays a separate private addon that adds its own pages
to the King Maker window when both are installed.

## 1. Layout

```
AddOns/King_Maker/                 the addon (folder = TOC name = "King_Maker")
  King_Maker.toc                   SavedVariables: KingMakerDB + every 1.x name (ScannerKingDB, EconKingDB, ...)
  Libs/                            LibStub, CallbackHandler, HereBeDragons (from Gather King)
  Textures/                        ring.tga (Gather pins)
  Core/Core.lua                    module system, KM.Print/Money/Now/Ago/Register/Safe, public KingMaker table
  Core/Theme.lua                   KM.UI: palette + widget kit (the only way modules draw)
  Core/Shell.lua                   the window, sidebar groups, pages, minimap crown, quick actions, status box
  Core/Settings.lua                the Settings page + Blizzard Options pointer
  Modules/<Name>/*.lua             one folder per 1.x addon: Scanner Econ Market Skillup Farm Gather Inventory Mail Quest Rested Minimap
  Core/Home.lua                    the Home page (tiles + quick actions + notes)
  Core/Boot.lua                    loads last: InitDB for every module, the 1.x data move, /km
  tests/                           mock.lua (workspace wow_mock), km.py (loader), core.py, <module>.py, run.py
AddOns/<1.x name>/                 stubs: <name>.toc (Dependencies: King_Maker, SavedVariables: <old var>,
                                   X-KingMaker-Stub: 1) + Stub.lua (a comment). They carry old data in, then can go.
```

## 2. The data move (Core/Boot.lua)

Each 1.x addon saved to `SavedVariables\<Folder>.lua`. King Maker saves every module's table under the **same
variable name** in `King_Maker.lua`. A stub declares the old variable and depends on King Maker, so the game loads
it right after King Maker and puts the old file's table in `_G`. Boot then copies it into the table the module
already holds (references stay valid), re-runs the module's `InitDB`, and records `KingMakerDB.moved[var]`. After
that the stub's copy is ignored. If the folder is the real 1.x addon (no `X-KingMaker-Stub`), nothing is touched
and the player is told to replace it. Saved-variable **shapes do not change**, so the King Dashboard's parsers keep
working; it only has to learn to read `King_Maker.lua` (and, while stubs remain, the old files carry the same data).

## 3. Module contract (every ported file)

1. **Header.** Replace `local addonName, ns = ...` / `local _, ns = ...` with
   ```lua
   local _, KM = ...
   local ns = KM.Module("Scanner")        -- Core.lua of the module passes info once:
   -- KM.Module("Scanner", { title = "Scanner King", short = "Scanner", legacy = "Scanner_King", db = "ScannerKingDB" })
   local addonName = "Scanner_King"        -- only if the file uses it (callback owners, sync, HBD refs)
   ```
   Every module keeps its own `ns`. Never put module state on `KM`.
2. **Saved variables.** The body of the old `ADDON_LOADED` (own name) handler becomes `function ns.InitDB()`:
   `XKingDB = XKingDB or {}`, `ns.db = XKingDB`, defaults, migrations. It **must be safe to run twice** (Boot runs
   it again after moving old data in) and must not keep sub-tables in upvalues except ones it re-sets itself. Drop
   the `ADDON_LOADED` registration for the module's own name; other `ADDON_LOADED` uses (Blizzard_AuctionHouseUI)
   stay. Saved-variable shapes stay as they are (King Dashboard reads them); dropping dead keys (`ui.button`,
   `ui.buttonAngle`) is fine.
3. **Chat.** `ns.Print(msg)` becomes `KM.Print(ns, msg)` ("King Maker Scanner: ...").
4. **Public API.** The global table (`ScannerKing`, `EconKing`, `FarmKing`, ...) and its functions stay exactly as
   they were: other modules, Oracle and third-party code call them. Callback owner names stay ("Market_King").
5. **No own minimap button.** Delete it. Its clicks become quick actions
   (`KM.RegisterQuickAction{ label, order, func }`) and its tooltip a line or two (`KM.RegisterTooltip(fn(tt))`).
   The `button` slash subcommand prints "The King Maker crown on the minimap replaces this button: /km button".
6. **No own main window.** It becomes one or more pages: `KM.RegisterPage{ id, group, label, icon, order, title,
   subtitle, badge, build, refresh, hide }`. The page container is about **764 x 560**. Old `Toggle(show)` calls
   become `KM.Show(id)` / `KM.Toggle(false)`. Several old tabs become a `UI.Tabs` strip at the top of the page.
7. **Draw only with `KM.UI`** (Theme.lua): `UI.Panel`, `UI.Text`, `UI.Button`, `UI.CheckLabel`, `UI.Tabs`,
   `UI.EditBox`, `UI.MenuButton`, `UI.Tile`, `UI.Table`, `UI.Scroll`, `UI.Bar`, `UI.Pill`. No `UIPanelButtonTemplate`,
   `BackdropTemplate` dialog art, `UICheckButtonTemplate` or `InputBoxTemplate` anywhere.
8. **Floating surfaces stay floating, restyled:** AH title-bar buttons (`UI.Button` "primary"), the Deep Scan and
   Market Scan dialogs and export windows (`UI.Window`), the Farm session tracker and Gather ledger (`UI.HUD`), map
   and minimap pins (unchanged logic).
9. **Settings** that lived in slash commands or a Blizzard panel are also rows in `KM.RegisterSettings{ id, label,
   order, rows }` (see Settings.lua). Every slash command and subcommand keeps working.
10. **Home and status.** Optional `KM.RegisterHomeTile{ order, get }` (one or two per module, where it means
    something) and `KM.RegisterStatus(fn)` for the sidebar box (Scanner: price age).
11. **Paths.** `Interface\AddOns\gather_king\...` becomes `Interface\AddOns\King_Maker\...`.
12. All the workspace non-negotiables (E:\wow_addons\CLAUDE.md) still apply.

## 4. Pages

| Group | Page id | Label | From |
|---|---|---|---|
| King Maker | home | Home | Core |
| Auction House | prices | Prices | Scanner (Browser) |
| Auction House | history | Price History | Econ (list + item page) |
| Auction House | ledger | Sales Ledger | Mail (Summary, Sales, Purchases, Expired, Items, Not selling, Buyers) |
| Crafting | crafting | Crafting Profits | Market |
| Crafting | skillups | Skill-ups | Skillup |
| Gold | inventory | Inventory | Inventory (Overview, Items) |
| Farming | mobs | Mob Farming | Farm (list + mob page) |
| Farming | whites | White Items | Farm |
| Farming | gathering | Gathering | Gather (profiles, types, display, sharing, export) |
| Characters | dungeons | Dungeon Quests | Quest (Dungeons, Route) |
| Characters | rested | Rested XP | Rested |
| | settings | Settings | Core + every module's section (Minimap: the button drawer) |
| Oracle (plug-in) | oracle-* | Oracle pages | the Oracle addon, when installed |

## 5. Tests

`python tests/run.py` from `AddOns/King_Maker` runs `core.py` and every `tests/<module>.py`. Each suite uses
`km.fresh(only=[...])` to load the core plus the modules it needs, against the shared mock. Extra stubs a suite
needs go in its own `seed`/`extra` Lua, not in mock.lua.

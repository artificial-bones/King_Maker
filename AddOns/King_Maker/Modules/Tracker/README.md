# Farm Tracker and Farming Ledger

New in King Maker 2.6. One floating **Farm Tracker** for all your mob farming and
all your gathering, and a **Farming Ledger** page in the King Maker window. Every
time you start and stop, the session is saved, and you can open it later and see
what it made. It replaces Farm's "Farm tracker" box and Gathering's "Farming
ledger" box.

## Where things are

| What | Where |
|---|---|
| The Farm Tracker | A small floating box: `/farm`, the crown's **Farm Tracker** quick action, the **Farm tracker** button on Mob Farming, the tick on the Gathering page, or a key |
| Start or stop a session | The tracker's buttons, the crown's **Start farming** / **Stop farming (save)**, `/farm start` / `/farm stop`, or a key |
| Every saved session | King Maker window, **Farming > Farming Ledger** (`/km farming`, `/farm ledger`, or **L** on the tracker) |
| Settings | **Settings > Farm Tracker** |
| Home | A **Farming now** tile while a session runs, **Farmed, 7 days** otherwise |
| Key bindings | **Esc > Options > Key Bindings > AddOns > King Maker** |

## What a session counts

Only what you actually **take** from a loot window counts; group rolls never do.
Coin counts as the money that actually arrives, so in a group your share is what
counts.

| Source | Counted as farmed |
|---|---|
| Mob drops and coin, per corpse (looting several at once still splits right) | Yes |
| Skinning, pickpocketing | Yes |
| Mining, herbs, fishing | Yes |
| Chests and other objects you open, containers (clams, lockboxes, junkboxes) | Yes: a container you looted in the same session counts as what was inside, not twice |
| Party coin shares (money that arrives while grouped with nothing open) | Yes (setting) |
| Disenchanting | No by default: it turns an item you had into mats (setting; the running session follows when you change it, saved ones stay as they were counted) |
| Quest rewards | No by default, but shown on the Money tab (setting) |
| Vendor sales and purchases, repairs, mail, auction house, trade, flights, training | No: shown on the Money tab, and costs come off **net** |

**Value** is King Maker's one rule: the auction price (Scanner's market price,
after the 5% cut) or the vendor price, whichever is better; grey and bind on
pickup items go to the vendor; quest items that don't sell are worth nothing
(a quest item with a vendor or auction price, like Righteous Orb, counts like
any other drop). Group loot you win on a roll, and master loot handed to you,
counts for the mob it dropped from once it reaches your bags. Each item is
valued **when you loot it**, so a later price change never changes a saved
session; the ledger can show any session at **today's** prices instead. Items
with no price yet count as zero until a scan prices them (the tracker says how
many).

**Gold per hour** uses active time only.

## Sessions

- **Start** begins one. With **Start a session by itself when I farm** on (the
  default), 3 kills, nodes, catches or skins within five minutes start one for
  you, with the clock from the first of them. One quest mob never does.
- **Pause** stops the clock. After **5 minutes** with nothing farmed it pauses by
  itself and takes those idle minutes back off; going AFK does the same.
  Farming again resumes it.
- A session left idle-paused for **20 minutes** is saved. A pause you pressed
  yourself is never saved by itself.
- **Stop & save** saves it to the Farming Ledger. **Split** saves it and starts
  the next one straight away. **Discard** throws it away (it asks first).
  Right-click **Stop & save** for all three.
- A `/reload` keeps it running. Log out for a while and it's paused; after two
  hours away it's saved when you come back.
- A session that started by itself and ended up short (under two minutes) or
  worth nothing is dropped quietly. One you started or stopped yourself is
  always kept.
- Each character has its own running session; the ledger shows every
  character's, or just this one's.

## The Farm Tracker

The title bar shows a square (green running, amber paused, grey idle), the
status, the clock and gold per hour, and keeps them when you fold the box with
**-**. Each has its own space: in a narrow box the status gets short ("Idle"
for "Paused (idle)"), then gold per hour steps aside, so nothing runs into
anything. **x** hides the box; the session keeps recording.

| Tab | Shows |
|---|---|
| **All** | Farmed so far and gold per hour, the last ten minutes' pace, the Mobs / Gathering split, a sparkline, the top items and coin, kills, skins and deaths |
| **Mobs** | Kills and kills per hour, each mob's value and value per kill, the top drops (skins included) |
| **Gathering** | Mining, herbs, fishing, treasure and containers with their value per node, catch or chest; the top materials and the nodes by name |
| **Prices** | Mat Prices (was the farming ledger's tab): Mining, Herbs, Skins, Cloth and Ench, most valuable first |

Hover an item for where it came from and how it's valued; shift-click links it.
Not farming, it shows your last session and a **Start** button.

**Size.** Until you size it, the box grows with what you loot: three items, three
rows, up to 8, and past that the mouse wheel scrolls the list. Drag the **dots in
the bottom-right corner** to size it yourself: down for a taller box (every tab's
list, the Prices tab too), right for a wider one with room for longer names. Once
sized, the box keeps that size, with blank rows until the loot fills it. The
smallest is 280 wide and 3 rows, the largest what fits on your screen;
**double-click** the dots to go back to growing with your loot. **Ctrl + wheel**
makes the whole box bigger or smaller (70 to 140%).

## The Farming Ledger

Three tabs share the top bar with **Export**, **All characters / This character** and the period (7 days, 30 days,
All): **Sessions**, **Trends** and **Mat Prices**.

**Sessions.** Six tiles for the period you pick (7 days, 30 days, All): farmed,
gold per hour (and how it compares with the period before), time, sessions,
your best gold per hour (10+ active minutes) and costs. Under them, gold per
hour for each session (orange mobs, aqua gathering, blue mixed; the line is
your average), then every session: date, zone, active time, farmed, gold per
hour, kills and nodes. Click a column to sort; click a bar or a row to open it;
right-click a row to rename, keep or delete it. **BEST** marks your best gold per
hour at a farm (a zone and what you did there, 10+ active minutes, once it has two
sessions to compare), and when a saved session beats it you get one line in chat:
"new best gold per hour here".

**Trends.** Six tiles (farmed, average gold per hour, time farmed, your best zone,
the top item, and this week against last week), **farmed per day** (hover a bar for
the day's total, time, gold per hour and sessions), **Best farms** (each zone and
activity with its sessions, time and gold per hour over all of it; click one to see
only its sessions on the Sessions tab, click the name at the bottom to show all
again) and **Top items farmed**. Carried-over sessions never count here.

**Mat Prices.** Mining, Herbs, Skins, Cloth and Ench: what one sells for (after the
5% cut, or the vendor price), how many are listed, the price against its 30-day
average (Price History), when you last farmed it, how many an hour you farm it, and
your best gold per hour in a session that farmed it. Click an item for its Price
History.

**Export** (or `/farm export`) puts the sessions shown into a window as
comma-separated text: Ctrl+A, Ctrl+C, paste into a spreadsheet. Money is in copper,
times in seconds.

**A session.** Back, the arrows step through the list, **Prices: When looted /
Today**, **Keep**, **Rename**, **Delete**. Six tiles (farmed, gold per hour
against your average in that zone, active time, coin, kills, net), gold over
time, where the gold came from, and four tabs:

| Tab | Shows |
|---|---|
| **Items** | Every item: where it came from, quantity, value each (AH or vendor), total and share. Click one for its Price History |
| **Mobs** | Each mob: kills, coin, drops, skins, total, per kill, share. Click one for its Mob Farming page |
| **Gathering** | Each kind: actions, per action, top item, value, share; the nodes by name |
| **Money** | Your gold at the start and end, and what came and went in between: looted coin, shares, vendor, quest rewards, repairs, purchases, flights. Then costs and **net farmed** |

The ledger keeps 200 sessions (setting). After 45 days a session keeps its
totals and its top 25 items; **kept** (starred) sessions stay as they are.

## Moving in from the old boxes

On the first login with 2.6, what the old farm tracker and farming ledger held
becomes one saved session called **Carried over from the old trackers**
(shown with a pill, and left out of the totals and the chart). The Farm
Tracker shows if either old box was showing, where that box was.

## Commands

| Command | What it does |
|---|---|
| `/farm` (or `/farmtracker`) | Show or hide the Farm Tracker (`on`, `off` work too) |
| `/farm start` | Start (or resume) a session |
| `/farm stop` | Stop and save it to the Farming Ledger |
| `/farm pause` | Pause or resume the clock |
| `/farm split` | Save this session and start the next one straight away |
| `/farm discard` | Throw the current session away (asks first) |
| `/farm ledger` | Open the Farming Ledger (also `/km farming`) |
| `/farm export` | The ledger's sessions as text for a spreadsheet |
| `/farm auto on` / `off` | Start sessions by themselves when you farm |
| `/farm status` | State, time, farmed, gold per hour |
| `/fk mini`, `/gt ledger` | The old commands still work: show or hide it; `/gt ledger reset` saves the session, `/gt ledger timer` pauses it |

## Settings

| Setting | Default |
|---|---|
| Show the Farm Tracker / Show it when a session starts | Off / on |
| Farm Tracker size | 100% |
| Width and rows (the corner dots) | 280 wide, 8 rows |
| Start a session by itself when I farm | On |
| Pause the clock when idle for | 5 min (2, 10, Never) |
| Resume when I farm again | On |
| Save an idle session after | 20 min (10, 60, Never) |
| Count party coin shares / quest gold / disenchanting | On / off / off |
| Keep | 200 sessions (100, 500) |

## For addon authors

```lua
TrackerKing.State()                    -- "idle" | "running" | "paused"
TrackerKing.Live()                     -- a copy of the running session's totals, or nil
TrackerKing.Sessions(since, char)      -- copies of saved sessions' totals, newest first
TrackerKing.Start() / Stop() / Pause() / Resume() / Split() / Toggle() / PauseOrResume()
TrackerKing.ToggleHUD() / SetHUD(on) / HUDShown() / OpenLedger(sessionID)
TrackerKing.RegisterCallback(owner, fn) -- fn(event, ...): "SESSION_STARTED", "SESSION_CHANGED", "SESSION_SAVED"
```

Saved data is `TrackerKingDB` (account-wide); the King Dashboard contract
describes it.

## Tests

`python tests/run.py tracker` (from `AddOns/King_Maker`) runs the tracker with the
Scanner, Farm, Gather and Econ against the shared stand-in for the game
(`tests/tracker.py`; needs `pip install lupa`).

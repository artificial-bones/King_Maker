# Cooldowns (new in King Maker 2.6)

Every crafting cooldown on every character on one page: transmutes, Mooncloth and the Salt Shaker, what's ready,
what to make with it and what that's worth. A red count on the sidebar tells you when one is ready on the character
you're playing.

It's the **Crafting > Cooldowns** page of the King Maker window.

## Where things are

| What | Where |
|---|---|
| The page | King Maker window, **Crafting > Cooldowns** (`/cdk` or `/km cooldowns`) |
| Ready count | On the sidebar's Cooldowns button: **red** = ready on this character, **gold** = only your alts have one |
| From the minimap | Right-click the crown: **Cooldowns**. Its tooltip lists the next three |
| Summary | A **Cooldowns** tile on the King Maker **Home** page |
| Reminders, the count, the shopping list | King Maker **Settings > Cooldowns** |

## What it tracks

| Cooldown | Profession | Needs | Length (until the game says otherwise) |
|---|---|---|---|
| Transmute (all of them share one cooldown, Legionite included) | Alchemy | Philosopher's Stone | Arcanite 2 days, Legionite 47 hours, the rest 1 day |
| Mooncloth | Tailoring | a moonwell | 4 days |
| Refined Salt (Salt Shaker) | Leatherworking 250 | the Salt Shaker | 3 days |

Any other recipe your profession window shows with a cooldown of 2 hours or more is picked up by itself and gets
its own line. If a transmute turns out not to share the cooldown, it moves to its own line too.

## How it works

1. **Log in on each crafter.** King Maker reads its timers from the game at login and whenever they change.
2. **If a line says "open Alchemy once to read"**, open that profession window once on that character.
3. **Timers are saved as clock times**, so an alt's line counts down correctly while you play someone else.
4. **When you craft**, the line shows an estimate (*est*) for a moment until the game confirms the real timer.

## The page

Four tiles across the top: ready now, next up, income a week, and gold lost to idling this week. Under them, one
line per character and cooldown:

| Column | What it shows |
|---|---|
| Cooldown | The product's icon and the cooldown (found ones in gold) |
| Character | In class colours; *(you)* for the one you're on |
| Status | A bar and the time left; **READY** in green, with how long it has sat idle; *no stone* when the tool is missing |
| Make | The best thing to make by gold per day (or your pick) |
| Each / Week | Profit per craft after the 5% cut, and per week at the cooldown's full pace |
| Mats | Crafts your materials cover here (and on alts); red when you're short |

- **Everyone / This character**, a profession filter and **Hide not ready** above the table.
- Click a line for the details below: what it sells for and how fast, materials, profit, per week, trend, when you
  last crafted it and your pace, every choice in the group by gold per day, and the product's price chart.
  Click a choice to make it your pick.
- Right-click a line: what to make, **Stop tracking this cooldown** (it comes back when you craft it), **Forget
  this character**.
- **Shopping: a week of mats** opens Shopping on the list **Cooldown mats**: what your characters on this realm
  and faction need for the next 7 days, minus what you own anywhere. It fills itself.
- Profit follows Crafting Profits' **Buying mats / Farming mats** setting. Every product and material is priced in
  every Scan, ticked on Crafting Profits or not.
- The Profession panel shows a **Cooldown** line for these recipes, and Crafting Profits tags them **CD 4d**.

## Reminders

| When | What | Default |
|---|---|---|
| A cooldown comes ready on the character you're on | Chat line with the best thing to make, a pop-up (click it to open the page), a sound | on |
| Login | One line: what's ready on your alts, and here | on |
| An alt's cooldown comes ready while you play another | Chat line | off |

## Settings

| Setting | Default |
|---|---|
| Sidebar count counts: This character / Here, alts in gold / Any character | Here, alts in gold |
| Count a ready transmute without a Philosopher's Stone | off |
| Chat line, pop-up, sound when a cooldown is ready | on |
| At login, list what's ready on your alts | on |
| Tell me when an alt's cooldown is ready | off |
| Shopping list covers the next N days | 7 |
| Shopping list counts: Realm and faction / This character | Realm and faction |
| Forget characters not seen in 90 days | button |

## Commands

| Command | Does |
|---|---|
| `/cdk` | Open or close the Cooldowns page (`/cooldownking` works too) |
| `/cdk list` | Every character's cooldowns in chat, ready ones first |
| `/cdk scan` | Read every cooldown now |
| `/cdk badge here\|alts\|any` | What the sidebar count counts |
| `/cdk remind on\|off` | Chat line, pop-up and sound together |
| `/cdk forget First Last` | Stop tracking a character |
| `/cdk debug` | What the game reports for each recipe (send it with bug reports) |

## For addon authors

```lua
CooldownKing.GetAll()                  -- { { char, group, label, ready, left, dur, pick, est, src }, ... }
CooldownKing.ReadyCount("here" | "alts" | "any")
CooldownKing.Length(spellID)           -- the recipe's cooldown in seconds, or nil
CooldownKing.State(spellID)            -- "ready" | seconds left on this character | nil
CooldownKing.RegisterCallback(owner, fn)   -- fn("CHANGED") after readings that changed something
CooldownKing.UnregisterCallback(owner)
```

Saved in `CooldownKingDB` (account-wide, schema 1). Times are server time (`GetServerTime()`), character keys
"First Last-Realm", group keys `transmute`, `mooncloth`, `salt` or `r:<spellID>`.

## Tests

`python tests/run.py cooldowns` from `AddOns/King_Maker` (needs `pip install lupa`).

## In-game checks (Phase 0)

On a character with Mooncloth (or a transmute) on cooldown, profession window **closed**. Send the answers along;
they decide whether timers can be read at login without opening anything.

```
/run local i=C_Spell.GetSpellCooldown(18560) print(i and i.startTime, i and i.duration, GetTime(), i and i.activeCategory)
/run print(C_SpellBook.IsSpellKnown(18560), IsPlayerSpell and IsPlayerSpell(18560))
/run print(C_TradeSkillUI.GetRecipeCooldown(18560))
/run local i=C_Spell.GetSpellCooldown(17187) print(i and i.duration)
/run print(C_Container.GetItemCooldown(15846))
/run print(GetSpellBaseCooldown and GetSpellBaseCooldown(18560))
/cdk debug
```

- Run the third line twice: window closed, then with Tailoring open.
- The fourth line: right after a **Legionite** transmute (does Arcanite show the same cooldown?).
- The fifth line: on the Salt Shaker's owner.

# Guild Blacklist (new in King Maker 2.10)

Players your guild doesn't want to group with: scammers, ninja looters, the toxic ones. One list, shared by everyone
in the guild running King Maker. Anyone can add, edit or remove an entry. When a listed player joins your group or
invites you, you're warned before anything happens, and their name shows a big red **BLACKLISTED** in chat.

It's the **Guild > Blacklist** page of the King Maker window.

## Where things are

| What | Where |
|---|---|
| The page | King Maker window, **Guild > Blacklist** (`/bl` or `/km blacklist`) |
| Add someone | Right-click their name in chat, their portrait, a party or raid frame, or a Who list line: **Add to Blacklist** |
| Add from the group finder | **Alt-click** a listing to blacklist its leader |
| Add by name | The **Add** button on the page, or `/bl add First Last: note` |
| Red count | On the sidebar's Blacklist button when a listed player is in your group right now |
| Settings | King Maker **Settings > Blacklist** |

## Adding someone

Pick a reason (**Scam**, **Ninja loot**, **Toxic**, **Other**) and write a short note: what happened. The note is
required (it's what your guild reads) and holds up to 160 characters. Guildmates can't be blacklisted, and neither
can you. Right-click someone already on the list for **Blacklist: edit note** or **Remove from Blacklist**.

## What you see

| Where | What |
|---|---|
| Chat | A red **BLACKLISTED** before their name in say, yell, whispers, party, raid and channels |
| Their tooltip | A red **BLACKLISTED** line, the reason, the note and who added it |
| They join your group | A red warning in the middle of the screen, a sound, and a chat line with the note (once per player per session; after a `/reload` you get one "already in your group" line instead) |
| They invite you | The same warning, before you accept |
| Group finder | A listed leader in red with **BLACKLISTED**; a group with a listed member says how many; the listing's tooltip names them |
| Who list | Listed names in red with **BLACKLISTED** |

King Maker never kicks or declines anyone (the game doesn't let addons do that): it warns and marks only.

## The page

Six tiles across the top: on the list, added this week, last added, last in your group, sharing, guildmates heard
from. Under them a search box (names, notes, who added), the count and **Add**, then the list, newest first:

| Column | What it shows |
|---|---|
| Name | Who's on the list |
| Reason | Scam, Ninja loot, Toxic or Other |
| Added | When (server time) |
| By | Who added them |
| Note | The start of the note |

Click a column to sort by it. Click a line for the whole entry below: the full note, the reason, who added it and
when, the last edit (who and when), and the last time they were in your group, with **Edit** and **Remove** (asks
first). Right-click a line to edit it.

## Sharing with your guild

Every guildmate running King Maker 2.10 or newer keeps the same list. Adds, edits and removals go out at once; at
login one short fingerprint is compared, and only the entries that differ travel. The latest change to an entry wins.
A removal is remembered for 60 days, so a guildmate who missed it can't put the player back.

Only the list is sent: names, reasons, notes, who and when. Nothing else (no farming data, nothing about you). Not in
a guild: the list is yours alone, and nothing is sent. Each guild has its own list, so switching guilds never mixes
them.

## Settings

| Setting | Default |
|---|---|
| Share with my guild | on |
| Warn when one joins your group | on |
| Warn when one invites you | on |
| Play a sound with the warning | on |
| BLACKLISTED before their name in chat | on |
| Line in their tooltip | on |
| Marks in the group finder and Who list | on |
| Forget removed entries after 60 days | on |

## Commands

| Command | Does |
|---|---|
| `/bl` | Open or close the Blacklist page (`/blacklist` works too) |
| `/bl add First Last: note` | Add a player (no note: opens the dialog; no name: your target) |
| `/bl remove First Last` | Take a player off |
| `/bl list` | Everyone on the list, in chat |
| `/bl share on\|off` | Share with your guild |

## For addon authors

```lua
BlacklistKing.IsListed(name)              -- true when "First Last" (realm or not) is on the list
BlacklistKing.Get(name)                   -- { name, reason, reasonLabel, note, by, added, changed, changedBy } or nil
BlacklistKing.GetAll()                    -- every entry, newest first (copies)
BlacklistKing.RegisterCallback(owner, fn) -- fn("CHANGED", key, "added" | "edited" | "removed", fromGuildmate)
BlacklistKing.UnregisterCallback(owner)
```

Saved in `BlacklistKingDB` (account-wide, schema 1): `lists[guildKey]` per guild ("Guild-Realm", or `personal`), each
with `entries`, `seen` and `heard`. Times are server time; keys are the lower-cased full name. Guild messages use King
Maker's prefix `KingMaker1`, kinds `L Q W E` (see `Sync.lua`).

## Tests

`python tests/run.py blacklist` from `AddOns/King_Maker` (needs `pip install lupa`).

## In-game checks

Some hooks can't be tried outside the game. Send the answers along (each line prints what this client has):

```
/run print(Menu and Menu.ModifyMenu, ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter, UnitNameUnmodified, C_GuildInfo and C_GuildInfo.MemberExistsByName)
/run print(RaidNotice_AddMessage, RaidWarningFrame, SOUNDKIT and SOUNDKIT.RAID_WARNING, UnitIsInMyGuild)
/run print(UnitNameUnmodified("target")) print(C_GuildInfo.MemberExistsByName((UnitName("player"))))
/run print(LFGBrowseSearchEntry_Update, LFGBrowseSearchEntryTooltip_UpdateAndShow, LFGWhoListFrame and LFGWhoListFrame.ScrollBox)
```

Run the last line after opening the group finder once yourself (its key or the micro menu), so the game has
loaded it.

- Right-click a name in chat and a portrait: is **Add to Blacklist** there?
- Add a test entry for a friend from another guild, have them `/say` something: is the red **BLACKLISTED** before
  their name? Have them invite you: does the warning show before you accept?
- Open the group finder (Browse) with a listed player's group showing; hover it, and Alt-click another listing.

# Crown King

One crown on the minimap for the whole King suite. Instead of a button per addon, Crown King hides
each King addon's minimap button and lists them in a drop-down under a crown.

- Click the crown for the menu: one line per King addon you have loaded.
- Click a line: the same as left-clicking that addon's button. Right-click a line: the same as
  right-clicking it (Scanner King scans, Market King opens its scan, Gather King picks a profile,
  Farm King opens the zone tab).
- Hover a line for that addon's own tooltip. Escape or a click elsewhere closes the menu.
- Drag the crown to move it around the minimap. It starts as a gold crown; `/crown icon` tries the others.

Works with Scanner, Market, Farm, Gather, Mail, Quest and Skillup King. None of them need changes:
Crown King only hides their buttons.

## Commands

| Command | |
|---|---|
| `/crown` or `/ck` | Open the menu |
| `/crown icon` | Try the next crown (gold, jeweled, royal and more); `/crown icon 2` picks one |
| `/crown release` | Put the King buttons back on the minimap |
| `/crown gather` | Take them into the crown again |

## Tests

`python3 tests/run.py .` (needs `lupa`).

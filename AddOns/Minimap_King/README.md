# Minimap King

One crown on the minimap for every minimap button. Minimap King moves the King addons' buttons, and
any other addon's minimap button, into a drop-down under a crown.

- Click the crown for the menu. The King addons come first under their own heading, then every
  other addon under "Other Addons". Each line is the addon's real button with its name next to it, so
  everything works as before: left-click, right-click, tooltips and menus.
- Clicking a name does the same as clicking its button, and the menu closes once you've picked one.
- **Right-click the crown** (or `/mmk settings`) for the settings: a checkbox for every addon
  button. Untick one to keep it on the minimap instead of in the crown.
- Or **shift-right-click** a name to leave that button on the minimap instead. `/mmk unignore` takes
  them all back in.
- Escape, or a click out in the world, closes the menu. Drag the crown to move it.
- Blizzard's own minimap buttons (tracking, calendar, mail and so on) and map pins stay where they
  are.

Picks up the King addons (Scanner, Market, Econ, Farm, Gather, Mail, Quest and Skillup King), any
addon that uses LibDBIcon (Questie, DBM, Details and most others), and other buttons sitting around
the edge of the minimap. If it takes something it shouldn't, shift-right-click it.

## Commands

| Command | |
|---|---|
| `/mmk` or `/minimapking` | Open the menu |
| `/mmk settings` | Choose which addons go in the crown |
| `/mmk icon` | Try the next crown (gold, jeweled, royal and more); `/mmk icon 2` picks one |
| `/mmk release` | Put every button back on the minimap |
| `/mmk gather` | Take them into the crown again |
| `/mmk unignore` | Take back the buttons you left on the minimap |

## Tests

`python3 tests/run.py .` (needs `lupa`).

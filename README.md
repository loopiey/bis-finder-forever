# BiSFinder

The best items for your talent tree, slot by slot, and a step-by-step plan to get them. For WoW Forever.

Type **/bis** to open it.

## Install

Get it from **CurseForge** or from the **Releases** page here (the file `BiSFinder-x.y.z.zip`), and unzip it into
`World of Warcraft\_forever_\Interface\AddOns`. You should end up with `AddOns\BiSFinder\BiSFinder.toc`.

The green **Code > Download ZIP** button gives a folder called `bis-finder-forever-main`. The game only loads an addon
whose folder has the same name as its `.toc` file, so rename that folder to `BiSFinder` if you use it.

## What it does

- **The best items for every slot**, for your talent tree. Every item is scored with stat weights for that tree (for
  example Spirit and Healing count more for Holy and Discipline Priests, Hit and Attack Power for a Fury Warrior).
- **Every class and talent tree:** pick any class on the left and any talent tree at the top, not only your own.
  Handy for an alt or to help a friend. (Your plan and the "worn" numbers are for your own character.)
- **Choose how many items per slot** (1 to 10, 3 to start), and pick as many of them for your plan as you like.
- **Two tabs:** *Now* shows the best items you can wear at your level. *Endgame* shows the best items at level 60.
- **Where each item comes from:** dungeon boss, quest, crafting, reputation, vendor or PvP.
- **Only items that are in the game.** Raids that are not open yet are hidden and show up by themselves on the day
  they open. Quest rewards that need a closed raid are hidden too.
- **Set bonuses:** for every set, how many pieces are worth wearing compared with the best single items, and what
  the bonuses add.
- **Upgrade plan:** click the items you want. *My plan* puts them in order, biggest upgrade first, as steps:
  "Craft Hide of the Wild (Leatherworking)", "Run Blackrock Depths" (with every boss you need there), a quest, a
  reputation, a vendor. Items you get move to *Done* by themselves.
- **Your own stat weights:** the *Stat weights* button lets you change any number.

## How to use it

1. Type `/bis`, or click the minimap button (left-click: best items, right-click: your plan; click the same button again to close). The first time, it reads the items from the game - this takes a few minutes, the list fills in as
   it goes. After that it opens at once.
2. Your class and talent tree are picked from your character. Click another class on the left, or another tree at
   the top, to see its list (click your own tree again to go back to automatic).
3. Click **Sources** to choose where items may come from.
4. Click items to add them to your plan, then open **My plan**.
5. Click a slot name (for example *Shoulder*) to fold it away; click it again to open it. Shift-click folds or opens
   every slot. Drag the bottom right corner to make the window bigger or smaller.

| Click | Does |
| --- | --- |
| Click | Add to / remove from your plan |
| Shift-click | Link in chat |
| Ctrl-click | Try it on |

## Commands

- `/bis` - open or close the window
- `/bis check <item>` - why an item is or is not shown (name, item ID, or shift-click the item)
- `/bis minimap` - show or hide the minimap button (and say where it is)
- `/bis rescan` - read all items from the game again

## Sources

| Box | Items |
| --- | --- |
| Dungeons | boss and trash drops |
| Raids | raid drops (from the day the raids open) |
| Quests | quest rewards |
| Reputation & sets | reputation rewards and set pieces |
| Crafted | everything a profession can make |
| Vendors & currency | vendors, e.g. Tarnished Undermine Real |
| World drops | world drops and chests |
| PvP (honor) | honor gear |
| Old drops (may be gone) | old drops whose loot may have changed - off to start |
| Unknown source | items nobody has found a source for yet - off to start |

## What is not counted

The score counts the item's own stats and set bonuses with plain stats. On-use and proc effects (many trinkets),
resistances and bonuses like "+36 Attack Power against Undead" are not counted - they are listed so you can judge
them yourself.

## License

GPL-3.0-or-later. See `LICENSE` and `CREDITS.md`.

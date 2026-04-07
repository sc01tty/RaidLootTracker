# RaidLootTracker

A World of Warcraft addon for tracking loot distribution during raids with roll tracking and player summaries.

## Features

### Automatic Loot Tracking
- Automatically captures boss loot using the `LOOT_HISTORY_UPDATE_DROP` event
- Only tracks **boss group-loot roll windows** — quest rewards and non-roll loot are never captured
- Associates each item with the boss and zone it dropped from
- Tracks item links, player names, timestamps, and roll results

### Roll Tracking
- Captures **group loot Need/Greed/Pass rolls** directly from the WoW loot history API
- Shows the winning roll and a configurable number of runner-ups per item (default 2, adjustable in Settings)
- Each roll shows the player name (class-coloured), roll value, and roll type (e.g. `Roll: 98 [Need]`)
- Roll type is tracked per-player: winners and runner-ups each display their own roll type independently
- Supported roll types: **Need**, **Need (OS)**, **Greed**, **Transmog**
- Manual roll entry available for items added manually

### Loot Management
- **Main Window**: View all tracked loot with filtering
- **Search/Filter**: Real-time search across item name, player, and boss
- **Reassign Loot**: Transfer items to different players (original owner is preserved and shown)
- **Manual Entry**: Add loot entries manually via the "Add Entry" button or `/rlt add`
- **Delete Entries**: Remove individual loot entries
- **Clear Session**: Clear current session loot (preserves history)
- **Reset All**: Clear all tracked loot data (confirmation required)

### Roll Display
- Items with roll data show a **+** button next to the Reassign button
- Click **+** to expand the roll breakdown beneath the entry
- Each roll row shows: class icon, class-coloured player name, roll value, and roll type
- Winner's roll is shown in green; runner-ups in white
- Click **−** to collapse

### Player Summary
- View loot distribution by player, sorted by item count
- Click **+** on any player row to expand a roll-type breakdown (e.g. Need: 2, Transmog: 1)
- Hover over a player row to see their full item list in a tooltip

### Minimap Button
- **Left-click**: Toggle main loot window
- **Right-click**: Toggle summary window
- **Drag**: Reposition button around the minimap ring
- Position is saved across sessions

### Easter Egg
- Click the "Raid Loot Tracker" title 5 times quickly to reveal a surprise!

## Installation

1. Extract the `RaidLootTracker` folder to your WoW AddOns directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```

2. Restart World of Warcraft or type `/reload` in-game

3. The minimap icon will appear — drag it to your preferred position

## Usage

### Basic Usage
1. Join a raid and start killing bosses
2. When a boss dies and the group loot roll window opens, rolls are captured automatically
3. Once all players have rolled and a winner is determined, the item is logged
4. Click the minimap button to view tracked loot

### Adding Loot Manually
1. Click the "Add Entry" button or type `/rlt add`
2. **Shift-click an item** from your bags or from a chat link — it will populate the item field automatically
3. Select the player who received the item from the dropdown
4. Optionally enter the boss name
5. Optionally click "Add Rolls" to record roll data manually
6. Click "Add" to save the entry

### Viewing Roll Data
1. Items with rolls show a **+** button next to the Reassign button
2. Click **+** to expand the roll breakdown
3. The winner's row is highlighted in green with their roll type (e.g. `[Need]`)
4. Runner-ups are shown below with their own roll types (count configurable in Settings)
5. Click **−** to collapse

### Reassigning Loot
1. Click the "Reassign" button next to any loot entry
2. Select the new owner from the raid roster dropdown
3. Click "Confirm"
4. The original owner is preserved and shown in the boss column

### Player Summary
1. Click the "Summary" button or right-click the minimap icon
2. View loot count per player, sorted highest first
3. Hover over a player row to see their full item list

### Session Management
- **Clear Session**: Removes loot from the current session only
- **Reset All**: Removes all tracked loot (confirmation dialog)
- All data persists across sessions and UI reloads

## Slash Commands

```
/rlt            - Toggle main loot window
/raidloot       - Alias for /rlt
/rlt summary    - Toggle summary window
/rlt add        - Open manual entry dialog
/rlt clear      - Clear current session
/rlt reset      - Reset all data (confirmation required)
/rlt help       - Show command list
```

## Performance

- **O(1) Entry Lookups**: Hash map index for instant entry access by ID
- **Player Class Caching**: Classes resolved from the loot history API and cached; cleared on roster changes
- **Throttled Filter Refresh**: Smooth typing with a 100ms refresh throttle
- **Duplicate Drop Guard**: `processedDrops` table prevents logging the same roll result twice (the `LOOT_HISTORY_UPDATE_DROP` event fires once per player roll)

## Data Storage

All data is stored in the `RaidLootTrackerDB` saved variable:

```lua
{
    id             = unique_id,
    itemLink       = "item_link",
    itemID         = item_id,
    player         = "PlayerName",
    boss           = "Boss Name",
    zone           = "Zone Name",
    timestamp      = time(),
    originalPlayer = "OriginalOwner",  -- set if reassigned
    rollType       = "Need",           -- winner's roll type, or nil for manual entries
    winningRoll    = { player = "Name", roll = 100, playerClass = "WARRIOR" },
    runnerUps      = {
        { player = "Name", roll = 98, rollType = "Need",  playerClass = "PALADIN" },
        { player = "Name", roll = 82, rollType = "Greed", playerClass = "MAGE" },
    },
}
```

Settings saved: minimap icon position, autoTrack toggle, minimum item quality threshold.

## Technical Details

### Files
- **RaidLootTracker.lua** — Core logic, event handling, data management
- **UI.lua** — All UI components: main window, summary, dialogs, minimap button
- **RaidLootTracker.toc** — Addon metadata (update `## Interface:` each patch)

### Events
- `LOOT_HISTORY_UPDATE_DROP` — Boss loot roll tracking (Need/Greed/Pass)
- `ENCOUNTER_END` — Boss kill detection for fallback boss name
- `ZONE_CHANGED_NEW_AREA` / `PLAYER_ENTERING_WORLD` — Zone tracking
- `ADDON_LOADED` — Database initialisation
- `GROUP_ROSTER_UPDATE` — Class cache invalidation

### Key APIs Used
- `C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)` — Full roll data including winner, all rollers, and roll types
- `C_LootHistory.GetInfoForEncounter(encounterID)` — Boss/encounter name
- `GetPlayerInfoByGUID(guid)` — Class lookup fallback for players not on the local roster
- `CLASS_ICON_TCOORDS` — Standard WoW class icon texture coordinates

### Keeping the Addon Up to Date
Only one line requires updating when the game version changes:

**[RaidLootTracker.toc](RaidLootTracker.toc) line 1:**
```
## Interface: 120001
```
Format: `Major * 10000 + Minor * 100 + Patch` (e.g. patch 12.0.1 = `120001`).
All other APIs are stable and have no known deprecation concerns, except `UIDropDownMenu_*` (used in the reassign and manual entry dropdowns) which Blizzard began deprecating around 10.2 in favour of `Menu.CreateContextMenu`.

## Changelog

- **v1.3**:
  - Added **Settings popup** (new footer button on main window) with a configurable runner-up count — use `+`/`−` to set how many runner-up rolls are displayed per item (default 2, max 24); value persists across sessions
  - **Summary window** player rows are now expandable — click `+` to show a roll-type breakdown beneath each player (e.g. `Need: 2  Transmog: 1  Greed: 1`), colour-coded by roll type (Need = green, Greed = blue, Transmog = purple, Need (OS) = teal)
- **v1.2**: Replaced chat-based roll parsing with `C_LootHistory` API for accurate Need/Greed tracking; added roll type display per player; class icons and class colours on roll rows; shift-click item insertion fixed; quest reward tracking eliminated
- **v1.1**: Performance optimisations, filter UI improvements, easter egg
- **v1.0**: Initial release

## License

This addon is provided as-is for personal use in World of Warcraft.

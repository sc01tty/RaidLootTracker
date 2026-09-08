# RaidLootTracker

A World of Warcraft addon for tracking loot distribution during raids with roll tracking and player summaries.

## Features

### Automatic Loot Tracking
- Automatically captures boss loot using the `LOOT_HISTORY_UPDATE_DROP` event
- Only tracks **boss group-loot roll windows** — quest rewards and non-roll loot are never captured
- Associates each item with the boss, zone, and **raid difficulty** (LFR/Normal/Heroic/Mythic) it dropped from
- Tracks item links, player names, timestamps, and roll results
- Optional **Skip solo-roll items** setting (off by default, toggle in Settings) — don't track a drop if only one player actually rolled Need/Greed/etc. on it, since there was no real contest to record
- Optional **Skip transmog-only items** setting (off by default, toggle in Settings) — don't track a drop if every roll on it was Transmog, since nobody actually needed/greeded it

### Roll Tracking
- Captures **group loot Need/Greed/Pass rolls** directly from the WoW loot history API
- Shows the winning roll and a configurable number of runner-ups per item in the main window's expanded view (default 2, adjustable in Settings up to 40). This limit only applies to that inline view — **Export always includes every captured runner-up regardless of this setting**, since it's meant to be a complete record rather than a display-density control
- Each roll shows the player name (class-coloured), roll value, and roll type (e.g. `Roll: 98 [Need]`)
- Roll type is tracked per-player: winners and runner-ups each display their own roll type independently
- Supported roll types: **Need**, **Need (OS)**, **Greed**, **Transmog**
- Manual roll entry available for items added manually

### Loot Management
- **Main Window**: Shows the current session's loot by default (bounded, so it doesn't grow into an ever-longer list of every raid you've ever done); searching/filtering reaches your full history
- **Sorting**: Click **Player** or **Item** above the list to sort alphabetically (click again to reverse); click **By Boss** to return to the default chronological order
- **Search/Filter**: Real-time search across item name, player, boss, and difficulty — searches all tracked loot, not just the current session
- **Reassign Loot**: Transfer items to different players (original owner is preserved and shown)
- **Manual Entry**: Add loot entries manually via the "Add Entry" button or `/rlt add`
- **Delete Entries**: Remove individual loot entries
- **Clear Session**: Starts a new session (non-destructive — nothing is deleted, older loot just drops out of the default view and stays reachable via search or Full History export)
- **Reset All**: Permanently deletes all tracked loot data (confirmation required)
- **Export**: Export loot as tab-separated text, ready to paste into a spreadsheet — toggle between the current session or your full tracked history (see [Exporting Loot Data](#exporting-loot-data))

### Difficulty Tracking
- Each item's raid difficulty (LFR/Normal/Heroic/Mythic) is shown as a colour-coded tag next to the boss name in the main window
- Difficulty is captured automatically from the encounter — nothing to configure
- Player Summary shows a per-difficulty breakdown when expanded, and the collapsed item count only mentions difficulty when a player's items actually span more than one tier (e.g. `3 items` vs `3 items (2 HC, 1 M)`)

### Roll Display
- Items with roll data show a **+** button next to the Reassign button
- Click **+** to expand the roll breakdown beneath the entry
- Each roll row shows: class icon, class-coloured player name, roll value, and roll type
- Winner's roll is shown in green; runner-ups in white
- Click **−** to collapse

### Player Summary
- View loot distribution by player, sorted by item count
- Click **+** on any player row to expand a roll-type breakdown (e.g. Need: 2, Transmog: 1) and a difficulty breakdown (e.g. Heroic: 3, Mythic: 1)
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
5. Difficulty is pre-filled if you're currently standing in a raid (change it from the dropdown if it's wrong or you're adding an item from elsewhere)
6. Optionally click "Add Rolls" to record roll data manually
7. Click "Add" to save the entry

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
2. Choose a scope with the **Session / Full History** toggle at the top (defaults to Session, matching the main window)
3. View loot count per player, sorted highest first
4. Hover over a player row to see their full item list

### Session Management
- **Clear Session**: Moves the session boundary forward — the main window's default view and the session export both narrow to "from now on," but nothing is deleted. Previous loot stays in your data and remains reachable via search or Export > Full History
- **Reset All**: The only action that actually deletes tracked loot, and the only one with a confirmation dialog
- All data persists across sessions and UI reloads

### Exporting Loot Data
1. Click the "Export" button on the main window
2. Choose a scope with the toggle at the top of the dialog: **Current Session** (default) or **Full History** (everything ever tracked, regardless of session boundary)
3. A tab-separated table of the selected scope's loot is shown in a text box, pre-selected
4. Press `Ctrl+C` to copy, then paste directly into Excel, Google Sheets, or a Word table — no extra "split into columns" step needed
5. Columns: Date, Boss, Difficulty, Zone, Item, Player, Roll Type, Winning Roll, Runner-Ups, Original Player

> Session-only was the original default because exporting after each raid night is the more common workflow, but RCLootCouncil and Gargul both default to (or only offer) full-history export — so **Full History** is offered as an explicit second option to match, for anyone who'd rather export everything at once (e.g. end of a raid tier, or as a standing backup habit).

> WoW addons can't write files to disk directly — the only file-write path is `SavedVariables`, which the client dumps on logout/reload as a raw Lua table, not a spreadsheet format. So, matching how other loot addons (RCLootCouncil, Gargul) handle export, this shows the data as selectable text for you to copy yourself rather than trying to save a file.
>
> **Tab-separated, not comma-separated (CSV):** pasting plain comma-separated text into Sheets/Excel does *not* auto-split into columns — it lands as one literal string per row, which can look correctly split at a glance (long text visually overflows into empty neighbouring cells) until you click a cell and find it empty. Tab-separated text is what both apps actually auto-split on a normal paste.

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
    difficultyName = "Heroic",         -- readable name, or nil for manual entries
    difficultyAbbr = "HC",             -- short tag used in the UI (LFR/N/HC/M)
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

Settings saved: minimap icon position, autoTrack toggle, minimum item quality threshold, runner-up display count, skip-solo-roll toggle, skip-transmog-only toggle.

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
- `GetDifficultyInfo(difficultyID)` — Resolves the `ENCOUNTER_END` difficulty ID into a readable name and LFR/Heroic/Mythic flags
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

- **v1.18.1**:
  - Completed the duplicate-name fix from v1.18.0, which only went half way. That release deduplicated the *dropdowns*, but the same underlying cause was still live in **Player Summary**: one person logged under both "Name" and "Name-Realm" was counted as two separate players with their wins split between them - and since the realm is stripped for display, that showed as two identical-looking rows. Summary now groups by the same identity the dropdowns use
  - Corrected the v1.18.0 fix itself, which was too aggressive: it stripped everything after the "-", so two genuinely different cross-realm raiders sharing a first name ("Bob-Illidan" and "Bob-Sargeras") were merged into one, silently hiding one of them. Name matching is now realm-aware - an unqualified name matches its OWN-realm qualified form (Blizzard only appends a realm for players from a different realm), while two differently-qualified names stay separate
  - Player aliases now match by the same identity, so an alias saved as "Alt-Realm" still applies to loot logged as plain "Alt". Aliases saved before this are re-keyed automatically on login
- **v1.18.0**:
  - Fixed a real bug from a user report: the same real player could show up twice in the Reassign dropdown (and elsewhere player lists are built from more than one source). Root cause: the raid roster API can return a realm-qualified "Name-Realm" for a cross-realm/connected-realm group member, while the loot-roll API returns just "Name" for that same person - names were being deduped on the raw string, so both variants counted as different people. Now deduped on the realm-stripped short name instead
  - Added a **Sort** toggle to Player Summary - by win count (default) or alphabetically by name - working across Session, Full History, and Named Session views alike, not just one
  - Fixed: clicking "Named" in Player Summary (or "Named Session" in Export) with no named sessions created yet only printed an easy-to-miss chat message and otherwise looked like the button did nothing. It now opens the real "Manage Sessions" dialog directly so there's an obvious next step
- **v1.17.3**:
  - Fixed a real bug from a user report: after running a Normal raid then a Heroic raid, Heroic drops could show up tagged "N" (Normal). Root cause: the sticky difficulty fallback (used whenever the live instance-difficulty lookup fails at the exact moment a drop is processed) only ever updated on a boss kill - so after zoning from Normal into Heroic, it stayed stale at "Normal" until the first Heroic kill happened. It now also refreshes the moment you zone into a raid (and on login/reload if you're already standing in one), so it's always correct before any boss in the new difficulty can drop loot
- **v1.17.2**:
  - Reworked the "Manage Sessions" name field based on user feedback: it was always live-editable, so clicking that row's own Active/Paused toggle would silently discard anything you'd typed but not yet committed with Enter - it looked like the name field was reverting on its own with no explanation. The name is now a fixed label by default; a "Rename" button reveals the real edit box only when you actually want to rename, and only one row can be mid-rename at a time
- **v1.17.1**:
  - Found via a self-review of the new named-sessions feature (v1.17.0), all fixed before anyone hit them in-game: renaming a session to an empty/whitespace-only value in the Manage Sessions dialog left the name box showing blank text while the real stored name was actually unchanged underneath - the box now reverts to the real name when a rename is rejected. Pausing, resuming, or deleting a named session didn't refresh an already-open Player Summary window, so it could keep showing stale (or, after a delete, orphaned) data until something else happened to refresh it - now matches the same live-refresh the Manage Aliases dialog already does. Session names are now trimmed of leading/trailing whitespace on create and rename
- **v1.17.0**:
  - Added **named sessions** - an optional, opt-in tagging layer for grouping loot to a specific raid/run (e.g. "ICC 25H Tuesday"), on top of the normal session/history tracking, which behaves exactly as before for anyone who doesn't use it. Settings → "Manage Sessions" lets you create a named session (it starts active immediately), pause it, and resume it later - even much later, with no gap-bridging needed, since membership is a tag on each entry rather than a time range. Multiple named sessions can be active at once, and a loot item logged then just carries every tag that applied. Covers both auto-tracked drops and manually entered ones (Add Entry), since both go through the same underlying function. Deleting a named session only removes the grouping/tag - it never deletes the loot entries themselves. Export and Player Summary both gained a "Named Session" option alongside the existing Session/Full History toggle, to view or export one specific named session by name
- **v1.16.2**:
  - Fixed the minimap button icon: the bag icon texture is square, but the border ring it sits inside is round, and the icon was never cropped to fit - so its corners could poke out past the ring instead of sitting neatly inside it. Now cropped to match
- **v1.16.1**:
  - Fixed: the Manual Entry and Roll Entry player dropdowns went back to showing only yourself if you'd left the group/raid mid-session, even with a fully populated loot table for that session. They were still pulling the player list from the live group roster directly instead of the same roster-plus-session-participants view used elsewhere, so leaving the group collapsed them to a solo fallback. Both now use the same `GetReassignCandidates()` lookup as the Reassign dialog (fixed for that dialog back in v1.14.0) - added a regression test that reproduces the exact "left the group, dropdown only shows me" report and proved it fails without the fix
- **v1.16.0**:
  - Added **player aliasing** — Settings → "Manage Aliases" lets you link an alt to a main (picked from dropdowns of every player already tracked, no free-text typos) so their wins count toward one combined total in Player Summary. The real per-entry record (Main Window, Export) is never altered — only Summary's aggregate counting resolves through the alias. Single-hop only; aliasing to a name that's already an alt of someone else is rejected to avoid chains
- **v1.15.1**:
  - Renamed the "Auto-track loot" setting to **"Enable automatic tracking"** — clearer that it's a master on/off switch, distinct from the filter-style settings above it (Skip solo-roll/transmog-only items). Settings popup widened slightly to fit the longer label with the same margin the other labels use
- **v1.15.0**:
  - Added an **Auto-track loot** checkbox to Settings — a persistent, explicit toggle to pause automatic tracking entirely (e.g. for a pug or off-roster run you don't want counted in your history), then resume it for the next real raid. The underlying `autoTrack` setting already existed and was already enforced, it simply had no UI control anywhere. Manual entry (Add Entry) is unaffected either way
  - Player Summary's expanded view now lists the actual items a player won, not just roll-type/difficulty counts — click a player row's `+` to see both
- **v1.14.0**:
  - Fixed **Reassign** being unable to target anyone who's left the group — the dropdown was pulled only from the live raid roster, so someone who disconnected or left mid-raid vanished from the list entirely. It now also includes everyone already appearing in the current session's data (winners, runner-ups, previous reassign origins), unioned with the live roster. This is computed fresh each time the dialog opens rather than stored anywhere, so there's no new data to grow unbounded or need clearing — it inherits whatever already bounds the session's data
- **v1.13.2**:
  - Fixed the Export dialog's hint text spilling past the left edge of the window. It was anchored to the "Current Session" button rather than the window itself — that button sits left-of-center to make room for "Full History" beside it, so text anchored to it was actually centered on the *button pair*, not the window. Invisible with short text, but the new runner-ups clarification line (v1.13.1) was long enough to visibly clip past the edge. Found via an in-game screenshot
- **v1.13.1**:
  - Added a permanent note in the Export dialog itself clarifying that it always includes every runner-up regardless of the "Runner-ups shown" setting — the Settings-popup tooltip from v1.13.0 was easy to miss since it's not near where the actual confusion happens; this puts the clarification right where a user would notice the discrepancy
- **v1.13.0**:
  - Clarified (via a settings tooltip and this README) that "Runner-ups shown" only limits the main window's inline expanded roll view — Export always includes every captured runner-up regardless of this setting, by design. This was never a bug, but it wasn't documented anywhere, and it genuinely confused a user counting more entries in their exported spreadsheet than the setting said they should see
  - Raised the "Runner-ups shown" ceiling from 24 to 40 (matches WoW's max raid group size)
- **v1.12.2**:
  - Fixed the sort direction indicator showing as a broken "tofu" box instead of an arrow — the encoding fix in v1.12.1 was correct (a real single character now, not garbled text), but WoW's default UI fonts don't include a glyph for that particular Unicode triangle character. Replaced with plain ASCII (`^` / `v`), which renders correctly in every font WoW uses, in every locale, with no encoding or font-coverage risk at all
- **v1.12.1**:
  - Fixed the sort direction arrows (▲/▼) rendering as literal garbled text ("xe2x96xb2") instead of an actual arrow, which also visually overlapped the neighbouring sort button. Caused by using a hex byte escape (`\xNN`) that's only valid in Lua 5.2+ — WoW's client runs Lua 5.1, which doesn't error on it but silently mangles it into garbage text instead. Found from an in-game screenshot; switched to Lua 5.1-safe decimal escapes (`\ddd`), and the sort buttons are also a bit wider now for margin
- **v1.12.0**:
  - Added click-to-sort to the main window: **Player** and **Item** column headers sort the current view alphabetically (click again to reverse), and **By Boss** returns to the default chronological order. Community-requested
- **v1.11.0**:
  - Added a **Session / Full History** toggle to the Player Summary window (defaults to Session), matching the main window and Export dialog. Previously Player Summary always totalled everything ever tracked regardless of the session boundary — inconsistent with the main window's new session-scoped default from v1.10.0
- **v1.10.0**:
  - **Clear Session is now non-destructive.** Previously it permanently deleted the current session's entries — now it only moves the session boundary forward; nothing is deleted, and older loot remains reachable via search or Export > Full History. Reset All (confirmation-gated) is now the only action that actually deletes data
  - Fixed the main window's default (no-filter) view, which was showing *all-time* history rather than the current session — it's now session-scoped by default, so it stays a bounded "tonight's raid" view instead of growing forever. Typing a search still reaches full history, only the no-filter default changed
  - This also makes last update's Full History export meaningfully safer: previously, clicking Clear Session before exporting could destroy data Full History was supposed to preserve. That's no longer possible
- **v1.9.1**:
  - Fixed a memory leak in **Clear Session**: cleared entries were removed from the visible loot log but never dropped from the internal `lootLogIndex` lookup cache, so every entry a Clear Session removed stayed referenced (and un-garbage-collectable) for the rest of the WoW session — defeating the point of clearing for anyone who doesn't want to keep piling up history. `RemoveLootEntry` (the single-item delete) already cleaned this up correctly; `ClearSession` now does the same. `Reset All` was unaffected — it already replaced the whole index at once
- **v1.9.0**:
  - Added a **Current Session / Full History** toggle to the Export dialog — Full History exports every loot entry ever tracked, ignoring the session boundary. Session-only stays the default (still the more common per-raid-night workflow), but full-history is now one click away, matching how RCLootCouncil and Gargul both default to (or only offer) all-time history rather than a session-scoped export
  - Export dialog title/hint updated to reflect the selected scope instead of always saying "session"
- **v1.8.2**:
  - Fixed a long-standing bug in the `ENCOUNTER_END` event handler where `encounterName` was silently dropped when forwarded, shifting every later argument (`difficultyID`, `groupSize`, `success`) one position — since `success` always ended up `nil`, `OnEncounterEnd`'s entire body never ran. This meant `currentBoss` never updated from `ENCOUNTER_END` (the Manual Entry dialog's Boss field pre-fill has always been blank as a result). Found via an executable test suite, not code review — the fix is a one-line argument-forwarding correction. Difficulty tracking was unaffected by this bug, since v1.8.1's live-query design never depended on it
- **v1.8.1**:
  - Fixed difficulty (and zone) potentially recording stale — items are now stamped from the player's **live** current instance state first, only falling back to the cached last-completed-encounter value when not currently inside any instance (e.g. clearing Normal then continuing into Heroic before the next kill no longer risks a Normal-tagged item)
  - Added a **Difficulty** dropdown to the Add Entry dialog, pre-filled from live detection but always overridable — matches how the Boss field already works, for the rare case of backfilling an item from outside the raid it dropped in
- **v1.8.0**:
  - Added **raid difficulty tracking** — each item now records LFR/Normal/Heroic/Mythic from the encounter it dropped in
  - Main window shows a colour-coded difficulty tag next to the boss name (boss column widened 80→130px to fit it)
  - Player Summary shows a per-difficulty breakdown when expanded, and mentions difficulty in the collapsed item count only when a player's items span more than one tier
  - Search/filter and Export now include difficulty
- **v1.7.1**:
  - Fixed Export producing comma-separated (CSV) text, which Sheets/Excel don't auto-split into columns on paste (it looked correct due to text overflow across empty cells, but every field was actually crammed into column A) — switched to tab-separated (TSV), which both apps do auto-split on a normal paste
- **v1.7.0**:
  - Added an **Export** button (main window footer) that shows the current session's loot as a selectable text box, ready to paste into a spreadsheet — main window widened from 550 to 630px to fit the new button
- **v1.6.0**:
  - Added a **Skip transmog-only items** setting (Settings popup, off by default) — when enabled, items where every roll was Transmog are not auto-tracked, since nobody actually contested it for gear
- **v1.5.0**:
  - Added a **Skip solo-roll items** setting (Settings popup, off by default) — when enabled, items where only one player rolled Need/Need (OS)/Greed/Transmog are not auto-tracked, since there was no actual contest for loot council purposes
- **v1.4.2**:
  - Bumped `## Interface:` to `120100` for game patch 12.1.0
  - Verified compatibility against the [Patch 12.1.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes) — no code changes required; all APIs used by the addon (`C_LootHistory.*`, `GetItemInfo`/`C_Item.GetItemInfoInstant`, roster/unit APIs, `UIDropDownMenu_*`, etc.) remain unaffected
- **v1.4**:
  - Fixed tracking stopping after 34 items — WoW's `C_LootHistory` uses a rolling buffer of 34 slots, causing `lootListID` to recycle and new drops to be falsely treated as duplicates; the duplicate guard key now includes the winner's name and item link, preventing collisions across recycled slots, multiple difficulties (Normal/Heroic), and same-boss kills in the same night
- **v1.3**:
  - Added **Settings popup** (new footer button on main window) with a configurable runner-up count — use `+`/`−` to set how many runner-up rolls are displayed per item (default 2, max 24); value persists across sessions
  - **Summary window** player rows are now expandable — click `+` to show a roll-type breakdown beneath each player (e.g. `Need: 2  Transmog: 1  Greed: 1`), colour-coded by roll type (Need = green, Greed = blue, Transmog = purple, Need (OS) = teal)
- **v1.2**: Replaced chat-based roll parsing with `C_LootHistory` API for accurate Need/Greed tracking; added roll type display per player; class icons and class colours on roll rows; shift-click item insertion fixed; quest reward tracking eliminated
- **v1.1**: Performance optimisations, filter UI improvements, easter egg
- **v1.0**: Initial release

## License

This addon is provided as-is for personal use in World of Warcraft.

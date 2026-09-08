-- RaidLootTracker - Core Logic
-- Tracks raid loot, who received it, and allows manual reassignment

local addonName, addon = ...
RaidLootTracker = addon

-- Constants
local EPIC_QUALITY = 4
local LEGENDARY_QUALITY = 5

-- Current encounter tracking
addon.currentBoss = nil
addon.currentZone = nil
addon.currentDifficulty = nil  -- {name = "Heroic", abbr = "HC"}, set on ENCOUNTER_END
addon.nextEntryID = 1
addon.nextSessionID = 1

-- Roll tracking: track processed group loot drops to avoid duplicate entries
addon.processedDrops = {}  -- Map "encounterID-lootListID" -> true

-- Labels for Enum.EncounterLootDropRollState values
local ROLL_STATE_LABELS = {
    [0] = "Need",
    [1] = "Need (OS)",
    [2] = "Transmog",
    [3] = "Greed",
}
local ROLL_STATE_TRANSMOG = 2
local ROLL_STATE_NOROLL = 4
local ROLL_STATE_PASS = 5

-- True if this rollInfo represents a player who actually rolled Need/Need (OS)/Greed/Transmog
-- (i.e. not a no-roll or a pass)
local function IsActiveRoll(rollInfo)
    return rollInfo.roll ~= nil and rollInfo.state ~= ROLL_STATE_NOROLL and rollInfo.state ~= ROLL_STATE_PASS
end

-- The same real player can come back differently formatted from different
-- Blizzard APIs - e.g. the raid roster API returns a realm-qualified
-- "Name-Realm" for a group member, while the loot-roll API can return just
-- "Name" for that same person (or vice versa).
--
-- Blizzard only appends the realm for players from a DIFFERENT realm, so an
-- unqualified name always means "someone on my realm". That makes the safe
-- rule: an unqualified name and its own-realm qualified form are the same
-- person, but two DIFFERENTLY qualified names are not. Naively stripping
-- everything after the "-" would merge "Bob-Illidan" and "Bob-Sargeras" into
-- one person, silently hiding a real raider - worse than the duplicate it
-- was fixing.
local localRealmCache
local function LocalRealm()
    if localRealmCache then return localRealmCache end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = GetRealmName and GetRealmName()
        if realm then realm = (realm:gsub("%s+", "")) end
    end
    -- Only memoize a real answer: these can return nil very early on login,
    -- and caching that would poison every later lookup for the session.
    if realm and realm ~= "" then
        localRealmCache = realm
    end
    return localRealmCache
end

-- Canonical identity for a player name: own-realm names collapse to the bare
-- name, genuinely cross-realm names keep their suffix. Splits on the FIRST
-- hyphen only, so realms that contain one (e.g. "Azjol-Nerub") still resolve.
local function CanonicalName(name)
    if not name then return nil end
    local short, realm = name:match("^(.-)%-(.+)$")
    if not short or short == "" then return name end  -- no realm suffix at all
    if realm == LocalRealm() then return short end
    return name
end

-- Map GetDifficultyInfo's boolean flags to a short display code. displayMythic is
-- checked before isHeroic because some difficulty IDs are internally flagged
-- isHeroic=true but are meant to display as "Mythic" in the UI.
local function GetDifficultyAbbr(isLFR, isHeroic, displayMythic)
    if isLFR then return "LFR" end
    if displayMythic then return "M" end
    if isHeroic then return "HC" end
    return "N"
end

-- Resolve a difficultyID (from ENCOUNTER_END or a live GetInstanceInfo() call)
-- into {name, abbr}, or nil if the ID isn't recognized.
local function ResolveDifficulty(difficultyID)
    local name, _, isHeroic, _, _, displayMythic, _, isLFR = GetDifficultyInfo(difficultyID)
    if not name then return nil end
    return { name = name, abbr = GetDifficultyAbbr(isLFR, isHeroic, displayMythic) }
end

-- Performance optimizations
addon.lootLogIndex = {}  -- Map entryID -> table reference for O(1) lookups
addon.playerClassCache = {}  -- Cache player class lookups

-- Default database structure
local defaults = {
    lootLog = {},
    settings = {
        minimapIcon = { hide = false, minimapPos = 220 },
        autoTrack = true,
        minQuality = EPIC_QUALITY,
        maxRunnerUps = 2,
        skipSoloRolls = false,
        skipTransmogOnly = false,
    },
    sessionStart = nil,
    -- Alt -> main name map, e.g. ["Bobalt"] = "Bob" - lets Player Summary
    -- count an alt's wins toward their main. A data table (like lootLog),
    -- not really a "setting", so kept top-level rather than under settings.
    playerAliases = {},
    -- Named, optional tagging layer on top of the normal session/history
    -- model - see the comment above CreateNamedSession for the full design.
    -- Each entry: {id, name, active, createdAt, closedAt}.
    namedSessions = {},
}

-- Class colors for display
addon.classColors = {
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43 },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73 },
    ["HUNTER"] = { r = 0.67, g = 0.83, b = 0.45 },
    ["ROGUE"] = { r = 1.00, g = 0.96, b = 0.41 },
    ["PRIEST"] = { r = 1.00, g = 1.00, b = 1.00 },
    ["DEATHKNIGHT"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["SHAMAN"] = { r = 0.00, g = 0.44, b = 0.87 },
    ["MAGE"] = { r = 0.41, g = 0.80, b = 0.94 },
    ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79 },
    ["MONK"] = { r = 0.00, g = 1.00, b = 0.59 },
    ["DRUID"] = { r = 1.00, g = 0.49, b = 0.04 },
    ["DEMONHUNTER"] = { r = 0.64, g = 0.19, b = 0.79 },
    ["EVOKER"] = { r = 0.20, g = 0.58, b = 0.50 },
}

-- Initialize the addon
local function InitializeDB()
    if not RaidLootTrackerDB then
        RaidLootTrackerDB = CopyTable(defaults)
    end

    -- Ensure all default keys exist
    for key, value in pairs(defaults) do
        if RaidLootTrackerDB[key] == nil then
            RaidLootTrackerDB[key] = CopyTable(value)
        end
    end

    -- Find the highest entry ID and build index
    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.id >= addon.nextEntryID then
            addon.nextEntryID = entry.id + 1
        end
        -- Build entry index for O(1) lookups
        addon.lootLogIndex[entry.id] = entry
    end

    -- Find the highest named-session ID
    for _, session in ipairs(RaidLootTrackerDB.namedSessions) do
        if session.id >= addon.nextSessionID then
            addon.nextSessionID = session.id + 1
        end
    end

    -- Re-key any aliases saved before names were canonicalized (they could be
    -- stored realm-qualified, which no longer matches how they're looked up).
    -- Idempotent - canonicalizing an already-canonical name is a no-op - so
    -- it's safe to run on every login.
    local migratedAliases = {}
    for alt, main in pairs(RaidLootTrackerDB.playerAliases) do
        migratedAliases[CanonicalName(alt)] = CanonicalName(main)
    end
    RaidLootTrackerDB.playerAliases = migratedAliases

    -- Start session if not set
    if not RaidLootTrackerDB.sessionStart then
        RaidLootTrackerDB.sessionStart = time()
    end
end

-- Helper: Find entry by ID with O(1) lookup
local function FindEntryByID(entryID)
    return addon.lootLogIndex[entryID]
end

-- Helper: Consolidate UI refresh calls
local function RefreshAllDisplays()
    if addon.RefreshLootDisplay then
        addon:RefreshLootDisplay()
    end
    if addon.RefreshSummaryDisplay then
        addon:RefreshSummaryDisplay()
    end
end

-- Get player class from name
function addon:GetPlayerClass(playerName)
    -- Check cache first for O(1) lookup
    if self.playerClassCache[playerName] then
        return self.playerClassCache[playerName]
    end

    local class = nil

    -- Try to get from raid roster first
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, foundClass = GetRaidRosterInfo(i)
            if name then
                -- Handle server names
                local shortName = strsplit("-", name)
                local shortPlayerName = strsplit("-", playerName)
                if shortName == shortPlayerName or name == playerName then
                    class = foundClass
                    break
                end
            end
        end
    end

    -- Check party
    if not class and IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local shortPlayerName = strsplit("-", playerName)
                if name == shortPlayerName or name == playerName then
                    local _, foundClass = UnitClass(unit)
                    class = foundClass
                    break
                end
            end
        end
    end

    -- Check if it's the player
    if not class then
        local playerShortName = strsplit("-", playerName)
        if playerShortName == UnitName("player") then
            local _, foundClass = UnitClass("player")
            class = foundClass
        end
    end

    -- Cache the result
    if class then
        self.playerClassCache[playerName] = class
    end

    return class
end

-- Get class color for a player
function addon:GetClassColor(playerName)
    local class = self:GetPlayerClass(playerName)
    if class and self.classColors[class] then
        return self.classColors[class]
    end
    return { r = 0.7, g = 0.7, b = 0.7 } -- Default gray
end

-- Format a colored player name
function addon:ColorPlayerName(playerName)
    local color = self:GetClassColor(playerName)
    local shortName = strsplit("-", playerName)
    return string.format("|cff%02x%02x%02x%s|r",
        color.r * 255, color.g * 255, color.b * 255, shortName)
end

-- Get the player's actual current zone name and difficulty, live, rather than
-- relying on cached state from the last completed encounter - that cache only
-- updates on a boss kill, so it can be stale (e.g. the raid switched difficulty
-- but nobody's died yet this session). Returns nil, nil if not currently
-- inside any instance, so callers can fall back to the sticky cache for that
-- case (e.g. backfilling an item after already leaving the raid).
function addon:GetLiveInstanceContext()
    local name, instanceType, difficultyID = GetInstanceInfo()
    if not instanceType or instanceType == "none" or not name or name == "" then
        return nil, nil
    end
    return name, ResolveDifficulty(difficultyID)
end

-- Add a loot entry
function addon:AddLootEntry(itemLink, player, boss, zone, winningRoll, runnerUps, rollType, difficulty)
    if not itemLink or not player then return end

    local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local itemID = getItemInfoInstant(itemLink)
    if not itemID then return end

    -- Live instance state takes priority over the sticky per-encounter cache,
    -- which in turn beats "Unknown"/nil. An explicit `difficulty` argument (from
    -- the manual entry dialog's dropdown) overrides both, since the player has
    -- deliberately said what it actually was.
    local liveZone, liveDifficulty = self:GetLiveInstanceContext()
    local resolvedDifficulty = difficulty or liveDifficulty or self.currentDifficulty

    local entry = {
        id = self.nextEntryID,
        itemLink = itemLink,
        itemID = itemID,
        player = player,
        boss = boss or self.currentBoss or "Unknown",
        zone = zone or liveZone or self.currentZone or "Unknown",
        difficultyName = resolvedDifficulty and resolvedDifficulty.name or nil,
        difficultyAbbr = resolvedDifficulty and resolvedDifficulty.abbr or nil,
        timestamp = time(),
        originalPlayer = nil,
        winningRoll = winningRoll,  -- {player = "Name", roll = 100}
        runnerUps = runnerUps or {},  -- Array of {player = "Name", roll = 95, rollType = "Greed"}
        rollType = rollType,  -- "Need", "Need (OS)", "Greed", "Transmog", or nil
        -- ids of any named sessions active right now (see CreateNamedSession) -
        -- purely additive tagging, empty for anyone not using that feature.
        -- Covers both auto-tracked drops and this same function's manual-entry
        -- call site, so nothing extra is needed to tag manual entries too.
        sessionTags = self:GetActiveNamedSessionIds(),
    }

    table.insert(RaidLootTrackerDB.lootLog, entry)
    self.lootLogIndex[entry.id] = entry  -- Maintain index
    self.nextEntryID = self.nextEntryID + 1

    -- Refresh UI if open
    if self.RefreshLootDisplay then
        self:RefreshLootDisplay()
    end
    if self.RefreshSummaryDisplay then
        self:RefreshSummaryDisplay()
    end

    print("|cffffd100RaidLootTracker:|r Added " .. itemLink .. " -> " .. self:ColorPlayerName(player))

    return entry
end

-- Add or update rolls for an entry
function addon:SetEntryRolls(entryID, winningRoll, runnerUps)
    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.id == entryID then
            entry.winningRoll = winningRoll
            entry.runnerUps = runnerUps or {}

            -- Refresh UI
            if self.RefreshLootDisplay then
                self:RefreshLootDisplay()
            end

            return true
        end
    end
    return false
end

-- Get rolls for an entry
function addon:GetEntryRolls(entryID)
    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.id == entryID then
            return entry.winningRoll, entry.runnerUps or {}
        end
    end
    return nil, {}
end

-- Reassign loot to another player
function addon:ReassignLoot(entryID, newPlayer)
    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.id == entryID then
            -- Store original player if not already stored
            if not entry.originalPlayer then
                entry.originalPlayer = entry.player
            end

            local oldPlayer = entry.player
            entry.player = newPlayer

            -- Refresh UI
            if self.RefreshLootDisplay then
                self:RefreshLootDisplay()
            end
            if self.RefreshSummaryDisplay then
                self:RefreshSummaryDisplay()
            end

            print("|cffffd100RaidLootTracker:|r Reassigned " .. entry.itemLink ..
                  " from " .. self:ColorPlayerName(oldPlayer) ..
                  " to " .. self:ColorPlayerName(newPlayer))
            return true
        end
    end
    return false
end

-- Remove a loot entry
function addon:RemoveLootEntry(entryID)
    for i, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.id == entryID then
            local removed = table.remove(RaidLootTrackerDB.lootLog, i)
            self.lootLogIndex[entryID] = nil  -- Remove from index

            RefreshAllDisplays()

            print("|cffffd100RaidLootTracker:|r Removed " .. removed.itemLink)
            return true
        end
    end
    return false
end

-- Resolve a player name through the alias map (alt -> main), single-hop only.
-- SetPlayerAlias below refuses to create a chain, so one lookup is always enough.
function addon:ResolvePlayerAlias(name)
    if not name then return name end
    -- Looked up by canonical identity, so an alias saved under "Zara-MyRealm"
    -- still matches an entry stored as plain "Zara" (and vice versa).
    return RaidLootTrackerDB.playerAliases[CanonicalName(name)] or name
end

-- Alias "alt" so their wins count toward "main" in Player Summary. Rejects
-- aliasing a name to itself, and rejects aliasing TO a name that's already an
-- alt of something else - keeps resolution a single, predictable hop instead
-- of needing to walk a chain.
function addon:SetPlayerAlias(alt, main)
    -- Stored by canonical identity on both sides, so the same pairing can't be
    -- created twice under two different spellings of the same player.
    alt = alt and CanonicalName(alt)
    main = main and CanonicalName(main)
    if not alt or not main or alt == "" or main == "" or alt == main then
        return false
    end
    if RaidLootTrackerDB.playerAliases[main] then
        return false  -- "main" is itself an alt - would create a chain
    end
    RaidLootTrackerDB.playerAliases[alt] = main
    return true
end

function addon:RemovePlayerAlias(alt)
    alt = alt and CanonicalName(alt)
    if alt and RaidLootTrackerDB.playerAliases[alt] then
        RaidLootTrackerDB.playerAliases[alt] = nil
        return true
    end
    return false
end

-- Every distinct player name ever tracked (winners, runner-ups, reassign
-- origins), across full history rather than just the current session -
-- aliasing is about merging wins across a whole tier, not one raid night.
function addon:GetKnownPlayerNames()
    local seen = {}
    local names = {}

    local function addName(name)
        if not name then return end
        local key = CanonicalName(name)
        if not seen[key] then
            seen[key] = true
            table.insert(names, name)
        end
    end

    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        addName(entry.player)
        if entry.winningRoll then
            addName(entry.winningRoll.player)
        end
        if entry.runnerUps then
            for _, ru in ipairs(entry.runnerUps) do
                addName(ru.player)
            end
        end
        addName(entry.originalPlayer)
    end

    table.sort(names)
    return names
end

-- Get player summary (count of items per player). Player names are resolved
-- through the alias map first, so an alt's wins are grouped under their main.
local function BuildPlayerSummary(entries)
    local summary = {}

    for _, entry in ipairs(entries) do
        -- Alias first (an alt's wins count toward their main), then canonical
        -- identity - otherwise the same person logged once as "Zara" and once
        -- as "Zara-MyRealm" splits into two rows with their wins divided
        -- between them, which is exactly what this summary exists to total up.
        local player = CanonicalName(addon:ResolvePlayerAlias(entry.player))
        if not summary[player] then
            summary[player] = {
                count = 0,
                items = {},
                class = addon:GetPlayerClass(player),
            }
        end
        summary[player].count = summary[player].count + 1
        table.insert(summary[player].items, entry)
    end

    return summary
end

-- Current session's totals only - the default, matching the main window's
-- session-scoped default view.
function addon:GetPlayerSummary()
    return BuildPlayerSummary(self:GetSessionLoot())
end

-- Totals across everything ever tracked, regardless of session boundary.
function addon:GetFullHistoryPlayerSummary()
    return BuildPlayerSummary(RaidLootTrackerDB.lootLog)
end

-- Player Summary scoped to one named session's tagged entries only.
function addon:GetNamedSessionPlayerSummary(id)
    return BuildPlayerSummary(self:GetNamedSessionLoot(id))
end

-- Get loot entries filtered. With no filter text, this is what the main
-- window shows by default - scoped to the current session (not all-time
-- history) so it stays a bounded "tonight's raid" view rather than growing
-- forever. Typing an actual search still searches full history, since
-- narrowing down to find something from a past session is the point of
-- searching - only the *default*, no-filter view is session-scoped.
function addon:GetFilteredLoot(filterText)
    if not filterText or filterText == "" then
        return self:GetSessionLoot()
    end

    filterText = filterText:lower()
    local filtered = {}

    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        local matchItem = entry.itemLink:lower():find(filterText, 1, true)
        local matchPlayer = entry.player:lower():find(filterText, 1, true)
        local matchBoss = entry.boss:lower():find(filterText, 1, true)
        local matchDifficulty = entry.difficultyName and entry.difficultyName:lower():find(filterText, 1, true)

        if matchItem or matchPlayer or matchBoss or matchDifficulty then
            table.insert(filtered, entry)
        end
    end

    return filtered
end

-- Get loot entries from the current session only (same boundary ClearSession uses)
function addon:GetSessionLoot()
    local sessionStart = RaidLootTrackerDB.sessionStart
    local sessionLoot = {}

    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.timestamp >= sessionStart then
            table.insert(sessionLoot, entry)
        end
    end

    return sessionLoot
end

-- Resolve an item link to a human-readable name: GetItemInfo first (needs the
-- item cached client-side), falling back to parsing the bracketed name out of
-- the raw link itself (always present, since the client generated the link).
function addon:GetItemDisplayName(itemLink)
    return (GetItemInfo(itemLink)) or itemLink:match("%[(.-)%]") or itemLink
end

-- Sanitize a value for TSV: strip tabs/newlines (which would corrupt the
-- column/row structure) since they're the only characters that matter here.
-- Unlike CSV, TSV needs no quoting - Excel/Sheets auto-split plain tab-
-- separated text into columns on a normal paste, which comma-CSV does not.
local function TSVField(value)
    value = tostring(value or "")
    return (value:gsub("[\t\r\n]+", " "))
end

-- Build a TSV export (with header row) of the given loot entries, ready to
-- paste into a spreadsheet. WoW addons can't write files directly, so this is
-- displayed in a selectable text box for the player to copy themselves.
local function BuildExportTSV(entries)
    local rows = {
        table.concat({
            "Date", "Boss", "Difficulty", "Zone", "Item", "Player", "Roll Type",
            "Winning Roll", "Runner-Ups", "Original Player",
        }, "\t"),
    }

    for _, entry in ipairs(entries) do
        local itemName = addon:GetItemDisplayName(entry.itemLink)

        local runnerUpParts = {}
        if entry.runnerUps then
            for _, ru in ipairs(entry.runnerUps) do
                table.insert(runnerUpParts, string.format("%s (%d%s)", ru.player or "?", ru.roll or 0,
                    ru.rollType and (" " .. ru.rollType) or ""))
            end
        end

        table.insert(rows, table.concat({
            TSVField(date("%Y-%m-%d %H:%M", entry.timestamp)),
            TSVField(entry.boss),
            TSVField(entry.difficultyName),
            TSVField(entry.zone),
            TSVField(itemName),
            TSVField(entry.player),
            TSVField(entry.rollType),
            TSVField(entry.winningRoll and entry.winningRoll.roll),
            TSVField(table.concat(runnerUpParts, "; ")),
            TSVField(entry.originalPlayer),
        }, "\t"))
    end

    return table.concat(rows, "\n")
end

-- Current session's loot only (what "Export" showed before the full-history
-- option was added - still the default, since exporting per raid night is
-- the more common workflow).
function addon:BuildSessionExportTSV()
    return BuildExportTSV(self:GetSessionLoot())
end

-- Everything ever tracked by this addon, regardless of session boundary -
-- matches how RCLootCouncil/Gargul default to exporting full history rather
-- than just the current session.
function addon:BuildFullHistoryExportTSV()
    return BuildExportTSV(RaidLootTrackerDB.lootLog)
end

-- Export of one named session's tagged entries only.
function addon:BuildNamedSessionExportTSV(id)
    return BuildExportTSV(self:GetNamedSessionLoot(id))
end

-- Start a new session. This is NON-destructive: it only moves the session
-- boundary forward, so entries from the session just ended drop out of the
-- default (no-filter) main window view and the session export, but nothing
-- is deleted - they remain in lootLog and stay reachable via Full History
-- export or a search. Reset All is the only action that actually deletes data.
function addon:ClearSession()
    RaidLootTrackerDB.sessionStart = time()

    -- Refresh UI
    if self.RefreshLootDisplay then
        self:RefreshLootDisplay()
    end
    if self.RefreshSummaryDisplay then
        self:RefreshSummaryDisplay()
    end

    print("|cffffd100RaidLootTracker:|r Started a new session. Previous loot is preserved - use Export > Full History to see everything.")
end

-- Reset all data
function addon:ResetAllData()
    RaidLootTrackerDB.lootLog = {}
    RaidLootTrackerDB.sessionStart = time()
    self.nextEntryID = 1
    self.lootLogIndex = {}
    self.processedDrops = {}

    -- Refresh UI
    if self.RefreshLootDisplay then
        self:RefreshLootDisplay()
    end
    if self.RefreshSummaryDisplay then
        self:RefreshSummaryDisplay()
    end

    print("|cffffd100RaidLootTracker:|r All data has been reset.")
end

-- Get raid roster
function addon:GetRaidRoster()
    local roster = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name and type(name) == "string" then
                table.insert(roster, name)
            end
        end
    elseif IsInGroup() then
        -- Add player
        local playerName = UnitName("player")
        if playerName and type(playerName) == "string" then
            table.insert(roster, playerName)
        end
        -- Add party members
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local unitName = UnitName(unit)
                if unitName and type(unitName) == "string" then
                    table.insert(roster, unitName)
                end
            end
        end
    else
        -- Solo - just the player
        local playerName = UnitName("player")
        if playerName and type(playerName) == "string" then
            table.insert(roster, playerName)
        end
    end

    table.sort(roster)
    return roster
end

-- Player names eligible for the Reassign/Manual Entry/Roll Entry player
-- dropdowns: the live roster (people definitely still around) plus everyone
-- already appearing in the current session's data (winners, runner-ups,
-- previous reassign origins) - so someone who's left the group mid-raid
-- still shows up, instead of the dropdown collapsing to just yourself.
-- Deliberately derived fresh each call rather than stored anywhere: there's
-- no new persistent state to prune, since it's just a view over lootLog,
-- which is already bounded by the existing session/reset lifecycle. Also
-- deliberately session-scoped rather than full-history - reaching back
-- through months of unrelated raids would make the dropdown unusable, and
-- the bug this fixes (someone left THIS raid) is already covered by session data.
function addon:GetReassignCandidates()
    local seen = {}
    local candidates = {}

    local function addName(name)
        if not name then return end
        local key = CanonicalName(name)
        if not seen[key] then
            seen[key] = true
            table.insert(candidates, name)
        end
    end

    for _, name in ipairs(self:GetRaidRoster()) do
        addName(name)
    end

    for _, entry in ipairs(self:GetSessionLoot()) do
        addName(entry.player)
        if entry.winningRoll then
            addName(entry.winningRoll.player)
        end
        if entry.runnerUps then
            for _, ru in ipairs(entry.runnerUps) do
                addName(ru.player)
            end
        end
        addName(entry.originalPlayer)
    end

    table.sort(candidates)
    return candidates
end

-- ============================================================================
-- NAMED SESSIONS
-- ============================================================================
-- An optional, purely additive tagging layer on top of the normal session/
-- history model. By default nothing here is ever touched: sessionStart,
-- ClearSession, ResetAllData, GetSessionLoot and the existing Session/Full
-- History export & summary views all behave exactly as before. A user can
-- opt in by creating a named session; while it's active, new loot entries
-- (auto-tracked AND manually entered - both go through AddLootEntry) get its
-- id appended to their sessionTags list, alongside their normal timestamp-
-- based session membership, which is never affected.
--
-- Membership is tag-based, not a time range, specifically so a session can be
-- paused and resumed later with no "gap" to bridge: reactivating just means
-- new entries start being tagged with the same id again, however much later.
-- Multiple named sessions can be active at once - a new entry then just gets
-- multiple tags, no ambiguity to resolve.
--
-- Deleting a named session strips its tag from any entries that reference it
-- but never touches the entries themselves - consistent with how aliasing
-- resolves at the display layer without altering the real record.

function addon:CreateNamedSession(name)
    name = name and name:match("^%s*(.-)%s*$")  -- trim leading/trailing whitespace
    if not name or name == "" then
        return nil
    end
    local session = {
        id = self.nextSessionID,
        name = name,
        active = true,
        createdAt = time(),
        closedAt = nil,
    }
    self.nextSessionID = self.nextSessionID + 1
    table.insert(RaidLootTrackerDB.namedSessions, session)
    return session
end

function addon:SetNamedSessionActive(id, active)
    for _, session in ipairs(RaidLootTrackerDB.namedSessions) do
        if session.id == id then
            session.active = active and true or false
            session.closedAt = session.active and nil or time()
            return true
        end
    end
    return false
end

function addon:RenameNamedSession(id, newName)
    newName = newName and newName:match("^%s*(.-)%s*$")  -- trim leading/trailing whitespace
    if not newName or newName == "" then
        return false
    end
    for _, session in ipairs(RaidLootTrackerDB.namedSessions) do
        if session.id == id then
            session.name = newName
            return true
        end
    end
    return false
end

function addon:DeleteNamedSession(id)
    for i, session in ipairs(RaidLootTrackerDB.namedSessions) do
        if session.id == id then
            table.remove(RaidLootTrackerDB.namedSessions, i)
            for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
                if entry.sessionTags then
                    for j = #entry.sessionTags, 1, -1 do
                        if entry.sessionTags[j] == id then
                            table.remove(entry.sessionTags, j)
                        end
                    end
                end
            end
            return true
        end
    end
    return false
end

function addon:GetNamedSessions()
    return RaidLootTrackerDB.namedSessions
end

-- ids of every named session currently active - stamped onto new entries by AddLootEntry
function addon:GetActiveNamedSessionIds()
    local ids = {}
    for _, session in ipairs(RaidLootTrackerDB.namedSessions) do
        if session.active then
            table.insert(ids, session.id)
        end
    end
    return ids
end

-- Every loot entry tagged with a given named session, regardless of when it
-- was logged or which normal session/history it also falls under.
function addon:GetNamedSessionLoot(id)
    local result = {}
    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.sessionTags then
            for _, tagId in ipairs(entry.sessionTags) do
                if tagId == id then
                    table.insert(result, entry)
                    break
                end
            end
        end
    end
    return result
end

-- Handle group loot roll completion via the LootHistory API.
-- LOOT_HISTORY_UPDATE_DROP fires each time a player rolls; we only act when
-- dropInfo.winner is set (i.e. the roll window has closed and a winner is known).
-- This only fires for boss group-loot rolls, so quest rewards are never captured.
local function OnLootHistoryUpdateDrop(self, event, encounterID, lootListID)
    if not RaidLootTrackerDB.settings.autoTrack then return end

    local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    if not dropInfo or not dropInfo.winner or dropInfo.allPassed then return end

    local itemLink = dropInfo.itemHyperlink
    if not itemLink then return end

    -- Avoid processing the same drop twice (event fires on every roll update).
    -- Include winner name and itemLink so recycled lootListIDs (WoW caps history
    -- at 34) and same-boss kills across difficulties never produce false collisions.
    local dropKey = encounterID .. "-" .. lootListID .. "-" .. dropInfo.winner.playerName .. "-" .. itemLink
    if addon.processedDrops[dropKey] then return end

    -- Check item quality
    local _, _, quality = GetItemInfo(itemLink)
    if quality and quality < RaidLootTrackerDB.settings.minQuality then return end

    -- Optionally skip items only one player actually rolled on (no real contest).
    -- Can't determine this without rollInfos, so uncontested-item filtering is
    -- simply skipped (i.e. the item is still tracked) if that data is missing.
    if RaidLootTrackerDB.settings.skipSoloRolls and dropInfo.rollInfos then
        local rollerCount = 0
        for _, rollInfo in ipairs(dropInfo.rollInfos) do
            if IsActiveRoll(rollInfo) then
                rollerCount = rollerCount + 1
            end
        end
        if rollerCount <= 1 then return end
    end

    -- Optionally skip items where every active roll was Transmog (nobody actually
    -- Need/Greed rolled it, so there's no real loot decision to record).
    if RaidLootTrackerDB.settings.skipTransmogOnly and dropInfo.rollInfos then
        local hasNonTransmogRoll = false
        for _, rollInfo in ipairs(dropInfo.rollInfos) do
            if IsActiveRoll(rollInfo) and rollInfo.state ~= ROLL_STATE_TRANSMOG then
                hasNonTransmogRoll = true
                break
            end
        end
        if not hasNonTransmogRoll then return end
    end

    -- Mark as processed before any async work
    addon.processedDrops[dropKey] = true

    -- Get boss name from loot history (more reliable than currentBoss at this moment)
    local encounterInfo = C_LootHistory.GetInfoForEncounter(encounterID)
    local bossName = (encounterInfo and encounterInfo.encounterName) or addon.currentBoss or "Unknown"

    -- Populate class cache from all rollInfos so ColorPlayerName works for every roller.
    -- playerClass may not be present in the API response, so fall back to GetPlayerInfoByGUID.
    if dropInfo.rollInfos then
        for _, rollInfo in ipairs(dropInfo.rollInfos) do
            if rollInfo.playerName then
                local class = rollInfo.playerClass
                if not class and rollInfo.playerGUID then
                    local _, englishClass = GetPlayerInfoByGUID(rollInfo.playerGUID)
                    class = englishClass
                end
                if class then
                    -- Cache under both the full name and the short (no-realm) name
                    addon.playerClassCache[rollInfo.playerName] = class
                    local shortName = strsplit("-", rollInfo.playerName)
                    addon.playerClassCache[shortName] = class
                end
            end
        end
    end

    local winner = dropInfo.winner
    local winningRoll = {
        player = winner.playerName,
        roll = winner.roll or 0,
        playerClass = winner.playerClass,
    }

    -- Determine how the winner rolled (Need / Greed / etc.)
    local rollType = ROLL_STATE_LABELS[winner.state]

    -- Collect runner-ups from the sorted rollInfos list (already highest-first)
    local runnerUps = {}
    if dropInfo.rollInfos then
        for _, rollInfo in ipairs(dropInfo.rollInfos) do
            if not rollInfo.isWinner and IsActiveRoll(rollInfo) then
                table.insert(runnerUps, {
                    player = rollInfo.playerName,
                    roll = rollInfo.roll,
                    rollType = ROLL_STATE_LABELS[rollInfo.state],
                    playerClass = rollInfo.playerClass,
                })
            end
        end
    end

    addon:AddLootEntry(itemLink, winner.playerName, bossName, addon.currentZone,
                       winningRoll, runnerUps, rollType)
end

-- Handle encounter end (keep currentBoss/currentDifficulty updated as a fallback
-- for when AddLootEntry's live instance lookup can't run, e.g. after leaving)
local function OnEncounterEnd(self, event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        addon.currentBoss = encounterName

        local resolved = ResolveDifficulty(difficultyID)
        if resolved then
            addon.currentDifficulty = resolved
        end
    end
end

-- Handle zone change. Also refreshes the sticky currentDifficulty fallback -
-- previously only ENCOUNTER_END (a boss kill) updated it, so someone who
-- just came from a Normal raid and zones into Heroic would have that
-- fallback still saying Normal until their first Heroic kill. If the live
-- lookup in AddLootEntry ever fails at the exact moment a drop is processed
-- (its own comment already calls this out as a real possibility), it falls
-- back to this cache - which needs to already be correct by then, not only
-- after a kill. Refreshing on zone change closes that gap: it's always
-- current before any boss in the new instance can possibly die.
local function OnZoneChanged(self, event)
    local name, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        addon.currentZone = name
        local resolved = ResolveDifficulty(difficultyID)
        if resolved then
            addon.currentDifficulty = resolved
        end
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitializeDB()
        print("|cffffd100RaidLootTracker|r loaded. Type |cff00ff00/rlt|r for options.")

        -- Initialize zone + difficulty fallback, in case of a /reload or
        -- relog while already standing inside a raid.
        local name, instanceType, difficultyID = GetInstanceInfo()
        if instanceType == "raid" then
            addon.currentZone = name
            local resolved = ResolveDifficulty(difficultyID)
            if resolved then
                addon.currentDifficulty = resolved
            end
        end

    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnLootHistoryUpdateDrop(self, event, arg1, arg2)

    elseif event == "ENCOUNTER_END" then
        -- arg2 (encounterName) must be forwarded explicitly - it's a named
        -- parameter in this outer function, so plain `...` alone excludes it,
        -- which used to silently shift every later arg by one position and
        -- leave `success` as nil (OnEncounterEnd's body never ran as a result).
        OnEncounterEnd(self, event, arg1, arg2, ...)

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        OnZoneChanged(self, event)

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Clear class cache when roster changes
        addon.playerClassCache = {}
    end
end)

-- Slash commands
SLASH_RAIDLOOTTRACKER1 = "/rlt"
SLASH_RAIDLOOTTRACKER2 = "/raidloot"

-- Command handlers lookup table (more efficient than if/elseif chain)
local slashCommands = {
    [""] = function()
        addon:ToggleMainWindow()
    end,

    ["summary"] = function()
        addon:ToggleSummaryWindow()
    end,

    ["reset"] = function()
        StaticPopup_Show("RAIDLOOTTRACKER_RESET_CONFIRM")
    end,

    ["clear"] = function()
        addon:ClearSession()
    end,

    ["add"] = function()
        addon:ShowManualEntryDialog()
    end,

    ["help"] = function()
        print("|cffffd100RaidLootTracker Commands:|r")
        print("  |cff00ff00/rlt|r - Toggle main loot window")
        print("  |cff00ff00/rlt summary|r - Toggle summary window")
        print("  |cff00ff00/rlt add|r - Manually add a loot entry")
        print("  |cff00ff00/rlt clear|r - Clear current session")
        print("  |cff00ff00/rlt reset|r - Reset all data")
        print("  |cff00ff00/rlt help|r - Show this help")
    end,
}

SlashCmdList["RAIDLOOTTRACKER"] = function(msg)
    local cmd = msg:lower():trim()
    local handler = slashCommands[cmd]

    if handler then
        handler()
    else
        print("|cffffd100RaidLootTracker:|r Unknown command. Type |cff00ff00/rlt help|r for options.")
    end
end

-- Confirmation popup for reset
StaticPopupDialogs["RAIDLOOTTRACKER_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset ALL loot tracking data? This cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        addon:ResetAllData()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

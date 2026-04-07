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
addon.nextEntryID = 1

-- Roll tracking: track processed group loot drops to avoid duplicate entries
addon.processedDrops = {}  -- Map "encounterID-lootListID" -> true

-- Labels for Enum.EncounterLootDropRollState values
local ROLL_STATE_LABELS = {
    [0] = "Need",
    [1] = "Need (OS)",
    [2] = "Transmog",
    [3] = "Greed",
}

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
    },
    sessionStart = nil,
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

-- Add a loot entry
function addon:AddLootEntry(itemLink, player, boss, zone, winningRoll, runnerUps, rollType)
    if not itemLink or not player then return end

    local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local itemID = getItemInfoInstant(itemLink)
    if not itemID then return end

    local entry = {
        id = self.nextEntryID,
        itemLink = itemLink,
        itemID = itemID,
        player = player,
        boss = boss or self.currentBoss or "Unknown",
        zone = zone or self.currentZone or GetInstanceInfo() or "Unknown",
        timestamp = time(),
        originalPlayer = nil,
        winningRoll = winningRoll,  -- {player = "Name", roll = 100}
        runnerUps = runnerUps or {},  -- Array of {player = "Name", roll = 95, rollType = "Greed"}
        rollType = rollType,  -- "Need", "Need (OS)", "Greed", "Transmog", or nil
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

-- Get player summary (count of items per player)
function addon:GetPlayerSummary()
    local summary = {}

    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        local player = entry.player
        if not summary[player] then
            summary[player] = {
                count = 0,
                items = {},
                class = self:GetPlayerClass(player),
            }
        end
        summary[player].count = summary[player].count + 1
        table.insert(summary[player].items, entry)
    end

    return summary
end

-- Get loot entries filtered
function addon:GetFilteredLoot(filterText)
    if not filterText or filterText == "" then
        return RaidLootTrackerDB.lootLog
    end

    filterText = filterText:lower()
    local filtered = {}

    for _, entry in ipairs(RaidLootTrackerDB.lootLog) do
        local matchItem = entry.itemLink:lower():find(filterText, 1, true)
        local matchPlayer = entry.player:lower():find(filterText, 1, true)
        local matchBoss = entry.boss:lower():find(filterText, 1, true)

        if matchItem or matchPlayer or matchBoss then
            table.insert(filtered, entry)
        end
    end

    return filtered
end

-- Clear current session
function addon:ClearSession()
    local sessionStart = RaidLootTrackerDB.sessionStart
    local toRemove = {}

    for i, entry in ipairs(RaidLootTrackerDB.lootLog) do
        if entry.timestamp >= sessionStart then
            table.insert(toRemove, i)
        end
    end

    -- Remove in reverse order to maintain indices
    for i = #toRemove, 1, -1 do
        table.remove(RaidLootTrackerDB.lootLog, toRemove[i])
    end

    -- Reset session
    RaidLootTrackerDB.sessionStart = time()

    -- Refresh UI
    if self.RefreshLootDisplay then
        self:RefreshLootDisplay()
    end
    if self.RefreshSummaryDisplay then
        self:RefreshSummaryDisplay()
    end

    print("|cffffd100RaidLootTracker:|r Session cleared. Removed " .. #toRemove .. " entries.")
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

-- Handle group loot roll completion via the LootHistory API.
-- LOOT_HISTORY_UPDATE_DROP fires each time a player rolls; we only act when
-- dropInfo.winner is set (i.e. the roll window has closed and a winner is known).
-- This only fires for boss group-loot rolls, so quest rewards are never captured.
local function OnLootHistoryUpdateDrop(self, event, encounterID, lootListID)
    if not RaidLootTrackerDB.settings.autoTrack then return end

    -- Avoid processing the same drop twice (event fires on every roll update)
    local dropKey = encounterID .. "-" .. lootListID
    if addon.processedDrops[dropKey] then return end

    local dropInfo = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    if not dropInfo or not dropInfo.winner or dropInfo.allPassed then return end

    local itemLink = dropInfo.itemHyperlink
    if not itemLink then return end

    -- Check item quality
    local _, _, quality = GetItemInfo(itemLink)
    if quality and quality < RaidLootTrackerDB.settings.minQuality then return end

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
            -- state 4 = NoRoll, state 5 = Pass — skip those
            if not rollInfo.isWinner and rollInfo.roll
                    and rollInfo.state ~= 4 and rollInfo.state ~= 5 then
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

-- Handle encounter end (keep currentBoss updated as a fallback)
local function OnEncounterEnd(self, event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        addon.currentBoss = encounterName
    end
end

-- Handle zone change
local function OnZoneChanged(self, event)
    local name, instanceType = GetInstanceInfo()
    if instanceType == "raid" then
        addon.currentZone = name
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

        -- Initialize zone
        local name, instanceType = GetInstanceInfo()
        if instanceType == "raid" then
            addon.currentZone = name
        end

    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnLootHistoryUpdateDrop(self, event, arg1, arg2)

    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(self, event, arg1, ...)

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

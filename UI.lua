-- RaidLootTracker - UI Components
-- Main loot window, summary window, dialogs, and minimap button

local addonName, addon = ...

-- UI Constants
local WINDOW_WIDTH = 630
local WINDOW_HEIGHT = 450
local SUMMARY_WIDTH = 320
local SUMMARY_HEIGHT = 480
local ROW_HEIGHT = 28
local HEADER_HEIGHT = 30

-- Performance: Throttle filter refresh
local throttleTimer = nil
local function ThrottledRefresh()
    if throttleTimer then return end
    throttleTimer = C_Timer.After(0.1, function()
        throttleTimer = nil
        addon:RefreshLootDisplay()
    end)
end

-- Colors
local COLORS = {
    background = { 0.1, 0.1, 0.1, 0.95 },
    header = { 0.15, 0.15, 0.15, 1 },
    border = { 0.4, 0.4, 0.4, 1 },
    gold = { 1, 0.82, 0, 1 },
    rowAlt = { 0.12, 0.12, 0.12, 1 },
    rowHover = { 0.2, 0.2, 0.3, 1 },
    button = { 0.2, 0.2, 0.2, 1 },
    buttonHover = { 0.3, 0.3, 0.3, 1 },
}

-- Difficulty tag colours - reuses WoW's own item-quality colour convention
-- (green/white/blue/orange) since players already read that as a tier scale.
-- Shared between the main loot list, the Player Summary breakdown, and the
-- Manual Entry dialog's difficulty dropdown.
local DIFFICULTY_COLORS = {
    ["LFR"] = "|cff1eff00",
    ["N"]   = "|cffffffff",
    ["HC"]  = "|cff0070dd",
    ["M"]   = "|cffff8000",
}

-- Fixed easy-to-hard order for difficulty breakdowns/dropdowns, rather than
-- first-seen order (unlike roll types, difficulty tiers have an obvious order)
local DIFFICULTY_ORDER = { "LFR", "N", "HC", "M" }

-- Full-word labels (the collapsed summary count and the row tag use the short
-- DIFFICULTY_COLORS keys instead, for space)
local DIFFICULTY_LABELS = {
    ["LFR"] = "LFR",
    ["N"]   = "Normal",
    ["HC"]  = "Heroic",
    ["M"]   = "Mythic",
    ["?"]   = "Unknown",
}

-- Helper: Create a styled frame
local function CreateStyledFrame(name, parent, width, height, title)
    local frame = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(COLORS.background))
    frame:SetBackdropBorderColor(unpack(COLORS.border))

    -- Header bar
    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    header:SetBackdropColor(unpack(COLORS.header))
    frame.header = header

    -- Title text
    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText(title or "Window")
    titleText:SetTextColor(unpack(COLORS.gold))
    frame.titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", -5, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.closeBtn = closeBtn

    frame:Hide()
    return frame
end

-- Helper: Create a styled button
local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 80, height or 24)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(unpack(COLORS.button))
    btn:SetBackdropBorderColor(unpack(COLORS.border))

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.buttonHover))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.button))
    end)

    return btn
end

-- ============================================================================
-- MAIN LOOT WINDOW
-- ============================================================================

local mainFrame = CreateStyledFrame("RaidLootTrackerMainFrame", UIParent, WINDOW_WIDTH, WINDOW_HEIGHT, "Raid Loot Tracker")
addon.mainFrame = mainFrame

-- Easter egg: Click title 5 times
local clickCount = 0
local lastClickTime = 0
mainFrame.titleText:SetScript("OnMouseDown", function(self)
    local currentTime = GetTime()

    -- Reset counter if more than 2 seconds since last click
    if currentTime - lastClickTime > 2 then
        clickCount = 0
    end

    clickCount = clickCount + 1
    lastClickTime = currentTime

    if clickCount >= 5 then
        clickCount = 0
        addon:ShowMoleEasterEgg()
    end
end)

-- Filter label
local filterLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
filterLabel:SetPoint("TOPLEFT", mainFrame.header, "BOTTOMLEFT", 10, -11)
filterLabel:SetText("Filter:")
filterLabel:SetTextColor(0.7, 0.7, 0.7)

-- Filter/Search box
local filterBox = CreateFrame("EditBox", nil, mainFrame, "InputBoxTemplate")
filterBox:SetSize(200, 20)
filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 5, 0)
filterBox:SetAutoFocus(false)
filterBox:SetScript("OnTextChanged", function(self)
    ThrottledRefresh()
end)
filterBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
mainFrame.filterBox = filterBox

-- Item count label
local countLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
countLabel:SetPoint("RIGHT", mainFrame.header, "BOTTOMRIGHT", -10, -16)
countLabel:SetText("0 items")
countLabel:SetTextColor(0.7, 0.7, 0.7)
mainFrame.countLabel = countLabel

-- Sort controls: "By Boss" (default) restores the natural kill-order the
-- window already shows (bosses die in sequence during a raid, so this is
-- effectively "grouped by boss run" without needing an actual grouped-header
-- redesign); "Player"/"Item" sort the current view alphabetically, toggling
-- ascending/descending on repeat clicks. mainFrame.sortMode/sortDir hold the
-- current state, read by RefreshLootDisplay.
mainFrame.sortMode = "boss"
mainFrame.sortDir = 1

local sortBossBtn = CreateStyledButton(mainFrame, "By Boss", 70, 20)
sortBossBtn:SetPoint("TOPLEFT", mainFrame.header, "BOTTOMLEFT", 10, -46)

local sortPlayerBtn = CreateStyledButton(mainFrame, "Player", 78, 20)
sortPlayerBtn:SetPoint("LEFT", sortBossBtn, "RIGHT", 6, 0)

local sortItemBtn = CreateStyledButton(mainFrame, "Item", 70, 20)
sortItemBtn:SetPoint("LEFT", sortPlayerBtn, "RIGHT", 6, 0)

sortBossBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Default order", 1, 1, 1)
    GameTooltip:AddLine("Chronological - the order bosses actually died, which naturally groups each kill's drops together.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
sortBossBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- Update button visuals to reflect the active sort - gold border/text on
-- whichever is active, with a direction arrow on Player/Item when active.
local function UpdateSortVisuals()
    local mode = mainFrame.sortMode
    -- Plain ASCII, not a Unicode triangle glyph (▲/▼). The encoding itself
    -- was fixed (see git history / changelog v1.12.1), but the actual glyph
    -- then rendered as a "tofu" box - WoW's default UI fonts have limited
    -- Unicode symbol coverage and apparently don't include U+25B2/U+25BC.
    -- Confirmed via a second in-game screenshot. Plain ASCII carets render
    -- correctly in every font WoW uses, in every locale, with zero encoding
    -- or font-coverage risk - not as pretty, but guaranteed to work.
    local arrow = mainFrame.sortDir == 1 and " ^" or " v"

    sortBossBtn:SetBackdropBorderColor(unpack(mode == "boss" and COLORS.gold or COLORS.border))
    sortBossBtn.text:SetTextColor(unpack(mode == "boss" and COLORS.gold or { 1, 1, 1, 1 }))

    sortPlayerBtn:SetBackdropBorderColor(unpack(mode == "player" and COLORS.gold or COLORS.border))
    sortPlayerBtn.text:SetTextColor(unpack(mode == "player" and COLORS.gold or { 1, 1, 1, 1 }))
    sortPlayerBtn.text:SetText("Player" .. (mode == "player" and arrow or ""))

    sortItemBtn:SetBackdropBorderColor(unpack(mode == "item" and COLORS.gold or COLORS.border))
    sortItemBtn.text:SetTextColor(unpack(mode == "item" and COLORS.gold or { 1, 1, 1, 1 }))
    sortItemBtn.text:SetText("Item" .. (mode == "item" and arrow or ""))
end

sortBossBtn:SetScript("OnClick", function()
    mainFrame.sortMode = "boss"
    UpdateSortVisuals()
    addon:RefreshLootDisplay()
end)
sortPlayerBtn:SetScript("OnClick", function()
    if mainFrame.sortMode == "player" then
        mainFrame.sortDir = -mainFrame.sortDir
    else
        mainFrame.sortMode = "player"
        mainFrame.sortDir = 1
    end
    UpdateSortVisuals()
    addon:RefreshLootDisplay()
end)
sortItemBtn:SetScript("OnClick", function()
    if mainFrame.sortMode == "item" then
        mainFrame.sortDir = -mainFrame.sortDir
    else
        mainFrame.sortMode = "item"
        mainFrame.sortDir = 1
    end
    UpdateSortVisuals()
    addon:RefreshLootDisplay()
end)

UpdateSortVisuals()

-- Scroll frame for loot entries
local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 8, -104)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 50)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(WINDOW_WIDTH - 40, 1)
scrollFrame:SetScrollChild(scrollChild)
mainFrame.scrollChild = scrollChild

-- Loot rows container
mainFrame.rows = {}

-- Create a loot row
local function CreateLootRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", 0, 0)

    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })

    if index % 2 == 0 then
        row:SetBackdropColor(unpack(COLORS.rowAlt))
    else
        row:SetBackdropColor(0, 0, 0, 0)
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.rowHover))
    end)
    row:SetScript("OnLeave", function(self)
        if index % 2 == 0 then
            self:SetBackdropColor(unpack(COLORS.rowAlt))
        else
            self:SetBackdropColor(0, 0, 0, 0)
        end
    end)

    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 4, 0)
    row.icon = icon

    -- Item name (clickable link)
    local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    itemText:SetWidth(180)
    itemText:SetJustifyH("LEFT")
    itemText:SetWordWrap(false)
    row.itemText = itemText

    -- Player name
    local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerText:SetPoint("LEFT", itemText, "RIGHT", 10, 0)
    playerText:SetWidth(100)
    playerText:SetJustifyH("LEFT")
    row.playerText = playerText

    -- Boss name
    local bossText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossText:SetPoint("LEFT", playerText, "RIGHT", 10, 0)
    bossText:SetWidth(130)  -- wide enough for "HC Boss Name (was: Player)"; ~65px of
                             -- otherwise-unused space sits here before the row buttons
    bossText:SetJustifyH("LEFT")
    bossText:SetWordWrap(false)
    bossText:SetTextColor(0.6, 0.6, 0.6)
    row.bossText = bossText

    -- Reassign button
    local reassignBtn = CreateStyledButton(row, "Reassign", 60, 20)
    reassignBtn:SetPoint("RIGHT", -30, 0)
    reassignBtn:SetScript("OnClick", function()
        if row.entryID then
            addon:ShowReassignDialog(row.entryID)
        end
    end)
    row.reassignBtn = reassignBtn

    -- Expand/Collapse button (for rolls) - positioned to left of Reassign button
    local expandBtn = CreateFrame("Button", nil, row)
    expandBtn:SetSize(16, 16)
    expandBtn:SetPoint("RIGHT", reassignBtn, "LEFT", -5, 0)
    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    expandBtn:Hide()  -- Hidden by default, shown if rolls exist
    expandBtn:SetScript("OnClick", function(self)
        if row.expanded then
            row.expanded = false
            self:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        else
            row.expanded = true
            self:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        end
        addon:RefreshLootDisplay()
    end)
    expandBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.expanded and "Hide Rolls" or "Show Rolls")
        GameTooltip:Show()
    end)
    expandBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.expandBtn = expandBtn

    -- Delete button
    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetSize(16, 16)
    deleteBtn:SetPoint("RIGHT", -8, 0)
    deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    deleteBtn:SetScript("OnClick", function()
        if row.entryID then
            addon:RemoveLootEntry(row.entryID)
        end
    end)
    deleteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove this entry")
        GameTooltip:Show()
    end)
    deleteBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    row.deleteBtn = deleteBtn

    -- Item link click handler
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.itemLink and IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)

    -- Tooltip on hover
    row:HookScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Roll sub-rows container
    row.rollRows = {}
    row.expanded = false

    row:Hide()
    return row
end

-- Create a roll sub-row
local function CreateRollRow(parent)
    local rollRow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    rollRow:SetHeight(22)
    rollRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    rollRow:SetBackdropColor(0.08, 0.08, 0.08, 1)

    -- Class icon (replaces the broken arrow glyph)
    local classIcon = rollRow:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(16, 16)
    classIcon:SetPoint("LEFT", 36, 0)
    rollRow.classIcon = classIcon

    -- Player name
    local playerText = rollRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("LEFT", 57, 0)
    playerText:SetWidth(120)
    playerText:SetJustifyH("LEFT")
    rollRow.playerText = playerText

    -- Roll value
    local rollText = rollRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rollText:SetPoint("LEFT", playerText, "RIGHT", 10, 0)
    rollText:SetTextColor(0.8, 0.8, 0.8)
    rollRow.rollText = rollText

    rollRow:Hide()
    return rollRow
end

-- ============================================================================
-- SETTINGS POPUP
-- ============================================================================

-- Widened from 200 to 230 to comfortably fit the "Enable automatic tracking"
-- label at the same ~24px right-margin the other two checkbox labels already
-- use, rather than crowding that one label right up to the edge. Anchored by
-- its own BOTTOMRIGHT, so growing width extends it further left/up - safe,
-- mainFrame is 630 wide with plenty of room to spare on that side.
local settingsPopup = CreateStyledFrame("RaidLootTrackerSettingsPopup", mainFrame, 230, 270, "Settings")
settingsPopup:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 48)
settingsPopup:SetFrameStrata("DIALOG")
settingsPopup:Hide()

local UpdateSettingsControls  -- forward declaration so closures below can capture it

-- IMPORTANT SCOPE NOTE (this exact ambiguity confused a real user - see
-- README): this setting only limits the main window's inline expanded roll
-- view. Export and the TSV it produces are NOT capped by this - they always
-- include every captured runner-up, by design, since Export is meant to be a
-- complete record rather than a display-density control. The tooltip below
-- says so explicitly to prevent this confusion recurring.
local ruLabel = settingsPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ruLabel:SetPoint("TOP", settingsPopup, "TOP", 0, -36)
ruLabel:SetText("Runner-ups shown:")

local RUNNER_UP_MAX = 40  -- matches WoW's max raid group size; effectively "everyone"

local function ShowRunnerUpTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Runner-ups shown", 1, 1, 1)
    GameTooltip:AddLine("Only limits the main window's expanded roll view (click + on an item). Export always includes every roller, regardless of this setting.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end
ruLabel:SetScript("OnEnter", ShowRunnerUpTooltip)
ruLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

local ruMinusBtn = CreateStyledButton(settingsPopup, "-", 22, 22)
ruMinusBtn:SetPoint("TOP", settingsPopup, "TOP", -20, -58)
ruMinusBtn:SetScript("OnClick", function()
    local cur = RaidLootTrackerDB.settings.maxRunnerUps or 2
    if cur > 0 then
        RaidLootTrackerDB.settings.maxRunnerUps = cur - 1
        UpdateSettingsControls()
        addon:RefreshLootDisplay()
    end
end)

local ruValueLabel = settingsPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ruValueLabel:SetPoint("TOP", settingsPopup, "TOP", 0, -60)
ruValueLabel:SetWidth(20)
ruValueLabel:SetJustifyH("CENTER")
settingsPopup.ruValueLabel = ruValueLabel

local ruPlusBtn = CreateStyledButton(settingsPopup, "+", 22, 22)
ruPlusBtn:SetPoint("TOP", settingsPopup, "TOP", 20, -58)
ruPlusBtn:SetScript("OnClick", function()
    local cur = RaidLootTrackerDB.settings.maxRunnerUps or 2
    if cur < RUNNER_UP_MAX then
        RaidLootTrackerDB.settings.maxRunnerUps = cur + 1
        UpdateSettingsControls()
        addon:RefreshLootDisplay()
    end
end)

-- Skip solo-roll items: don't auto-track a drop if only one player actually rolled on it
local skipSoloCheckbox = CreateFrame("CheckButton", nil, settingsPopup, "UICheckButtonTemplate")
skipSoloCheckbox:SetSize(22, 22)
skipSoloCheckbox:SetPoint("TOPLEFT", settingsPopup, "TOPLEFT", 12, -95)
skipSoloCheckbox:SetScript("OnClick", function(self)
    RaidLootTrackerDB.settings.skipSoloRolls = self:GetChecked() and true or false
end)
skipSoloCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Skip Solo Rolls", 1, 1, 1)
    GameTooltip:AddLine("Don't track an item if only one player rolled on it.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
skipSoloCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
settingsPopup.skipSoloCheckbox = skipSoloCheckbox

local skipSoloLabel = settingsPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
skipSoloLabel:SetPoint("LEFT", skipSoloCheckbox, "RIGHT", 2, 0)
skipSoloLabel:SetWidth(140)
skipSoloLabel:SetJustifyH("LEFT")
skipSoloLabel:SetText("Skip solo-roll items")

-- Skip transmog-only items: don't auto-track a drop if every roll on it was Transmog
local skipTransmogCheckbox = CreateFrame("CheckButton", nil, settingsPopup, "UICheckButtonTemplate")
skipTransmogCheckbox:SetSize(22, 22)
skipTransmogCheckbox:SetPoint("TOPLEFT", settingsPopup, "TOPLEFT", 12, -122)
skipTransmogCheckbox:SetScript("OnClick", function(self)
    RaidLootTrackerDB.settings.skipTransmogOnly = self:GetChecked() and true or false
end)
skipTransmogCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Skip Transmog-Only Rolls", 1, 1, 1)
    GameTooltip:AddLine("Don't track an item if every roll on it was Transmog.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
skipTransmogCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
settingsPopup.skipTransmogCheckbox = skipTransmogCheckbox

local skipTransmogLabel = settingsPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
skipTransmogLabel:SetPoint("LEFT", skipTransmogCheckbox, "RIGHT", 2, 0)
skipTransmogLabel:SetWidth(140)
skipTransmogLabel:SetJustifyH("LEFT")
skipTransmogLabel:SetText("Skip transmog-only items")

-- Auto-track loot: master on/off for automatic tracking (settings.autoTrack
-- already existed and was already enforced in OnLootHistoryUpdateDrop, but
-- had no UI control anywhere - this was a real, working kill-switch nobody
-- could actually flip). Lets someone pause tracking for a pug/off-roster run
-- without it polluting their real history, then resume for the next raid -
-- a persistent, explicit choice rather than an assumed default, since some
-- groups (e.g. tracking a whole tier) want everything captured, pugs included.
local autoTrackCheckbox = CreateFrame("CheckButton", nil, settingsPopup, "UICheckButtonTemplate")
autoTrackCheckbox:SetSize(22, 22)
autoTrackCheckbox:SetPoint("TOPLEFT", settingsPopup, "TOPLEFT", 12, -149)
autoTrackCheckbox:SetScript("OnClick", function(self)
    RaidLootTrackerDB.settings.autoTrack = self:GetChecked() and true or false
end)
autoTrackCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Enable Automatic Tracking", 1, 1, 1)
    GameTooltip:AddLine("Unticking this turns automatic tracking off entirely - useful for a pug or off-roster run you don't want counted in your history. Manual entry (Add Entry) still works either way.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
autoTrackCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
settingsPopup.autoTrackCheckbox = autoTrackCheckbox

-- 170px, not the 140 the two labels above use - this text is close enough to
-- that boundary (26 chars vs. "Skip transmog-only items"'s 25) that it's
-- worth the extra headroom. Matches the same ~24px right-margin those two
-- already use, now that settingsPopup itself is 30px wider to accommodate it.
local autoTrackLabel = settingsPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoTrackLabel:SetPoint("LEFT", autoTrackCheckbox, "RIGHT", 2, 0)
autoTrackLabel:SetWidth(170)
autoTrackLabel:SetJustifyH("LEFT")
autoTrackLabel:SetText("Enable automatic tracking")

-- Opens the alias management dialog (defined further down, after it's
-- created) - so an alt's wins can be merged into their main's Player Summary
-- total.
local manageAliasesBtn = CreateStyledButton(settingsPopup, "Manage Aliases", 150, 24)
manageAliasesBtn:SetPoint("TOP", settingsPopup, "TOP", 0, -180)
manageAliasesBtn:SetScript("OnClick", function()
    addon:ShowAliasDialog()
end)

-- Opens the named-sessions dialog (defined further down, after it's created)
-- - an optional, opt-in layer for tagging loot to a specific named raid/run,
-- on top of the normal session/history behavior which is unaffected.
local manageSessionsBtn = CreateStyledButton(settingsPopup, "Manage Sessions", 150, 24)
manageSessionsBtn:SetPoint("TOP", settingsPopup, "TOP", 0, -212)
manageSessionsBtn:SetScript("OnClick", function()
    addon:ShowSessionsDialog()
end)

UpdateSettingsControls = function()
    local val = RaidLootTrackerDB.settings.maxRunnerUps or 2
    settingsPopup.ruValueLabel:SetText(tostring(val))
    settingsPopup.skipSoloCheckbox:SetChecked(RaidLootTrackerDB.settings.skipSoloRolls and true or false)
    settingsPopup.skipTransmogCheckbox:SetChecked(RaidLootTrackerDB.settings.skipTransmogOnly and true or false)
    -- autoTrack defaults to true (matches `defaults.settings.autoTrack`), so
    -- an absent/nil value should still show checked, not unchecked.
    settingsPopup.autoTrackCheckbox:SetChecked(RaidLootTrackerDB.settings.autoTrack ~= false)
end

settingsPopup:SetScript("OnShow", UpdateSettingsControls)

-- Footer buttons
local addBtn = CreateStyledButton(mainFrame, "Add Entry", 90, 26)
addBtn:SetPoint("BOTTOMLEFT", 10, 12)
addBtn:SetScript("OnClick", function()
    addon:ShowManualEntryDialog()
end)

local clearBtn = CreateStyledButton(mainFrame, "Clear Session", 100, 26)
clearBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
clearBtn:SetScript("OnClick", function()
    addon:ClearSession()
end)
-- HookScript (not SetScript) so this adds to CreateStyledButton's existing
-- OnEnter/OnLeave hover-color handlers instead of replacing them.
clearBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Start a new session", 1, 1, 1)
    GameTooltip:AddLine("Doesn't delete anything - just moves what counts as \"current\" forward. Older loot stays available via Export > Full History or by searching.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
clearBtn:HookScript("OnLeave", function()
    GameTooltip:Hide()
end)

local resetBtn = CreateStyledButton(mainFrame, "Reset All", 80, 26)
resetBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
resetBtn:SetScript("OnClick", function()
    StaticPopup_Show("RAIDLOOTTRACKER_RESET_CONFIRM")
end)

local exportBtn = CreateStyledButton(mainFrame, "Export", 70, 26)
exportBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
exportBtn:SetScript("OnClick", function()
    addon:ShowExportDialog()
end)

local settingsBtn = CreateStyledButton(mainFrame, "Settings", 75, 26)
settingsBtn:SetPoint("BOTTOMRIGHT", -100, 12)
settingsBtn:SetScript("OnClick", function()
    if settingsPopup:IsShown() then
        settingsPopup:Hide()
    else
        settingsPopup:Show()
    end
end)

local summaryBtn = CreateStyledButton(mainFrame, "Summary", 80, 26)
summaryBtn:SetPoint("BOTTOMRIGHT", -10, 12)
summaryBtn:SetScript("OnClick", function()
    addon:ToggleSummaryWindow()
end)

-- Refresh the loot display
function addon:RefreshLootDisplay()
    local filterText = mainFrame.filterBox:GetText()
    local entries = self:GetFilteredLoot(filterText)

    -- Apply the active sort. "boss" is the default and needs no extra sort -
    -- entries already come back in chronological (kill) order. entries is a
    -- freshly-built array from GetFilteredLoot/GetSessionLoot, never a direct
    -- reference to RaidLootTrackerDB.lootLog, so sorting it in place here
    -- never reorders the addon's actual stored data.
    if mainFrame.sortMode == "player" then
        table.sort(entries, function(a, b)
            local pa, pb = a.player:lower(), b.player:lower()
            if mainFrame.sortDir == 1 then return pa < pb end
            return pa > pb
        end)
    elseif mainFrame.sortMode == "item" then
        table.sort(entries, function(a, b)
            local na, nb = self:GetItemDisplayName(a.itemLink):lower(), self:GetItemDisplayName(b.itemLink):lower()
            if mainFrame.sortDir == 1 then return na < nb end
            return na > nb
        end)
    end

    -- Update count label
    mainFrame.countLabel:SetText(#entries .. " item" .. (#entries ~= 1 and "s" or ""))

    -- Ensure enough rows exist
    while #mainFrame.rows < #entries do
        local row = CreateLootRow(mainFrame.scrollChild, #mainFrame.rows + 1)
        table.insert(mainFrame.rows, row)
    end

    -- Calculate total height including expanded rows
    local yOffset = 0
    local displayIndex = 0

    -- Populate rows
    for i, row in ipairs(mainFrame.rows) do
        if i <= #entries then
            local entry = entries[i]
            row.entryID = entry.id
            row.itemLink = entry.itemLink

            -- Get item info
            local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            local itemID, _, _, _, icon = getItemInfoInstant(entry.itemLink)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Set text
            row.itemText:SetText(entry.itemLink)
            row.playerText:SetText(addon:ColorPlayerName(entry.player))

            -- Difficulty tag (e.g. "HC"), colour-coded; blank for entries with no
            -- difficulty data (manual entries, or logged before this feature existed)
            local difficultyTag = ""
            if entry.difficultyAbbr then
                local color = DIFFICULTY_COLORS[entry.difficultyAbbr] or "|cffaaaaaa"
                difficultyTag = color .. entry.difficultyAbbr .. "|r "
            end

            -- Show original player if traded
            if entry.originalPlayer and entry.originalPlayer ~= entry.player then
                row.bossText:SetText(difficultyTag .. entry.boss .. " (was: " .. entry.originalPlayer .. ")")
            else
                row.bossText:SetText(difficultyTag .. entry.boss)
            end

            -- Check if entry has rolls
            local hasRolls = (entry.winningRoll or (entry.runnerUps and #entry.runnerUps > 0))
            if hasRolls then
                row.expandBtn:Show()
                if row.expanded then
                    row.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                else
                    row.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                end
            else
                row.expandBtn:Hide()
                row.expanded = false
            end

            -- Reposition main row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", 0, 0)
            yOffset = yOffset + ROW_HEIGHT

            -- Alternate colors
            if displayIndex % 2 == 0 then
                row:SetBackdropColor(unpack(COLORS.rowAlt))
            else
                row:SetBackdropColor(0, 0, 0, 0)
            end
            displayIndex = displayIndex + 1

            row:Show()

            -- Handle expanded roll rows
            if row.expanded and hasRolls then
                local rollData = {}

                -- Add winning roll if exists
                if entry.winningRoll then
                    table.insert(rollData, {
                        player = entry.winningRoll.player,
                        roll = entry.winningRoll.roll,
                        isWinner = true,
                        rollType = entry.rollType,
                        playerClass = entry.winningRoll.playerClass,
                    })
                end

                -- Add runner-ups up to the user-configured limit
                local maxRunnerUps = RaidLootTrackerDB.settings.maxRunnerUps or 2
                if entry.runnerUps then
                    for i, runnerUp in ipairs(entry.runnerUps) do
                        if i > maxRunnerUps then break end
                        table.insert(rollData, {
                            player = runnerUp.player,
                            roll = runnerUp.roll,
                            isWinner = false,
                            rollType = runnerUp.rollType,
                            playerClass = runnerUp.playerClass,
                        })
                    end
                end

                -- Ensure enough roll rows exist
                while #row.rollRows < #rollData do
                    local rollRow = CreateRollRow(mainFrame.scrollChild)
                    table.insert(row.rollRows, rollRow)
                end

                -- Display roll rows
                for j, rollRow in ipairs(row.rollRows) do
                    if j <= #rollData then
                        local rollInfo = rollData[j]
                        rollRow.playerText:SetText(addon:ColorPlayerName(rollInfo.player))

                        -- Class icon
                        local pClass = rollInfo.playerClass or addon:GetPlayerClass(rollInfo.player)
                        if pClass and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[pClass] then
                            rollRow.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
                            rollRow.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[pClass]))
                            rollRow.classIcon:Show()
                        else
                            rollRow.classIcon:Hide()
                        end

                        local rollColor = rollInfo.isWinner and "|cff00ff00" or "|cffffffff"
                        local rollTypeStr = rollInfo.rollType and (" [" .. rollInfo.rollType .. "]") or ""
                        rollRow.rollText:SetText(rollColor .. "Roll: " .. rollInfo.roll .. rollTypeStr .. "|r")

                        rollRow:ClearAllPoints()
                        rollRow:SetPoint("TOPLEFT", 0, -yOffset)
                        rollRow:SetPoint("RIGHT", 0, 0)
                        yOffset = yOffset + 22

                        rollRow:Show()
                    else
                        rollRow:Hide()
                    end
                end
            else
                -- Hide all roll rows
                for _, rollRow in ipairs(row.rollRows) do
                    rollRow:Hide()
                end
            end
        else
            row:Hide()
            for _, rollRow in ipairs(row.rollRows) do
                rollRow:Hide()
            end
        end
    end

    -- Update scroll child height
    mainFrame.scrollChild:SetHeight(math.max(1, yOffset))
end

-- Toggle main window
function addon:ToggleMainWindow()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:RefreshLootDisplay()
        mainFrame:Show()
    end
end

-- ============================================================================
-- SUMMARY WINDOW
-- ============================================================================

local summaryFrame = CreateStyledFrame("RaidLootTrackerSummaryFrame", UIParent, SUMMARY_WIDTH, SUMMARY_HEIGHT, "Loot Summary")
summaryFrame:SetPoint("CENTER", 300, 0)
addon.summaryFrame = summaryFrame

-- Scope toggle: "Session" (default), "Full History", or one specific
-- optional Named Session - same pattern as the Export dialog's toggle, so
-- Player Summary stays consistent with the main window's session-scoped
-- default instead of always totalling everything.
local summarySessionBtn = CreateStyledButton(summaryFrame, "Session", 85, 20)
summarySessionBtn:SetPoint("TOP", summaryFrame.header, "BOTTOM", -96, -8)

local summaryFullBtn = CreateStyledButton(summaryFrame, "Full History", 95, 20)
summaryFullBtn:SetPoint("LEFT", summarySessionBtn, "RIGHT", 6, 0)

local summaryNamedBtn = CreateStyledButton(summaryFrame, "Named", 85, 20)
summaryNamedBtn:SetPoint("LEFT", summaryFullBtn, "RIGHT", 6, 0)

-- Sort toggle: by win count (default - most wins first) or alphabetically by
-- name. Applies in every scope (Session/Full History/Named) rather than
-- just one, matching the main window's sort buttons already working across
-- every filter/view there. Always visible (unlike the dropdown below), so
-- it sits right under the toggle row at a fixed, unconditional position.
local summarySortBtn = CreateStyledButton(summaryFrame, "Sort: Count", 110, 18)
summarySortBtn:SetPoint("TOP", summaryFrame, "TOP", 0, -66)
summaryFrame.sortMode = "count"
summarySortBtn:SetScript("OnClick", function(self)
    summaryFrame.sortMode = (summaryFrame.sortMode == "count") and "name" or "count"
    self.text:SetText(summaryFrame.sortMode == "count" and "Sort: Count" or "Sort: Name (A-Z)")
    addon:RefreshSummaryDisplay()
end)

-- Only relevant/shown in "named" mode - picks which named session to view.
-- Anchored below the always-visible sort button (not overlapping it) with
-- enough clearance for its own ~32px height plus a safety margin.
local summarySessionDropdown = CreateFrame("Frame", "RaidLootTrackerSummarySessionDropdown", summaryFrame, "UIDropDownMenuTemplate")
summarySessionDropdown:SetPoint("TOP", summaryFrame, "TOP", 0, -92)
UIDropDownMenu_SetWidth(summarySessionDropdown, 180)
summaryFrame.sessionDropdown = summarySessionDropdown

-- Scroll frame
local summaryScroll = CreateFrame("ScrollFrame", nil, summaryFrame, "UIPanelScrollFrameTemplate")
summaryScroll:SetPoint("TOPLEFT", 8, -134)
summaryScroll:SetPoint("BOTTOMRIGHT", -28, 12)

local summaryScrollChild = CreateFrame("Frame", nil, summaryScroll)
summaryScrollChild:SetSize(SUMMARY_WIDTH - 40, 1)
summaryScroll:SetScrollChild(summaryScrollChild)
summaryFrame.scrollChild = summaryScrollChild

summaryFrame.rows = {}

-- Create a summary player row
local function CreateSummaryRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)

    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0, 0, 0, 0)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.rowHover))
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(self.bgR, self.bgG, self.bgB, self.bgA or 0)
    end)

    -- Expand/collapse button
    local expandBtn = CreateFrame("Button", nil, row)
    expandBtn:SetSize(16, 16)
    expandBtn:SetPoint("LEFT", 4, 0)
    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    expandBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    expandBtn:SetScript("OnClick", function(self)
        row.expanded = not row.expanded
        if row.expanded then
            self:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        else
            self:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        end
        addon:RefreshSummaryDisplay()
    end)
    expandBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.expanded and "Hide Items" or "Show Items")
        GameTooltip:Show()
    end)
    expandBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.expandBtn = expandBtn

    -- Player name
    local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerText:SetPoint("LEFT", 24, 0)
    playerText:SetWidth(160)
    playerText:SetJustifyH("LEFT")
    row.playerText = playerText

    -- Count
    local countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("RIGHT", -10, 0)
    countText:SetTextColor(unpack(COLORS.gold))
    row.countText = countText

    row.expanded = false
    row.breakdownRow = nil  -- created lazily in RefreshSummaryDisplay
    row.difficultyBreakdownRow = nil  -- created lazily in RefreshSummaryDisplay
    row:Hide()
    return row
end

-- Create a roll type breakdown sub-row (one per player, shown when expanded)
local function CreateSummaryBreakdownRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)

    row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    row:SetBackdropColor(0.08, 0.08, 0.08, 1)

    local breakdownText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    breakdownText:SetPoint("LEFT", 24, 0)
    breakdownText:SetPoint("RIGHT", -8, 0)
    breakdownText:SetJustifyH("LEFT")
    row.breakdownText = breakdownText

    row:Hide()
    return row
end

-- Roll type display colours
local ROLL_TYPE_COLORS = {
    ["Need"]        = "|cff00ff00",
    ["Need (OS)"]   = "|cff00cc44",
    ["Greed"]       = "|cff4488ff",
    ["Transmog"]    = "|cffcc55ff",
}

-- Tally a player's items by difficulty tier, in DIFFICULTY_ORDER. Returns the
-- counts, the tiers actually present (in order), and how many distinct tiers.
local function TallyDifficulty(items)
    local counts = {}
    for _, entry in ipairs(items) do
        local tier = entry.difficultyAbbr or "?"
        counts[tier] = (counts[tier] or 0) + 1
    end

    local present = {}
    for _, tier in ipairs(DIFFICULTY_ORDER) do
        if counts[tier] then table.insert(present, tier) end
    end
    if counts["?"] then table.insert(present, "?") end  -- entries with no difficulty data

    return counts, present, #present
end

-- Update the toggle buttons' visuals to match summaryFrame.mode - active gets
-- a gold border+text, matching the Export dialog's toggle.
local function UpdateSummaryToggleVisuals()
    local mode = summaryFrame.mode
    summarySessionBtn:SetBackdropBorderColor(unpack(mode == "session" and COLORS.gold or COLORS.border))
    summarySessionBtn.text:SetTextColor(unpack(mode == "session" and COLORS.gold or { 1, 1, 1, 1 }))
    summaryFullBtn:SetBackdropBorderColor(unpack(mode == "full" and COLORS.gold or COLORS.border))
    summaryFullBtn.text:SetTextColor(unpack(mode == "full" and COLORS.gold or { 1, 1, 1, 1 }))
    summaryNamedBtn:SetBackdropBorderColor(unpack(mode == "named" and COLORS.gold or COLORS.border))
    summaryNamedBtn.text:SetTextColor(unpack(mode == "named" and COLORS.gold or { 1, 1, 1, 1 }))
    if mode == "named" then
        summarySessionDropdown:Show()
    else
        summarySessionDropdown:Hide()
    end
end

-- Populate the named-session dropdown - lists every named session (active or
-- paused, all eligible to view), most recently created first.
local function PopulateSummarySessionDropdown()
    local sessions = addon:GetNamedSessions()
    UIDropDownMenu_Initialize(summarySessionDropdown, function(_, level)
        for i = #sessions, 1, -1 do
            local s = sessions[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = s.name
            info.value = s.id
            info.func = function(btn)
                summaryFrame.selectedNamedSessionId = btn.value
                UIDropDownMenu_SetText(summarySessionDropdown, s.name)
                addon:RefreshSummaryDisplay()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

summarySessionBtn:SetScript("OnClick", function()
    summaryFrame.mode = "session"
    UpdateSummaryToggleVisuals()
    addon:RefreshSummaryDisplay()
end)
summaryFullBtn:SetScript("OnClick", function()
    summaryFrame.mode = "full"
    UpdateSummaryToggleVisuals()
    addon:RefreshSummaryDisplay()
end)
summaryNamedBtn:SetScript("OnClick", function()
    local sessions = addon:GetNamedSessions()
    if #sessions == 0 then
        -- A chat print alone is too easy to miss, and "clicking Named"
        -- otherwise causes no visible change at all - which reads as the
        -- button being broken rather than there just being nothing to show
        -- yet. Open the real dialog to create one instead of leaving the
        -- user to go find it themselves in Settings.
        print("|cffffd100RaidLootTracker:|r No named sessions yet - create one below.")
        addon:ShowSessionsDialog()
        return
    end
    summaryFrame.mode = "named"
    if not summaryFrame.selectedNamedSessionId then
        local latest = sessions[#sessions]
        summaryFrame.selectedNamedSessionId = latest.id
        UIDropDownMenu_SetText(summarySessionDropdown, latest.name)
    end
    UpdateSummaryToggleVisuals()
    addon:RefreshSummaryDisplay()
end)

summaryFrame.mode = "session"
UpdateSummaryToggleVisuals()

-- Refresh summary display
function addon:RefreshSummaryDisplay()
    local summary
    if summaryFrame.mode == "full" then
        summary = self:GetFullHistoryPlayerSummary()
    elseif summaryFrame.mode == "named" then
        summary = summaryFrame.selectedNamedSessionId and self:GetNamedSessionPlayerSummary(summaryFrame.selectedNamedSessionId) or {}
    else
        summary = self:GetPlayerSummary()
    end

    -- Convert to array and sort by count
    local sorted = {}
    for player, data in pairs(summary) do
        table.insert(sorted, {
            player = player,
            count = data.count,
            items = data.items,
        })
    end
    if summaryFrame.sortMode == "name" then
        table.sort(sorted, function(a, b) return a.player:lower() < b.player:lower() end)
    else
        table.sort(sorted, function(a, b) return a.count > b.count end)
    end

    -- Ensure enough player rows
    while #summaryFrame.rows < #sorted do
        local row = CreateSummaryRow(summaryFrame.scrollChild)
        table.insert(summaryFrame.rows, row)
    end

    local yOffset = 0

    for i, row in ipairs(summaryFrame.rows) do
        if i <= #sorted then
            local data = sorted[i]
            row.playerName = data.player
            row.items = data.items

            -- Alternate background
            local r, g, b, a = 0, 0, 0, 0
            if i % 2 == 0 then r, g, b, a = unpack(COLORS.rowAlt) end
            row.bgR, row.bgG, row.bgB, row.bgA = r, g, b, a
            row:SetBackdropColor(r, g, b, a)

            row.playerText:SetText(addon:ColorPlayerName(data.player))

            -- Only mention difficulty inline in the collapsed count when a player's
            -- items actually span more than one tier - most sessions are a single
            -- difficulty, so stating it every time would just be noise.
            local diffCounts, diffPresent, diffTierCount = TallyDifficulty(data.items)
            local countStr = data.count .. " item" .. (data.count ~= 1 and "s" or "")
            if diffTierCount > 1 then
                local mixParts = {}
                for _, tier in ipairs(diffPresent) do
                    table.insert(mixParts, diffCounts[tier] .. " " .. tier)
                end
                countStr = countStr .. " (" .. table.concat(mixParts, ", ") .. ")"
            end
            row.countText:SetText(countStr)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", 0, 0)
            row:Show()
            yOffset = yOffset + 26

            -- Create breakdown rows lazily
            if not row.breakdownRow then
                row.breakdownRow = CreateSummaryBreakdownRow(summaryFrame.scrollChild)
            end
            if not row.difficultyBreakdownRow then
                row.difficultyBreakdownRow = CreateSummaryBreakdownRow(summaryFrame.scrollChild)
            end

            -- Build roll type count breakdown
            if row.expanded then
                local counts = {}
                local order = {}
                for _, entry in ipairs(data.items) do
                    local rt = entry.rollType or "Unknown"
                    if not counts[rt] then
                        counts[rt] = 0
                        table.insert(order, rt)
                    end
                    counts[rt] = counts[rt] + 1
                end

                local parts = {}
                for _, rt in ipairs(order) do
                    local color = ROLL_TYPE_COLORS[rt] or "|cffaaaaaa"
                    table.insert(parts, color .. rt .. ": " .. counts[rt] .. "|r")
                end
                row.breakdownRow.breakdownText:SetText(table.concat(parts, "  "))

                row.breakdownRow:ClearAllPoints()
                row.breakdownRow:SetPoint("TOPLEFT", 0, -yOffset)
                row.breakdownRow:SetPoint("RIGHT", 0, 0)
                row.breakdownRow:Show()
                yOffset = yOffset + 22

                -- Build difficulty count breakdown, using the tally already computed
                -- above for the collapsed count (always shown here, unlike the
                -- collapsed count's conditional single-tier suppression)
                local diffParts = {}
                for _, tier in ipairs(diffPresent) do
                    local color = DIFFICULTY_COLORS[tier] or "|cffaaaaaa"
                    table.insert(diffParts, color .. DIFFICULTY_LABELS[tier] .. ": " .. diffCounts[tier] .. "|r")
                end
                row.difficultyBreakdownRow.breakdownText:SetText(table.concat(diffParts, "  "))

                row.difficultyBreakdownRow:ClearAllPoints()
                row.difficultyBreakdownRow:SetPoint("TOPLEFT", 0, -yOffset)
                row.difficultyBreakdownRow:SetPoint("RIGHT", 0, 0)
                row.difficultyBreakdownRow:Show()
                yOffset = yOffset + 22

                -- List the actual items won, one per line (not just roll-type/
                -- difficulty counts) - reuses entry.itemLink directly as the
                -- row text so it renders as the same real, clickable, tooltip-
                -- able item link the main window uses, not a plain resolved
                -- name. One row per item (not a single joined/wrapped line)
                -- since a player can have many - same dynamic-pool pattern
                -- the main window already uses for its roll breakdown.
                row.itemRows = row.itemRows or {}
                while #row.itemRows < #data.items do
                    table.insert(row.itemRows, CreateSummaryBreakdownRow(summaryFrame.scrollChild))
                end
                for j, itemRow in ipairs(row.itemRows) do
                    if j <= #data.items then
                        local itemEntry = data.items[j]
                        itemRow.breakdownText:SetText(itemEntry.itemLink .. "  |cff888888(" .. (itemEntry.boss or "Unknown") .. ")|r")
                        itemRow:ClearAllPoints()
                        itemRow:SetPoint("TOPLEFT", 0, -yOffset)
                        itemRow:SetPoint("RIGHT", 0, 0)
                        itemRow:Show()
                        yOffset = yOffset + 22
                    else
                        itemRow:Hide()
                    end
                end
            else
                row.breakdownRow:Hide()
                row.difficultyBreakdownRow:Hide()
                if row.itemRows then
                    for _, itemRow in ipairs(row.itemRows) do
                        itemRow:Hide()
                    end
                end
            end
        else
            row:Hide()
            if row.breakdownRow then
                row.breakdownRow:Hide()
            end
            if row.difficultyBreakdownRow then
                row.difficultyBreakdownRow:Hide()
            end
            if row.itemRows then
                for _, itemRow in ipairs(row.itemRows) do
                    itemRow:Hide()
                end
            end
        end
    end

    summaryFrame.scrollChild:SetHeight(math.max(1, yOffset))
end

-- Toggle summary window
function addon:ToggleSummaryWindow()
    if summaryFrame:IsShown() then
        summaryFrame:Hide()
    else
        PopulateSummarySessionDropdown()
        self:RefreshSummaryDisplay()
        summaryFrame:Show()
    end
end

-- ============================================================================
-- REASSIGN DIALOG
-- ============================================================================

local reassignFrame = CreateStyledFrame("RaidLootTrackerReassignFrame", UIParent, 280, 140, "Reassign Loot")
reassignFrame:SetFrameStrata("DIALOG")
addon.reassignFrame = reassignFrame

local reassignItemText = reassignFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
reassignItemText:SetPoint("TOP", 0, -45)
reassignItemText:SetWidth(260)
reassignFrame.itemText = reassignItemText

local reassignLabel = reassignFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
reassignLabel:SetPoint("TOPLEFT", 15, -75)
reassignLabel:SetText("New Owner:")
reassignLabel:SetTextColor(0.7, 0.7, 0.7)

-- Dropdown for player selection
local reassignDropdown = CreateFrame("Frame", "RaidLootTrackerReassignDropdown", reassignFrame, "UIDropDownMenuTemplate")
reassignDropdown:SetPoint("LEFT", reassignLabel, "RIGHT", -10, -2)
UIDropDownMenu_SetWidth(reassignDropdown, 140)
reassignFrame.dropdown = reassignDropdown

local reassignConfirmBtn = CreateStyledButton(reassignFrame, "Confirm", 80, 26)
reassignConfirmBtn:SetPoint("BOTTOMLEFT", 30, 12)
reassignConfirmBtn:SetScript("OnClick", function()
    if reassignFrame.selectedPlayer and reassignFrame.entryID then
        addon:ReassignLoot(reassignFrame.entryID, reassignFrame.selectedPlayer)
        reassignFrame:Hide()
    end
end)

local reassignCancelBtn = CreateStyledButton(reassignFrame, "Cancel", 80, 26)
reassignCancelBtn:SetPoint("BOTTOMRIGHT", -30, 12)
reassignCancelBtn:SetScript("OnClick", function()
    reassignFrame:Hide()
end)

reassignFrame.selectedPlayer = nil
reassignFrame.entryID = nil

-- Show reassign dialog
function addon:ShowReassignDialog(entryID)
    -- Find the entry
    local entry
    for _, e in ipairs(RaidLootTrackerDB.lootLog) do
        if e.id == entryID then
            entry = e
            break
        end
    end

    if not entry then return end

    reassignFrame.entryID = entryID
    reassignFrame.itemText:SetText(entry.itemLink)
    reassignFrame.selectedPlayer = nil

    -- Setup dropdown - includes anyone from the current session's data, not
    -- just the live roster, so someone who's already left the group can
    -- still be a reassign target/origin.
    local roster = self:GetReassignCandidates()
    UIDropDownMenu_Initialize(reassignDropdown, function(_, level)
        for _, name in ipairs(roster) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                reassignFrame.selectedPlayer = btn.value
                UIDropDownMenu_SetText(reassignDropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(reassignDropdown, "Select player...")

    reassignFrame:Show()
end

-- ============================================================================
-- ALIAS MANAGEMENT DIALOG
-- ============================================================================
-- Lets an alt's wins count toward their main in Player Summary. Deliberately
-- affects Summary's counting only - the real per-entry record (Main Window,
-- Export) always shows exactly who actually won each item.

local aliasFrame = CreateStyledFrame("RaidLootTrackerAliasFrame", UIParent, 320, 320, "Manage Player Aliases")
aliasFrame:SetFrameStrata("DIALOG")
addon.aliasFrame = aliasFrame

local aliasHint = aliasFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aliasHint:SetPoint("TOP", aliasFrame, "TOP", 0, -36)
aliasHint:SetWidth(290)
aliasHint:SetJustifyH("CENTER")
aliasHint:SetTextColor(0.7, 0.7, 0.7)
aliasHint:SetText("Alias an alt so their wins count toward their main in Summary. The real record (Main Window, Export) is never changed.")

local altLabel = aliasFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
altLabel:SetPoint("TOPLEFT", 15, -80)
altLabel:SetText("Alt:")
altLabel:SetTextColor(0.7, 0.7, 0.7)

local altDropdown = CreateFrame("Frame", "RaidLootTrackerAliasAltDropdown", aliasFrame, "UIDropDownMenuTemplate")
altDropdown:SetPoint("LEFT", altLabel, "RIGHT", -5, -2)
UIDropDownMenu_SetWidth(altDropdown, 120)
aliasFrame.altDropdown = altDropdown

local mainLabel = aliasFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mainLabel:SetPoint("TOPLEFT", 15, -112)
mainLabel:SetText("Main:")
mainLabel:SetTextColor(0.7, 0.7, 0.7)

local mainDropdown = CreateFrame("Frame", "RaidLootTrackerAliasMainDropdown", aliasFrame, "UIDropDownMenuTemplate")
mainDropdown:SetPoint("LEFT", mainLabel, "RIGHT", -5, -2)
UIDropDownMenu_SetWidth(mainDropdown, 120)
aliasFrame.mainDropdown = mainDropdown

aliasFrame.selectedAlt = nil
aliasFrame.selectedMain = nil

-- Shared populate helper for both dropdowns - lists every distinct player
-- name ever tracked, so there's no free-text typo risk.
local function PopulateAliasDropdown(dropdown, onSelect)
    local names = addon:GetKnownPlayerNames()
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                onSelect(btn.value)
                UIDropDownMenu_SetText(dropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local aliasAddBtn = CreateStyledButton(aliasFrame, "Add Alias", 100, 24)
aliasAddBtn:SetPoint("TOP", aliasFrame, "TOP", 0, -145)

-- Scrollable list of existing aliases, one row each, with a remove button -
-- same dynamic-row-pool pattern as the main window/Summary window's rows.
local aliasScroll = CreateFrame("ScrollFrame", "RaidLootTrackerAliasScroll", aliasFrame, "UIPanelScrollFrameTemplate")
aliasScroll:SetPoint("TOPLEFT", 12, -177)
aliasScroll:SetPoint("BOTTOMRIGHT", -30, 45)

local aliasScrollChild = CreateFrame("Frame", nil, aliasScroll)
aliasScrollChild:SetSize(260, 1)
aliasScroll:SetScrollChild(aliasScrollChild)
aliasFrame.scrollChild = aliasScrollChild
aliasFrame.rows = {}

local function CreateAliasRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 4, 0)
    text:SetPoint("RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    row.text = text

    local removeBtn = CreateFrame("Button", nil, row)
    removeBtn:SetSize(16, 16)
    removeBtn:SetPoint("RIGHT", -4, 0)
    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    row.removeBtn = removeBtn

    row:Hide()
    return row
end

local function RefreshAliasList()
    local pairsArr = {}
    for alt, main in pairs(RaidLootTrackerDB.playerAliases) do
        table.insert(pairsArr, { alt = alt, main = main })
    end
    table.sort(pairsArr, function(a, b) return a.alt < b.alt end)

    while #aliasFrame.rows < #pairsArr do
        table.insert(aliasFrame.rows, CreateAliasRow(aliasScrollChild))
    end

    local yOffset = 0
    for i, row in ipairs(aliasFrame.rows) do
        if i <= #pairsArr then
            local p = pairsArr[i]
            row.text:SetText(addon:ColorPlayerName(p.alt) .. " |cffaaaaaa->|r " .. addon:ColorPlayerName(p.main))
            row.removeBtn:SetScript("OnClick", function()
                addon:RemovePlayerAlias(p.alt)
                RefreshAliasList()
                addon:RefreshSummaryDisplay()
            end)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", 0, 0)
            row:Show()
            yOffset = yOffset + 22
        else
            row:Hide()
        end
    end
    aliasScrollChild:SetHeight(math.max(1, yOffset))
end
aliasFrame.RefreshList = RefreshAliasList

aliasAddBtn:SetScript("OnClick", function()
    if not aliasFrame.selectedAlt then
        print("|cffffd100RaidLootTracker:|r Please select an alt.")
        return
    end
    if not aliasFrame.selectedMain then
        print("|cffffd100RaidLootTracker:|r Please select a main.")
        return
    end
    if addon:SetPlayerAlias(aliasFrame.selectedAlt, aliasFrame.selectedMain) then
        RefreshAliasList()
        addon:RefreshSummaryDisplay()
        aliasFrame.selectedAlt = nil
        aliasFrame.selectedMain = nil
        UIDropDownMenu_SetText(altDropdown, "Select alt...")
        UIDropDownMenu_SetText(mainDropdown, "Select main...")
    else
        print("|cffffd100RaidLootTracker:|r Couldn't add that alias (same name, or the main is itself already an alt of someone else).")
    end
end)

local aliasCloseBtn = CreateStyledButton(aliasFrame, "Close", 80, 26)
aliasCloseBtn:SetPoint("BOTTOM", 0, 12)
aliasCloseBtn:SetScript("OnClick", function()
    aliasFrame:Hide()
end)

function addon:ShowAliasDialog()
    aliasFrame.selectedAlt = nil
    aliasFrame.selectedMain = nil
    UIDropDownMenu_SetText(altDropdown, "Select alt...")
    UIDropDownMenu_SetText(mainDropdown, "Select main...")
    PopulateAliasDropdown(altDropdown, function(name) aliasFrame.selectedAlt = name end)
    PopulateAliasDropdown(mainDropdown, function(name) aliasFrame.selectedMain = name end)
    RefreshAliasList()
    aliasFrame:Show()
end

-- ============================================================================
-- NAMED SESSIONS DIALOG
-- ============================================================================
-- Optional, opt-in tagging layer on top of the normal session/history model.
-- By default (nobody touches this dialog) the addon behaves exactly as
-- before - Clear Session, Reset All, and Export/Summary's Session/Full
-- History toggle are all untouched. Creating a named session here just adds
-- an extra, independent grouping: while active, new loot (auto-tracked or
-- manually entered) gets tagged with it, and it can be paused/resumed any
-- time with no loss of data - see the comment above CreateNamedSession in
-- RaidLootTracker.lua for the full design reasoning.

StaticPopupDialogs["RAIDLOOTTRACKER_DELETE_SESSION_CONFIRM"] = {
    text = "Delete named session \"%s\"? This does NOT delete any loot entries - it just removes this grouping/tag.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self, data)
        addon:DeleteNamedSession(data.id)
        data.refresh()
        addon:RefreshSummaryDisplay()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local sessionsFrame = CreateStyledFrame("RaidLootTrackerSessionsFrame", UIParent, 340, 340, "Manage Sessions")
sessionsFrame:SetFrameStrata("DIALOG")
addon.sessionsFrame = sessionsFrame

local sessionsHint = sessionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionsHint:SetPoint("TOP", sessionsFrame, "TOP", 0, -36)
sessionsHint:SetWidth(300)
sessionsHint:SetJustifyH("CENTER")
sessionsHint:SetTextColor(0.7, 0.7, 0.7)
sessionsHint:SetText("Optional: tag loot to a specific named raid/run, on top of the normal session/history tracking below - which keeps working exactly as before.")

local sessionNameInput = CreateFrame("EditBox", nil, sessionsFrame, "InputBoxTemplate")
sessionNameInput:SetSize(170, 20)
sessionNameInput:SetPoint("TOPLEFT", 20, -85)
sessionNameInput:SetAutoFocus(false)
sessionsFrame.nameInput = sessionNameInput

local sessionCreateBtn = CreateStyledButton(sessionsFrame, "Start Session", 100, 24)
sessionCreateBtn:SetPoint("LEFT", sessionNameInput, "RIGHT", 8, 0)

-- Scrollable list of named sessions, one row each - same dynamic-row-pool
-- pattern as the Alias dialog.
local sessionsScroll = CreateFrame("ScrollFrame", "RaidLootTrackerSessionsScroll", sessionsFrame, "UIPanelScrollFrameTemplate")
sessionsScroll:SetPoint("TOPLEFT", 12, -117)
sessionsScroll:SetPoint("BOTTOMRIGHT", -30, 45)

local sessionsScrollChild = CreateFrame("Frame", nil, sessionsScroll)
sessionsScrollChild:SetSize(280, 1)
sessionsScroll:SetScrollChild(sessionsScrollChild)
sessionsFrame.scrollChild = sessionsScrollChild
sessionsFrame.rows = {}

local function CreateSessionRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)
    row:EnableMouse(true)  -- needed for the OnEnter/OnLeave tooltip below

    -- Fixed/display-only by default - renaming is an explicit action via the
    -- Rename button below. An always-live edit box here previously meant
    -- clicking this row's own Active/Paused toggle silently discarded
    -- whatever you'd typed but not yet committed, with no warning.
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", 6, 0)
    nameText:SetWidth(90)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)  -- clip, don't wrap, in this fixed-height row
    row.nameText = nameText

    -- Hidden until Rename is clicked; occupies the same spot as nameText.
    local nameBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    nameBox:SetSize(90, 18)
    nameBox:SetPoint("LEFT", 6, 0)
    nameBox:SetAutoFocus(false)
    nameBox:Hide()
    row.nameBox = nameBox

    local renameBtn = CreateStyledButton(row, "Rename", 60, 20)
    renameBtn:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    row.renameBtn = renameBtn

    local toggleBtn = CreateStyledButton(row, "", 74, 20)
    toggleBtn:SetPoint("LEFT", renameBtn, "RIGHT", 4, 0)
    row.toggleBtn = toggleBtn

    local removeBtn = CreateFrame("Button", nil, row)
    removeBtn:SetSize(16, 16)
    removeBtn:SetPoint("RIGHT", -4, 0)
    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    row.removeBtn = removeBtn

    row:Hide()
    return row
end

-- Only one row can be mid-rename at a time - entering rename mode on one row
-- always exits it on every other, so there's never a stray open edit box
-- left behind from switching straight to a different row's Rename button.
local function ExitRenameMode(row)
    row.nameBox:Hide()
    row.nameBox:ClearFocus()
    row.nameText:Show()
end

local function ExitAllRenameModes()
    for _, r in ipairs(sessionsFrame.rows) do
        if r.nameBox:IsShown() then
            ExitRenameMode(r)
        end
    end
end

local function EnterRenameMode(row, s)
    ExitAllRenameModes()
    row.nameText:Hide()
    row.nameBox:SetText(s.name)
    row.nameBox:Show()
    row.nameBox:SetFocus()
    row.nameBox:HighlightText()
end

local function RefreshSessionsList()
    local sessions = addon:GetNamedSessions()

    while #sessionsFrame.rows < #sessions do
        table.insert(sessionsFrame.rows, CreateSessionRow(sessionsScrollChild))
    end

    local yOffset = 0
    for i, row in ipairs(sessionsFrame.rows) do
        if i <= #sessions then
            local s = sessions[i]

            row.nameText:SetText(s.name)
            ExitRenameMode(row)  -- every refresh starts back in fixed/display mode

            row.renameBtn:SetScript("OnClick", function()
                EnterRenameMode(row, s)
            end)

            row.nameBox:SetScript("OnEnterPressed", function(self)
                local newName = self:GetText()
                if addon:RenameNamedSession(s.id, newName) then
                    RefreshSessionsList()
                    addon:RefreshSummaryDisplay()
                else
                    -- Rejected (empty/whitespace-only) - revert the box to the
                    -- real stored name, so what's displayed never drifts from
                    -- what's actually saved.
                    self:SetText(s.name)
                    ExitRenameMode(row)
                end
                self:ClearFocus()
            end)
            row.nameBox:SetScript("OnEscapePressed", function(self)
                self:SetText(s.name)
                ExitRenameMode(row)
                self:ClearFocus()
            end)

            if s.active then
                row.toggleBtn.text:SetText("|cff40ff40Active|r")
            else
                row.toggleBtn.text:SetText("|cff999999Paused|r")
            end
            row.toggleBtn:SetScript("OnClick", function()
                addon:SetNamedSessionActive(s.id, not s.active)
                RefreshSessionsList()
                addon:RefreshSummaryDisplay()
            end)

            local entryCount = #addon:GetNamedSessionLoot(s.id)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.name, 1, 1, 1)
                GameTooltip:AddLine(entryCount .. " item(s) tagged so far.", 0.7, 0.7, 0.7)
                GameTooltip:AddLine(s.active and "Currently active - new loot is being tagged." or "Paused - not tagging new loot. Click Paused to resume.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            row.removeBtn:SetScript("OnClick", function()
                StaticPopup_Show("RAIDLOOTTRACKER_DELETE_SESSION_CONFIRM", s.name, nil,
                    { id = s.id, refresh = RefreshSessionsList })
            end)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -yOffset)
            row:SetPoint("RIGHT", 0, 0)
            row:Show()
            yOffset = yOffset + 26
        else
            row:Hide()
        end
    end
    sessionsScrollChild:SetHeight(math.max(1, yOffset))
end
sessionsFrame.RefreshList = RefreshSessionsList

sessionCreateBtn:SetScript("OnClick", function()
    local name = sessionNameInput:GetText()
    if addon:CreateNamedSession(name) then
        sessionNameInput:SetText("")
        sessionNameInput:ClearFocus()
        RefreshSessionsList()
    else
        print("|cffffd100RaidLootTracker:|r Please enter a session name.")
    end
end)

local sessionsCloseBtn = CreateStyledButton(sessionsFrame, "Close", 80, 26)
sessionsCloseBtn:SetPoint("BOTTOM", 0, 12)
sessionsCloseBtn:SetScript("OnClick", function()
    sessionsFrame:Hide()
end)

function addon:ShowSessionsDialog()
    sessionsFrame.nameInput:SetText("")
    RefreshSessionsList()
    sessionsFrame:Show()
end

-- ============================================================================
-- MANUAL ENTRY DIALOG
-- ============================================================================

local manualFrame = CreateStyledFrame("RaidLootTrackerManualFrame", UIParent, 300, 285, "Add Loot Entry")
manualFrame:SetFrameStrata("DIALOG")
addon.manualFrame = manualFrame
manualFrame.rollData = nil  -- Stores {winning = {player, roll}, runnerUps = {{player, roll}, ...}}

-- Item link input
local itemLabel = manualFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
itemLabel:SetPoint("TOPLEFT", 15, -45)
itemLabel:SetText("Item (Shift-click):")
itemLabel:SetTextColor(0.7, 0.7, 0.7)

local itemInput = CreateFrame("EditBox", nil, manualFrame, "InputBoxTemplate")
itemInput:SetSize(170, 20)
itemInput:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
itemInput:SetAutoFocus(false)
manualFrame.itemInput = itemInput

-- Player dropdown
local playerLabel = manualFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
playerLabel:SetPoint("TOPLEFT", 15, -80)
playerLabel:SetText("Player:")
playerLabel:SetTextColor(0.7, 0.7, 0.7)

local manualPlayerDropdown = CreateFrame("Frame", "RaidLootTrackerManualPlayerDropdown", manualFrame, "UIDropDownMenuTemplate")
manualPlayerDropdown:SetPoint("LEFT", playerLabel, "RIGHT", -10, -2)
UIDropDownMenu_SetWidth(manualPlayerDropdown, 150)
manualFrame.playerDropdown = manualPlayerDropdown

-- Boss input
local bossLabel = manualFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bossLabel:SetPoint("TOPLEFT", 15, -115)
bossLabel:SetText("Boss:")
bossLabel:SetTextColor(0.7, 0.7, 0.7)

local bossInput = CreateFrame("EditBox", nil, manualFrame, "InputBoxTemplate")
bossInput:SetSize(170, 20)
bossInput:SetPoint("LEFT", bossLabel, "RIGHT", 10, 0)
bossInput:SetAutoFocus(false)
manualFrame.bossInput = bossInput

-- Difficulty dropdown - pre-filled with a live guess (see ShowManualEntryDialog)
-- but always overridable, since the live guess can be wrong if you're not
-- currently standing in the raid the item actually came from.
local difficultyLabel = manualFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
difficultyLabel:SetPoint("TOPLEFT", 15, -150)
difficultyLabel:SetText("Difficulty:")
difficultyLabel:SetTextColor(0.7, 0.7, 0.7)

local manualDifficultyDropdown = CreateFrame("Frame", "RaidLootTrackerManualDifficultyDropdown", manualFrame, "UIDropDownMenuTemplate")
manualDifficultyDropdown:SetPoint("LEFT", difficultyLabel, "RIGHT", -10, -2)
UIDropDownMenu_SetWidth(manualDifficultyDropdown, 100)
manualFrame.difficultyDropdown = manualDifficultyDropdown

-- Add Rolls button
local addRollsBtn = CreateStyledButton(manualFrame, "Add Rolls", 90, 24)
addRollsBtn:SetPoint("TOPLEFT", 15, -185)
addRollsBtn:SetScript("OnClick", function()
    addon:ShowRollEntryDialog()
end)

-- Roll status label
local rollStatusLabel = manualFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rollStatusLabel:SetPoint("LEFT", addRollsBtn, "RIGHT", 10, 0)
rollStatusLabel:SetText("|cff999999No rolls added|r")
rollStatusLabel:SetTextColor(0.6, 0.6, 0.6)
manualFrame.rollStatusLabel = rollStatusLabel

-- Buttons
local manualAddBtn = CreateStyledButton(manualFrame, "Add", 80, 26)
manualAddBtn:SetPoint("BOTTOMLEFT", 40, 12)
manualAddBtn:SetScript("OnClick", function()
    local itemLink = manualFrame.itemInput:GetText()
    local player = manualFrame.selectedPlayer
    local boss = manualFrame.bossInput:GetText()

    if not itemLink or itemLink == "" then
        print("|cffffd100RaidLootTracker:|r Please enter an item link (Shift-click an item)")
        return
    end

    if not player then
        print("|cffffd100RaidLootTracker:|r Please select a player")
        return
    end

    -- Prepare roll data
    local winningRoll, runnerUps = nil, {}
    if manualFrame.rollData then
        winningRoll = manualFrame.rollData.winning
        runnerUps = manualFrame.rollData.runnerUps or {}
    end

    addon:AddLootEntry(itemLink, player, boss ~= "" and boss or nil, nil,
                        winningRoll, runnerUps, nil, manualFrame.selectedDifficulty)
    manualFrame:Hide()
end)

local manualCancelBtn = CreateStyledButton(manualFrame, "Cancel", 80, 26)
manualCancelBtn:SetPoint("BOTTOMRIGHT", -40, 12)
manualCancelBtn:SetScript("OnClick", function()
    manualFrame:Hide()
end)

-- Allow shift-click to insert item
itemInput:SetScript("OnReceiveDrag", function(self)
    local infoType, itemID = GetCursorInfo()
    if infoType == "item" then
        local itemLink = select(2, GetItemInfo(itemID))
        if itemLink then
            self:SetText(itemLink)
        end
    end
    ClearCursor()
end)

manualFrame.selectedPlayer = nil
manualFrame.selectedDifficulty = nil

-- Show manual entry dialog
function addon:ShowManualEntryDialog()
    manualFrame.itemInput:SetText("")
    manualFrame.bossInput:SetText(self.currentBoss or "")
    manualFrame.selectedPlayer = nil
    manualFrame.rollData = nil
    manualFrame.rollStatusLabel:SetText("|cff999999No rolls added|r")

    -- Setup player dropdown
    local roster = self:GetReassignCandidates()
    UIDropDownMenu_Initialize(manualPlayerDropdown, function(_, level)
        for _, name in ipairs(roster) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                manualFrame.selectedPlayer = btn.value
                UIDropDownMenu_SetText(manualPlayerDropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(manualPlayerDropdown, "Select player...")

    -- Setup difficulty dropdown, pre-selected from the player's actual current
    -- instance if they're standing in one; always overridable either way.
    local _, liveDifficulty = self:GetLiveInstanceContext()
    manualFrame.selectedDifficulty = liveDifficulty
    UIDropDownMenu_Initialize(manualDifficultyDropdown, function(_, level)
        for _, tier in ipairs(DIFFICULTY_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            local color = DIFFICULTY_COLORS[tier] or "|cffaaaaaa"
            info.text = color .. DIFFICULTY_LABELS[tier] .. "|r"
            info.value = tier
            info.func = function(btn)
                manualFrame.selectedDifficulty = { name = DIFFICULTY_LABELS[btn.value], abbr = btn.value }
                UIDropDownMenu_SetText(manualDifficultyDropdown,
                    (DIFFICULTY_COLORS[btn.value] or "|cffaaaaaa") .. DIFFICULTY_LABELS[btn.value] .. "|r")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if liveDifficulty then
        UIDropDownMenu_SetText(manualDifficultyDropdown,
            (DIFFICULTY_COLORS[liveDifficulty.abbr] or "|cffaaaaaa") .. liveDifficulty.name .. "|r")
    else
        UIDropDownMenu_SetText(manualDifficultyDropdown, "Select...")
    end

    manualFrame:Show()
    manualFrame.itemInput:SetFocus()
end

-- Capture shift-clicked item links from bags into the item input box.
-- HandleModifiedItemClick is called when shift-clicking bag items; ChatEdit_InsertLink
-- is called when shift-clicking item links in the chat frame. Both paths are hooked so
-- that either source works while the manual entry dialog is open.
hooksecurefunc("HandleModifiedItemClick", function(link)
    if manualFrame:IsShown() and link then
        manualFrame.itemInput:SetText(link)
    end
end)

hooksecurefunc("ChatEdit_InsertLink", function(link)
    if manualFrame:IsShown() and link then
        manualFrame.itemInput:SetText(link)
    end
end)

-- ============================================================================
-- ROLL ENTRY DIALOG
-- ============================================================================

local rollEntryFrame = CreateStyledFrame("RaidLootTrackerRollEntryFrame", UIParent, 320, 300, "Add Roll Data")
rollEntryFrame:SetFrameStrata("DIALOG")
addon.rollEntryFrame = rollEntryFrame

local rollInfo = rollEntryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rollInfo:SetPoint("TOPLEFT", 15, -45)
rollInfo:SetText("Enter winning roll and up to 2 runner-ups:")
rollInfo:SetTextColor(0.7, 0.7, 0.7)

-- Winning roll
local winLabel = rollEntryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
winLabel:SetPoint("TOPLEFT", 15, -70)
winLabel:SetText("|cff00ff00Winner:|r")

local winPlayerDropdown = CreateFrame("Frame", "RaidLootTrackerWinPlayerDropdown", rollEntryFrame, "UIDropDownMenuTemplate")
winPlayerDropdown:SetPoint("TOPLEFT", 15, -85)
UIDropDownMenu_SetWidth(winPlayerDropdown, 120)
rollEntryFrame.winPlayerDropdown = winPlayerDropdown

local winRollInput = CreateFrame("EditBox", nil, rollEntryFrame, "InputBoxTemplate")
winRollInput:SetSize(50, 20)
winRollInput:SetPoint("LEFT", winPlayerDropdown, "RIGHT", 10, 2)
winRollInput:SetAutoFocus(false)
winRollInput:SetMaxLetters(3)
winRollInput:SetNumeric(true)
rollEntryFrame.winRollInput = winRollInput

-- Runner up 1
local ru1Label = rollEntryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ru1Label:SetPoint("TOPLEFT", 15, -130)
ru1Label:SetText("Runner-up 1:")

local ru1PlayerDropdown = CreateFrame("Frame", "RaidLootTrackerRU1PlayerDropdown", rollEntryFrame, "UIDropDownMenuTemplate")
ru1PlayerDropdown:SetPoint("TOPLEFT", 15, -145)
UIDropDownMenu_SetWidth(ru1PlayerDropdown, 120)
rollEntryFrame.ru1PlayerDropdown = ru1PlayerDropdown

local ru1RollInput = CreateFrame("EditBox", nil, rollEntryFrame, "InputBoxTemplate")
ru1RollInput:SetSize(50, 20)
ru1RollInput:SetPoint("LEFT", ru1PlayerDropdown, "RIGHT", 10, 2)
ru1RollInput:SetAutoFocus(false)
ru1RollInput:SetMaxLetters(3)
ru1RollInput:SetNumeric(true)
rollEntryFrame.ru1RollInput = ru1RollInput

-- Runner up 2
local ru2Label = rollEntryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ru2Label:SetPoint("TOPLEFT", 15, -190)
ru2Label:SetText("Runner-up 2:")

local ru2PlayerDropdown = CreateFrame("Frame", "RaidLootTrackerRU2PlayerDropdown", rollEntryFrame, "UIDropDownMenuTemplate")
ru2PlayerDropdown:SetPoint("TOPLEFT", 15, -205)
UIDropDownMenu_SetWidth(ru2PlayerDropdown, 120)
rollEntryFrame.ru2PlayerDropdown = ru2PlayerDropdown

local ru2RollInput = CreateFrame("EditBox", nil, rollEntryFrame, "InputBoxTemplate")
ru2RollInput:SetSize(50, 20)
ru2RollInput:SetPoint("LEFT", ru2PlayerDropdown, "RIGHT", 10, 2)
ru2RollInput:SetAutoFocus(false)
ru2RollInput:SetMaxLetters(3)
ru2RollInput:SetNumeric(true)
rollEntryFrame.ru2RollInput = ru2RollInput

-- Save and Cancel buttons
local rollSaveBtn = CreateStyledButton(rollEntryFrame, "Save", 80, 26)
rollSaveBtn:SetPoint("BOTTOMLEFT", 40, 12)
rollSaveBtn:SetScript("OnClick", function()
    local winRoll = tonumber(rollEntryFrame.winRollInput:GetText())
    local ru1Roll = tonumber(rollEntryFrame.ru1RollInput:GetText())
    local ru2Roll = tonumber(rollEntryFrame.ru2RollInput:GetText())

    if not rollEntryFrame.winPlayer or not winRoll then
        print("|cffffd100RaidLootTracker:|r Winner and winning roll are required")
        return
    end

    local rollData = {
        winning = {player = rollEntryFrame.winPlayer, roll = winRoll},
        runnerUps = {}
    }

    if rollEntryFrame.ru1Player and ru1Roll then
        table.insert(rollData.runnerUps, {player = rollEntryFrame.ru1Player, roll = ru1Roll})
    end

    if rollEntryFrame.ru2Player and ru2Roll then
        table.insert(rollData.runnerUps, {player = rollEntryFrame.ru2Player, roll = ru2Roll})
    end

    manualFrame.rollData = rollData

    -- Update status label
    local statusText = string.format("|cff00ff00Winner: %s (%d)|r", rollData.winning.player, rollData.winning.roll)
    if #rollData.runnerUps > 0 then
        statusText = statusText .. string.format(" +%d runner-up%s", #rollData.runnerUps, #rollData.runnerUps > 1 and "s" or "")
    end
    manualFrame.rollStatusLabel:SetText(statusText)

    rollEntryFrame:Hide()
end)

local rollCancelBtn = CreateStyledButton(rollEntryFrame, "Cancel", 80, 26)
rollCancelBtn:SetPoint("BOTTOMRIGHT", -40, 12)
rollCancelBtn:SetScript("OnClick", function()
    rollEntryFrame:Hide()
end)

rollEntryFrame.winPlayer = nil
rollEntryFrame.ru1Player = nil
rollEntryFrame.ru2Player = nil

-- Show roll entry dialog
function addon:ShowRollEntryDialog()
    rollEntryFrame.winPlayer = nil
    rollEntryFrame.ru1Player = nil
    rollEntryFrame.ru2Player = nil
    rollEntryFrame.winRollInput:SetText("")
    rollEntryFrame.ru1RollInput:SetText("")
    rollEntryFrame.ru2RollInput:SetText("")

    local roster = self:GetReassignCandidates()

    -- Setup winner dropdown
    UIDropDownMenu_Initialize(winPlayerDropdown, function(_, level)
        for _, name in ipairs(roster) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                rollEntryFrame.winPlayer = btn.value
                UIDropDownMenu_SetText(winPlayerDropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(winPlayerDropdown, "Select...")

    -- Setup runner-up 1 dropdown
    UIDropDownMenu_Initialize(ru1PlayerDropdown, function(_, level)
        for _, name in ipairs(roster) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                rollEntryFrame.ru1Player = btn.value
                UIDropDownMenu_SetText(ru1PlayerDropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(ru1PlayerDropdown, "Select...")

    -- Setup runner-up 2 dropdown
    UIDropDownMenu_Initialize(ru2PlayerDropdown, function(_, level)
        for _, name in ipairs(roster) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:ColorPlayerName(name)
            info.value = name
            info.func = function(btn)
                rollEntryFrame.ru2Player = btn.value
                UIDropDownMenu_SetText(ru2PlayerDropdown, addon:ColorPlayerName(btn.value))
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(ru2PlayerDropdown, "Select...")

    rollEntryFrame:Show()
end

-- ============================================================================
-- EXPORT DIALOG
-- ============================================================================
-- WoW addons can't write files to disk directly (the only file-write path is
-- SavedVariables, dumped on logout/reload). So, matching how RCLootCouncil and
-- Gargul handle export, this shows text in a selectable box for the player to
-- Ctrl+A/Ctrl+C and paste into Excel/Google Sheets themselves.
--
-- Tab-separated (TSV), not comma-separated: pasting plain comma-separated
-- text into Sheets/Excel does NOT auto-split into columns (it lands as one
-- literal string per cell, which can look right until you click a cell and
-- find it empty - the text was just overflowing visually from its neighbour).
-- Tab-separated text is the format both apps auto-split on a normal paste.

local exportFrame = CreateStyledFrame("RaidLootTrackerExportFrame", UIParent, 520, 434, "Export Loot (TSV)")
exportFrame:SetFrameStrata("DIALOG")
addon.exportFrame = exportFrame

-- Scope toggle: "Current Session" (default - matches the more common
-- per-raid-night export workflow), "Full History" (everything ever tracked,
-- regardless of session boundary - matches how RCLootCouncil and Gargul
-- default to exporting all-time history rather than just a session), or one
-- specific optional Named Session (see the Named Sessions dialog).
local exportSessionBtn = CreateStyledButton(exportFrame, "Current Session", 130, 22)
exportSessionBtn:SetPoint("TOP", exportFrame.header, "BOTTOM", -138, -10)

local exportFullBtn = CreateStyledButton(exportFrame, "Full History", 130, 22)
exportFullBtn:SetPoint("LEFT", exportSessionBtn, "RIGHT", 8, 0)

local exportNamedBtn = CreateStyledButton(exportFrame, "Named Session", 130, 22)
exportNamedBtn:SetPoint("LEFT", exportFullBtn, "RIGHT", 8, 0)

-- Only relevant/shown in "named" mode - picks which named session to export.
local exportSessionDropdown = CreateFrame("Frame", "RaidLootTrackerExportSessionDropdown", exportFrame, "UIDropDownMenuTemplate")
exportSessionDropdown:SetPoint("TOP", exportFrame, "TOP", 0, -80)
UIDropDownMenu_SetWidth(exportSessionDropdown, 180)
exportFrame.sessionDropdown = exportSessionDropdown

-- Anchored to exportFrame itself (the window's true horizontal center), NOT
-- to exportSessionBtn - that button sits left-of-center to make room for
-- Full History beside it, so anchoring text to it centers the text on the
-- BUTTON PAIR, not the window. Invisible with short text, but the longer
-- note line below actually spilled past the left window edge as a result
-- (confirmed via an in-game screenshot). -115 leaves room below the button
-- row and the named-session dropdown added above it.
local exportHint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportHint:SetPoint("TOP", exportFrame, "TOP", 0, -125)
exportHint:SetWidth(480)
exportHint:SetJustifyH("CENTER")
exportHint:SetTextColor(0.7, 0.7, 0.7)

-- Static (not scope-dependent) clarification, added after a real user
-- assumed the "Runner-ups shown" setting was broken because they counted more
-- names in their export than the setting said they should see - Export was
-- never capped by that setting (by design, it's meant to be a complete
-- record), but that was never stated anywhere the user would actually see it.
local exportNote = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportNote:SetPoint("TOP", exportHint, "BOTTOM", 0, -2)
exportNote:SetWidth(480)
exportNote:SetJustifyH("CENTER")
exportNote:SetTextColor(0.5, 0.5, 0.5)
exportNote:SetText("Includes every runner-up captured, regardless of the \"Runner-ups shown\" setting.")

-- Scrollable, multi-line text box holding the TSV. It's a real EditBox (not
-- locked read-only) so the OS text-selection/copy shortcuts work on it, same
-- as other addons' export boxes; nothing ever reads its contents back in.
local exportScroll = CreateFrame("ScrollFrame", "RaidLootTrackerExportScroll", exportFrame, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", 15, -166)
exportScroll:SetPoint("BOTTOMRIGHT", -30, 45)

local exportEditBox = CreateFrame("EditBox", nil, exportScroll)
exportEditBox:SetMultiLine(true)
exportEditBox:SetFontObject(ChatFontNormal)
exportEditBox:SetWidth(465)
exportEditBox:SetAutoFocus(false)
exportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
exportScroll:SetScrollChild(exportEditBox)
exportFrame.editBox = exportEditBox

local exportCloseBtn = CreateStyledButton(exportFrame, "Close", 80, 26)
exportCloseBtn:SetPoint("BOTTOM", 0, 12)
exportCloseBtn:SetScript("OnClick", function()
    exportFrame:Hide()
end)

-- Repopulate the edit box for whichever scope is currently selected, and
-- update the toggle buttons' visuals + hint text to match.
local function RefreshExportContent()
    local mode = exportFrame.mode
    local tsv
    if mode == "named" then
        tsv = exportFrame.selectedNamedSessionId and addon:BuildNamedSessionExportTSV(exportFrame.selectedNamedSessionId) or ""
    elseif mode == "full" then
        tsv = addon:BuildFullHistoryExportTSV()
    else
        tsv = addon:BuildSessionExportTSV()
    end
    exportEditBox:SetText(tsv)

    -- Size the edit box to fit its content (~14px/line) so the scrollbar
    -- covers exactly the exported rows instead of a fixed guess.
    local _, lineBreaks = tsv:gsub("\n", "\n")
    exportEditBox:SetHeight(math.max(260, (lineBreaks + 2) * 14))

    if mode == "named" then
        exportHint:SetText(exportFrame.selectedNamedSessionId
            and "Named session's tagged loot - Ctrl+C to copy, then paste into a spreadsheet."
            or "Pick a named session above to export.")
    elseif mode == "full" then
        exportHint:SetText("All loot ever tracked - Ctrl+C to copy, then paste into a spreadsheet.")
    else
        exportHint:SetText("Current session's loot - Ctrl+C to copy, then paste into a spreadsheet.")
    end

    -- Active toggle gets a gold border+text; the inactive ones fall back to
    -- CreateStyledButton's normal look.
    exportSessionBtn:SetBackdropBorderColor(unpack(mode == "session" and COLORS.gold or COLORS.border))
    exportSessionBtn.text:SetTextColor(unpack(mode == "session" and COLORS.gold or { 1, 1, 1, 1 }))
    exportFullBtn:SetBackdropBorderColor(unpack(mode == "full" and COLORS.gold or COLORS.border))
    exportFullBtn.text:SetTextColor(unpack(mode == "full" and COLORS.gold or { 1, 1, 1, 1 }))
    exportNamedBtn:SetBackdropBorderColor(unpack(mode == "named" and COLORS.gold or COLORS.border))
    exportNamedBtn.text:SetTextColor(unpack(mode == "named" and COLORS.gold or { 1, 1, 1, 1 }))

    if mode == "named" then
        exportSessionDropdown:Show()
    else
        exportSessionDropdown:Hide()
    end

    exportEditBox:SetFocus()
    exportEditBox:HighlightText()
end

-- Populate the named-session dropdown - lists every named session (active or
-- paused, all eligible to export), most recently created first.
local function PopulateExportSessionDropdown()
    local sessions = addon:GetNamedSessions()
    UIDropDownMenu_Initialize(exportSessionDropdown, function(_, level)
        for i = #sessions, 1, -1 do
            local s = sessions[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = s.name
            info.value = s.id
            info.func = function(btn)
                exportFrame.selectedNamedSessionId = btn.value
                UIDropDownMenu_SetText(exportSessionDropdown, s.name)
                RefreshExportContent()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

exportSessionBtn:SetScript("OnClick", function()
    exportFrame.mode = "session"
    RefreshExportContent()
end)
exportFullBtn:SetScript("OnClick", function()
    exportFrame.mode = "full"
    RefreshExportContent()
end)
exportNamedBtn:SetScript("OnClick", function()
    local sessions = addon:GetNamedSessions()
    if #sessions == 0 then
        -- Same reasoning as the Summary window's Named button: a chat print
        -- alone reads as "nothing happened," so open the real dialog too.
        print("|cffffd100RaidLootTracker:|r No named sessions yet - create one below.")
        addon:ShowSessionsDialog()
        return
    end
    exportFrame.mode = "named"
    if not exportFrame.selectedNamedSessionId then
        -- Default to the most recently created one
        local latest = sessions[#sessions]
        exportFrame.selectedNamedSessionId = latest.id
        UIDropDownMenu_SetText(exportSessionDropdown, latest.name)
    end
    RefreshExportContent()
end)

-- Show the export dialog, populated with the current session's loot as TSV
-- (the default scope - full history and named sessions are one click away
-- via the toggle above).
function addon:ShowExportDialog()
    exportFrame.mode = "session"
    exportFrame.selectedNamedSessionId = nil
    UIDropDownMenu_SetText(exportSessionDropdown, "Select session...")
    PopulateExportSessionDropdown()
    exportFrame:Show()
    RefreshExportContent()
end

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local minimapButton = CreateFrame("Button", "RaidLootTrackerMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:EnableMouse(true)
minimapButton:SetMovable(true)
minimapButton:RegisterForDrag("LeftButton")
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Border (draw first, as background)
local minimapBorder = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapBorder:SetSize(52, 52)
minimapBorder:SetPoint("TOPLEFT")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Icon (draw on top of border)
local minimapIcon = minimapButton:CreateTexture(nil, "OVERLAY")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("TOPLEFT", 6, -5)
minimapIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Blue")
-- Crop the icon's corners: item icons are square, but the border ring's
-- hole is round, so an uncropped icon's corners poke out past the ring
-- (the exact bug reported - "gold ring but the bag icon square is outside
-- the ring"). Standard fix used by every minimap-button addon: shrink the
-- visible texture coordinates in from each edge.
minimapIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Highlight
local minimapHighlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
minimapHighlight:SetSize(24, 24)
minimapHighlight:SetPoint("CENTER")
minimapHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
minimapHighlight:SetBlendMode("ADD")

-- Position around minimap
local function UpdateMinimapButtonPosition()
    local angle = math.rad(RaidLootTrackerDB.settings.minimapIcon.minimapPos or 220)
    -- Position on the outer ring - use GetWidth() to dynamically get minimap size
    local minimapSize = Minimap:GetWidth()
    local radius = (minimapSize / 2) + 8  -- Add 8 pixels to place in outer decorative ring
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Dragging
local isDragging = false
minimapButton:SetScript("OnDragStart", function(self)
    isDragging = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local angle = math.atan2(cy - my, cx - mx)
        RaidLootTrackerDB.settings.minimapIcon.minimapPos = math.deg(angle)
        UpdateMinimapButtonPosition()
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    isDragging = false
    self:SetScript("OnUpdate", nil)
end)

-- Click handlers
minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        addon:ToggleMainWindow()
    elseif button == "RightButton" then
        addon:ToggleSummaryWindow()
    end
end)

-- Tooltip
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Raid Loot Tracker", 1, 0.82, 0)
    GameTooltip:AddLine(" ")

    local count = #RaidLootTrackerDB.lootLog
    GameTooltip:AddLine("Tracking " .. count .. " item" .. (count ~= 1 and "s" or ""), 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Left-click:|r Open loot window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("|cff00ff00Right-click:|r Open summary", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("|cff00ff00Drag:|r Move button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Initialize button position when DB is ready
local buttonInit = CreateFrame("Frame")
buttonInit:RegisterEvent("PLAYER_LOGIN")
buttonInit:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        if RaidLootTrackerDB and RaidLootTrackerDB.settings then
            UpdateMinimapButtonPosition()
            if RaidLootTrackerDB.settings.minimapIcon.hide then
                minimapButton:Hide()
            else
                minimapButton:Show()
            end
        end
    end)
end)

-- ============================================================================
-- EASTER EGG - MOLE
-- ============================================================================

function addon:ShowMoleEasterEgg()
    -- Create popup frame if it doesn't exist
    if not self.moleFrame then
        local mole = CreateFrame("Frame", "RaidLootTrackerMoleFrame", UIParent, "BackdropTemplate")
        mole:SetSize(400, 400)
        mole:SetPoint("CENTER")
        mole:SetFrameStrata("TOOLTIP")
        mole:SetMovable(true)
        mole:EnableMouse(true)
        mole:RegisterForDrag("LeftButton")
        mole:SetScript("OnDragStart", mole.StartMoving)
        mole:SetScript("OnDragStop", mole.StopMovingOrSizing)

        -- Backdrop
        mole:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        mole:SetBackdropColor(0, 0, 0, 0.95)
        mole:SetBackdropBorderColor(0.8, 0.6, 0.4, 1)

        -- Mole image texture
        local moleTexture = mole:CreateTexture(nil, "ARTWORK")
        moleTexture:SetSize(380, 320)
        moleTexture:SetPoint("TOP", 0, -10)
        -- Image should be saved as Interface\AddOns\RaidLootTracker\mole.tga
        moleTexture:SetTexture("Interface\\AddOns\\RaidLootTracker\\mole")

        -- Text
        local moleText = mole:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        moleText:SetPoint("BOTTOM", 0, 40)
        moleText:SetText("|cffFFD700SURPRISE MOLE!|r")

        -- Close button
        local closeBtn = CreateStyledButton(mole, "Close", 80, 26)
        closeBtn:SetPoint("BOTTOM", 0, 10)
        closeBtn:SetScript("OnClick", function()
            mole:Hide()
        end)

        self.moleFrame = mole
    end

    self.moleFrame:Show()
end

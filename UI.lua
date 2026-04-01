-- RaidLootTracker - UI Components
-- Main loot window, summary window, dialogs, and minimap button

local addonName, addon = ...

-- UI Constants
local WINDOW_WIDTH = 550
local WINDOW_HEIGHT = 450
local SUMMARY_WIDTH = 320
local SUMMARY_HEIGHT = 400
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

-- Scroll frame for loot entries
local scrollFrame = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 8, -75)
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
    bossText:SetWidth(80)
    bossText:SetJustifyH("LEFT")
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

local resetBtn = CreateStyledButton(mainFrame, "Reset All", 80, 26)
resetBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
resetBtn:SetScript("OnClick", function()
    StaticPopup_Show("RAIDLOOTTRACKER_RESET_CONFIRM")
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

            -- Show original player if traded
            if entry.originalPlayer and entry.originalPlayer ~= entry.player then
                row.bossText:SetText(entry.boss .. " (was: " .. entry.originalPlayer .. ")")
            else
                row.bossText:SetText(entry.boss)
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

                -- Add top 2 runner-ups only
                if entry.runnerUps then
                    for i, runnerUp in ipairs(entry.runnerUps) do
                        if i > 2 then break end
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

-- Scroll frame
local summaryScroll = CreateFrame("ScrollFrame", nil, summaryFrame, "UIPanelScrollFrameTemplate")
summaryScroll:SetPoint("TOPLEFT", 8, -40)
summaryScroll:SetPoint("BOTTOMRIGHT", -28, 12)

local summaryScrollChild = CreateFrame("Frame", nil, summaryScroll)
summaryScrollChild:SetSize(SUMMARY_WIDTH - 40, 1)
summaryScroll:SetScrollChild(summaryScrollChild)
summaryFrame.scrollChild = summaryScrollChild

summaryFrame.rows = {}

-- Create a summary row
local function CreateSummaryRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 26)
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
        -- Show items tooltip
        if self.items and #self.items > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.playerName .. "'s Loot", 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            for _, item in ipairs(self.items) do
                GameTooltip:AddLine(item.itemLink)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if index % 2 == 0 then
            self:SetBackdropColor(unpack(COLORS.rowAlt))
        else
            self:SetBackdropColor(0, 0, 0, 0)
        end
        GameTooltip:Hide()
    end)

    -- Player name
    local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerText:SetPoint("LEFT", 10, 0)
    playerText:SetWidth(180)
    playerText:SetJustifyH("LEFT")
    row.playerText = playerText

    -- Count
    local countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("RIGHT", -10, 0)
    countText:SetTextColor(unpack(COLORS.gold))
    row.countText = countText

    row:Hide()
    return row
end

-- Refresh summary display
function addon:RefreshSummaryDisplay()
    local summary = self:GetPlayerSummary()

    -- Convert to array and sort by count
    local sorted = {}
    for player, data in pairs(summary) do
        table.insert(sorted, {
            player = player,
            count = data.count,
            items = data.items,
        })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    -- Ensure enough rows
    while #summaryFrame.rows < #sorted do
        local row = CreateSummaryRow(summaryFrame.scrollChild, #summaryFrame.rows + 1)
        table.insert(summaryFrame.rows, row)
    end

    -- Update scroll child height
    summaryFrame.scrollChild:SetHeight(math.max(1, #sorted * 26))

    -- Populate rows
    for i, row in ipairs(summaryFrame.rows) do
        if i <= #sorted then
            local data = sorted[i]
            row.playerName = data.player
            row.items = data.items

            row.playerText:SetText(addon:ColorPlayerName(data.player))
            row.countText:SetText(data.count .. " item" .. (data.count ~= 1 and "s" or ""))

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
            row:SetPoint("RIGHT", 0, 0)

            if i % 2 == 0 then
                row:SetBackdropColor(unpack(COLORS.rowAlt))
            else
                row:SetBackdropColor(0, 0, 0, 0)
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

-- Toggle summary window
function addon:ToggleSummaryWindow()
    if summaryFrame:IsShown() then
        summaryFrame:Hide()
    else
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

    -- Setup dropdown
    local roster = self:GetRaidRoster()
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
-- MANUAL ENTRY DIALOG
-- ============================================================================

local manualFrame = CreateStyledFrame("RaidLootTrackerManualFrame", UIParent, 300, 250, "Add Loot Entry")
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

-- Add Rolls button
local addRollsBtn = CreateStyledButton(manualFrame, "Add Rolls", 90, 24)
addRollsBtn:SetPoint("TOPLEFT", 15, -150)
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

    addon:AddLootEntry(itemLink, player, boss ~= "" and boss or nil, nil, winningRoll, runnerUps)
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

-- Show manual entry dialog
function addon:ShowManualEntryDialog()
    manualFrame.itemInput:SetText("")
    manualFrame.bossInput:SetText(self.currentBoss or "")
    manualFrame.selectedPlayer = nil
    manualFrame.rollData = nil
    manualFrame.rollStatusLabel:SetText("|cff999999No rolls added|r")

    -- Setup player dropdown
    local roster = self:GetRaidRoster()
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

    local roster = self:GetRaidRoster()

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

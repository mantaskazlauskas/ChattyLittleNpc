-- RaceModelManager.lua - Developer window for labeling unknown NPC race models
-- Pages through model file IDs that NpcRaceLookup could not resolve, renders
-- the NPC so it can be identified visually, and saves a hand-entered race.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Widgets = CLN.Widgets

---@class RaceModelManager
local RaceModelManager = {}
CLN.RaceModelManager = RaceModelManager

RaceModelManager.list = {}
RaceModelManager.index = 1
RaceModelManager.totalCount = 0 -- all recorded models, before filtering
RaceModelManager.query = ""     -- search text for the model list panel

local VIEWER_W = 380   -- left column: model viewer and labeling controls
local LIST_W   = 280   -- right column: searchable model list
local ROW_H    = 20

--- True when a model has neither a race nor a "not a race" mark.
local function isUnassigned(entry)
    return (not entry.race or entry.race == "") and not entry.ignored
end

--- Build the searchable list panel on the right side of the window.
local function createListPanel(f)
    local C = Widgets.Colors

    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", VIEWER_W, -36)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", panel, "TOPLEFT")
    divider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
    divider:SetColorTexture(Widgets.rgba(C.cardBorder))

    local search = Widgets.CreateEditBox(panel, LIST_W - 28, 24)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -10)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    placeholder:SetText("Search model ID, NPC, race…")
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        RaceModelManager.query = self:GetText() or ""
        RaceModelManager:RefreshList(true)
    end)
    -- Enter jumps to the first match.
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = RaceModelManager.filtered and RaceModelManager.filtered[1]
        if first then RaceModelManager:Select(first) end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- HookScript keeps the edit box's own hover highlight.
    search:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Search", 1, 1, 1)
        GameTooltip:AddLine("Matches model ID, NPC name, NPC ID or race. Enter selects the first match.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.search = search

    f.listCount = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.listCount:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -6)

    local sf, content = Widgets.CreateScrollFrame(panel)
    sf:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -24)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 12)
    content:SetWidth(LIST_W - 40)
    f.listScroll, f.listContent = sf, content
    f.listRows = {}

    f.listEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.listEmpty:SetPoint("TOP", content, "TOP", 0, -12)
    f.listEmpty:SetText("No matching models")
end

--- Pooled list row: model ID, NPC name, race / status.
local function getListRow(f, i)
    local row = f.listRows[i]
    if row then return row end
    local C = Widgets.Colors

    row = CreateFrame("Button", nil, f.listContent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", f.listContent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", f.listContent, "RIGHT", 0, 0)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    row.selected = row:CreateTexture(nil, "BORDER")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(Widgets.rgba(C.accentSoft))
    row.selBar = row:CreateTexture(nil, "ARTWORK")
    row.selBar:SetWidth(2)
    row.selBar:SetPoint("TOPLEFT")
    row.selBar:SetPoint("BOTTOMLEFT")
    row.selBar:SetColorTexture(Widgets.rgba(C.accent))
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)

    local function col(font, justify)
        local fs = row:CreateFontString(nil, "OVERLAY", font)
        fs:SetJustifyH(justify)
        fs:SetWordWrap(false)
        return fs
    end
    row.id = col("GameFontHighlightSmall", "LEFT")
    row.id:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.id:SetWidth(54)
    row.race = col("GameFontHighlightSmall", "RIGHT")
    row.race:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.race:SetWidth(72)
    row.name = col("GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("LEFT", row.id, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.race, "LEFT", -4, 0)

    row:SetScript("OnClick", function(self) RaceModelManager:Select(self.listIndex) end)
    f.listRows[i] = row
    return row
end

local function createFrame()
    local f = CreateFrame("Frame", "CLN_RaceModelManager", UIParent, "BackdropTemplate")
    f:SetSize(VIEWER_W + LIST_W, 572)
    Widgets.ApplyBackdrop(f, Widgets.Colors.windowBg, Widgets.Colors.windowBorder)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true) -- opens from the settings window, which shares this strata
    f:Hide()
    tinsert(UISpecialFrames, "CLN_RaceModelManager") -- close with Escape

    Widgets.CreateTitleBar(f, "Chatty Little NPC", { subtitle = "Race Models" })

    -- Left column holds the viewer; the list panel fills the rest.
    local viewer = CreateFrame("Frame", nil, f)
    viewer:SetPoint("TOPLEFT", f, "TOPLEFT")
    viewer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    viewer:SetWidth(VIEWER_W)

    -- Header: model file ID
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.header:SetPoint("TOP", viewer, "TOP", 0, -48)

    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.counter:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -14, -44)

    f.details = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.details:SetPoint("TOP", f.header, "BOTTOM", 0, -6)
    f.details:SetWidth(350)

    -- Model view (drag to rotate, mouse wheel to zoom)
    local modelBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    modelBg:SetPoint("TOPLEFT", viewer, "TOPLEFT", 14, -96)
    modelBg:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -14, -96)
    modelBg:SetHeight(330)
    modelBg:SetFrameLevel(f:GetFrameLevel() + 5)
    Widgets.ApplyBackdrop(modelBg, { 0, 0, 0, 0.5 }, Widgets.Colors.border)

    local model = CreateFrame("PlayerModel", nil, modelBg)
    model:SetAllPoints(modelBg)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.facing = 0
    model.zoom = 0
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) * 0.02
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0, math.min(0.9, self.zoom + delta * 0.1))
        self:SetPortraitZoom(self.zoom)
    end)
    f.model = model

    f.noModel = modelBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.noModel:SetPoint("CENTER", modelBg)
    f.noModel:SetText("No model to display")

    -- Race input
    f.raceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.raceLabel:SetPoint("TOPLEFT", modelBg, "BOTTOMLEFT", 2, -14)
    f.raceLabel:SetText("Race:")

    f.raceInput = Widgets.CreateEditBox(f)
    f.raceInput:SetSize(270, 22)
    f.raceInput:SetPoint("LEFT", f.raceLabel, "RIGHT", 12, 0)
    f.raceInput:SetAutoFocus(false)
    f.raceInput:SetScript("OnEnterPressed", function() RaceModelManager:SaveCurrent(true) end)
    f.raceInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Buttons
    local function button(text, width, onClick)
        local b = Widgets.CreateButton(f)
        b:SetSize(width, 24)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.prevButton = button("< Prev", 74, function() RaceModelManager:Step(-1) end)
    f.prevButton:SetPoint("TOPLEFT", f.raceLabel, "BOTTOMLEFT", -2, -16)

    f.saveButton = button("Save", 80, function() RaceModelManager:SaveCurrent(true) end)
    f.saveButton:SetPoint("LEFT", f.prevButton, "RIGHT", 8, 0)

    f.ignoreButton = button("Not a race", 100, function() RaceModelManager:ToggleIgnored() end)
    f.ignoreButton:SetPoint("LEFT", f.saveButton, "RIGHT", 8, 0)

    f.nextButton = button("Next >", 74, function() RaceModelManager:Step(1) end)
    f.nextButton:SetPoint("LEFT", f.ignoreButton, "RIGHT", 8, 0)

    f.unassignedOnly = Widgets.CreateCheckButton(f, "Only show unassigned models", "GameFontHighlightSmall")
    f.unassignedOnly:SetPoint("TOPLEFT", f.prevButton, "BOTTOMLEFT", 0, -10)
    f.unassignedOnly:SetScript("OnClick", function(self)
        RaceModelManager:SetUnassignedOnly(self:GetChecked())
    end)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", viewer, "BOTTOM", 0, 12)
    f.hint:SetText("Drag model to rotate, scroll to zoom. Enter saves and moves on.")

    createListPanel(f)
    return f
end

--- True when the model's ID, NPC name/ID or race contains the (lowercased) query.
local function matchesQuery(item, query)
    if query == "" then return true end
    local e = item.entry
    local haystack = table.concat({
        tostring(item.fileId), e.name or "", tostring(e.npcId or ""), e.race or "",
        e.ignored and "not a race" or "",
    }, "\n"):lower()
    return haystack:find(query, 1, true) ~= nil
end

--- Redraw the model list, keeping the current model in view.
--- resetScroll jumps to the top instead (used when the search text changes).
function RaceModelManager:RefreshList(resetScroll)
    local f = self.frame
    local query = strtrim(self.query or ""):lower()
    local filtered = {}
    for i, item in ipairs(self.list) do
        if matchesQuery(item, query) then filtered[#filtered + 1] = i end
    end
    self.filtered = filtered

    local C = Widgets.Colors
    local selectedPos
    for pos, listIndex in ipairs(filtered) do
        local item = self.list[listIndex]
        local e = item.entry
        local row = getListRow(f, pos)
        row.listIndex = listIndex
        row.id:SetText(item.fileId)
        row.name:SetText(e.name or "?")
        if e.ignored then
            row.race:SetText("not a race")
            row.race:SetTextColor(1, 0.5, 0.5)
        elseif e.race and e.race ~= "" then
            row.race:SetText(e.race)
            row.race:SetTextColor(0.5, 0.9, 0.5)
        else
            row.race:SetText("—")
            row.race:SetTextColor(Widgets.rgba(C.textMuted))
        end
        local isSelected = listIndex == self.index
        row.selected:SetShown(isSelected)
        row.selBar:SetShown(isSelected)
        if isSelected then selectedPos = pos end
        row:Show()
    end
    for i = #filtered + 1, #f.listRows do f.listRows[i]:Hide() end

    f.listEmpty:SetShown(#filtered == 0 and #self.list > 0)
    f.listCount:SetText(query == "" and (#self.list .. " models")
        or (#filtered .. " of " .. #self.list .. " models"))
    f.listContent:SetHeight(math.max(1, #filtered * ROW_H))

    -- Keep the selected row visible (or jump to the top after a new search).
    local sf = f.listScroll
    if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
    if resetScroll then
        sf.ScrollBar:SetValue(0)
    elseif selectedPos then
        local top, viewH = (selectedPos - 1) * ROW_H, sf:GetHeight()
        local cur = sf:GetVerticalScroll()
        if top < cur then
            sf.ScrollBar:SetValue(top)
        elseif top + ROW_H > cur + viewH then
            sf.ScrollBar:SetValue(top + ROW_H - viewH)
        end
    end
end

--- Jump to a model by its index in self.list.
function RaceModelManager:Select(listIndex)
    if not self.list[listIndex] then return end
    self.index = listIndex
    self:Refresh()
end

function RaceModelManager:Refresh()
    local f = self.frame
    local item = self.list[self.index]

    f.prevButton:SetEnabled(self.index > 1)
    f.nextButton:SetEnabled(self.index < #self.list)

    if not item then
        if self.totalCount and self.totalCount > 0 then
            f.header:SetText("All models assigned")
            f.details:SetText("Untick \"Only show unassigned models\" to review the " .. self.totalCount .. " labeled ones.")
        else
            f.header:SetText("No unknown models")
            f.details:SetText("Talk to NPCs with NPC text logging enabled to collect some.")
        end
        f.counter:SetText("")
        f.raceInput:SetText("")
        f.raceInput:Disable()
        f.saveButton:Disable()
        f.ignoreButton:Disable()
        f.model.renderToken = (f.model.renderToken or 0) + 1 -- cancel a pending fallback
        f.model:ClearModel()
        f.noModel:Show()
        self:RefreshList()
        return
    end

    local e = item.entry
    local labeled = 0
    for _, it in ipairs(self.list) do
        if not isUnassigned(it.entry) then labeled = labeled + 1 end
    end

    f.header:SetText("Model ID: " .. item.fileId)
    f.counter:SetText(self.index .. " / " .. #self.list .. "  (" .. labeled .. " done)")
    f.details:SetText(string.format("%s (NPC %s)  ·  Display %s  ·  %s  ·  seen %dx%s",
        e.name or "?", tostring(e.npcId or "?"), tostring(e.displayId or "?"),
        e.creatureType or "?", e.count or 0,
        e.ignored and "  ·  |cffff8080not a race|r" or ""))

    f.raceInput:Enable()
    f.saveButton:Enable()
    f.ignoreButton:Enable()
    f.raceInput:SetText(e.race or "")
    f.ignoreButton:SetText(e.ignored and "Restore" or "Not a race")

    local model = f.model
    model:ClearModel()
    model.facing, model.zoom = 0, 0
    model.renderToken = (model.renderToken or 0) + 1
    local renderPath
    if e.displayId then
        model:SetDisplayInfo(e.displayId)
        renderPath = "SetDisplayInfo(" .. e.displayId .. ")"
    elseif e.npcId and model.SetCreature and pcall(model.SetCreature, model, e.npcId) then
        -- No display ID captured: render by creature ID, textured if the client has it cached
        renderPath = "SetCreature(" .. e.npcId .. ")"
        -- SetCreature succeeds but draws nothing for creatures the client has
        -- not cached; fall back to the bare model file if nothing loaded.
        local token = model.renderToken
        C_Timer.After(0.5, function()
            if model.renderToken ~= token or not model.GetModelFileID then return end
            local loaded = model:GetModelFileID()
            if not loaded or loaded == 0 then
                model:SetModel(item.fileId)
                model:SetPortraitZoom(model.zoom)
                model:SetFacing(model.facing)
                if CLN.Logger then
                    CLN.Logger:debug("RaceModelManager render: SetCreature(" .. e.npcId .. ") loaded nothing, SetModel(" .. item.fileId .. ") - untextured", false, CLN.Utils.LogCategories.ui)
                end
            end
        end)
    else
        model:SetModel(item.fileId) -- last resort: bare model file, untextured
        renderPath = "SetModel(" .. item.fileId .. ") - untextured"
    end
    if CLN.Logger then
        CLN.Logger:debug("RaceModelManager render: " .. renderPath, false, CLN.Utils.LogCategories.ui)
    end
    model:SetPortraitZoom(0)
    model:SetFacing(0)
    f.noModel:Hide()
    self:RefreshList()
end

function RaceModelManager:Step(delta)
    self.index = math.max(1, math.min(#self.list, self.index + delta))
    self:Refresh()
end

--- Save the typed race for the current model. An empty box clears the label.
---@param advance boolean Move to the next entry after saving
function RaceModelManager:SaveCurrent(advance)
    local item = self.list[self.index]
    if not item then return end
    local race = strtrim(self.frame.raceInput:GetText() or "")
    item.entry.race = race
    if race ~= "" then item.entry.ignored = nil end
    self.frame.raceInput:ClearFocus()
    if CLN.Logger then
        CLN.Logger:info("Race model " .. item.fileId .. " = " .. (race ~= "" and race or "(cleared)"), true, CLN.Utils.LogCategories.ui)
    end
    if advance and self.index < #self.list then
        self:Step(1)
    else
        self:Refresh()
    end
end

function RaceModelManager:ToggleIgnored()
    local item = self.list[self.index]
    if not item then return end
    item.entry.ignored = (not item.entry.ignored) or nil
    if item.entry.ignored then item.entry.race = "" end
    if item.entry.ignored and self.index < #self.list then
        self:Step(1)
    else
        self:Refresh()
    end
end

--- Rebuild the list from the saved models, filtered by the checkbox. The list
--- is only rebuilt on open and on toggling the filter, so a model labeled
--- just now stays reachable with Prev for a correction.
function RaceModelManager:BuildList()
    local all = CLN.NpcRaceLookup and CLN.NpcRaceLookup:GetUnknownList() or {}
    self.totalCount = #all
    if CLN.db.profile.raceModelsUnassignedOnly == false then
        self.list = all
        return
    end
    self.list = {}
    for _, item in ipairs(all) do
        if isUnassigned(item.entry) then table.insert(self.list, item) end
    end
end

--- Index of the given model in the list, else the first one still needing a label.
function RaceModelManager:FindStartIndex(fileId)
    local firstUnassigned
    for i, item in ipairs(self.list) do
        if item.fileId == fileId then return i end
        if not firstUnassigned and isUnassigned(item.entry) then firstUnassigned = i end
    end
    return firstUnassigned or 1
end

function RaceModelManager:SetUnassignedOnly(enabled)
    local current = self.list[self.index]
    CLN.db.profile.raceModelsUnassignedOnly = enabled and true or false
    self:BuildList()
    self.index = self:FindStartIndex(current and current.fileId)
    self:Refresh()
end

function RaceModelManager:Show()
    self.frame = self.frame or createFrame()
    self.frame.unassignedOnly:SetChecked(CLN.db.profile.raceModelsUnassignedOnly ~= false)
    self:BuildList()
    self.index = self:FindStartIndex(nil)

    self.frame:Show()
    self.frame:Raise()
    self:Refresh()
end

function RaceModelManager:Hide()
    if self.frame then self.frame:Hide() end
end

function RaceModelManager:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

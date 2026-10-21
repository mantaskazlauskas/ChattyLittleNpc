-- ItemPropPicker.lua - Window (Display settings) for choosing the book / letter
-- / plaque models shown as the portrait for item text and object voiceovers.
-- Browse candidate models, tune pitch / facing / zoom, and assign one to a prop
-- slot. Saved picks override the defaults in ReplayFrame.ItemProps per profile
-- (reset per slot or all); the Lua line can be pasted into ModelFrame.lua to
-- make a pick the default.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Widgets = CLN.Widgets

---@class ItemPropPicker
local ItemPropPicker = {}
CLN.ItemPropPicker = ItemPropPicker

ItemPropPicker.list = {}      -- { fileId, path } from CLN.ItemPropCandidates
ItemPropPicker.index = nil    -- selected list index (nil for a typed-in file ID)
ItemPropPicker.query = ""
ItemPropPicker.slot = "book"
ItemPropPicker.fileId = nil
ItemPropPicker.pitch, ItemPropPicker.facing, ItemPropPicker.distance = 0, 0, 1

local VIEWER_W = 380
local LIST_W   = 320
local ROW_H    = 20

local SLOTS = {
    book   = "Book (several pages)",
    scroll = "Letter (one page)",
    stone  = "Stone / Marble plaque",
    bronze = "Bronze / Gold plaque",
    silver = "Silver plaque",
}
local SLOT_ORDER = { "book", "scroll", "stone", "bronze", "silver" }

local function round2(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

--- Draw the current model with the portrait's prop framing (see host:FrameProp).
local function applyFraming(model, p)
    pcall(model.SetPortraitZoom, model, 0)
    pcall(model.SetCamDistanceScale, model, p.distance)
    pcall(model.SetPosition, model, 0, 0, 0)
    pcall(model.SetFacing, model, p.facing)
    pcall(model.SetPitch, model, p.pitch)
end

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
    placeholder:SetText("Search file ID or path (book, scroll, paper…)")
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        ItemPropPicker.query = self:GetText() or ""
        ItemPropPicker:RefreshList(true)
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = ItemPropPicker.filtered and ItemPropPicker.filtered[1]
        if first then ItemPropPicker:Select(first) end
    end)
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

--- Pooled list row: file ID and model path.
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

    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.id:SetJustifyH("LEFT")
    row.id:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.id:SetWidth(58)
    row.path = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.path:SetJustifyH("LEFT")
    row.path:SetWordWrap(false)
    row.path:SetPoint("LEFT", row.id, "RIGHT", 4, 0)
    row.path:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row:SetScript("OnClick", function(self) ItemPropPicker:Select(self.listIndex) end)
    -- Long paths are cut off; show the full one on hover
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.fullPath or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.listRows[i] = row
    return row
end

--- Labeled slider writing to ItemPropPicker[field].
local function createSlider(f, anchor, label, field, minV, maxV, step)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    text:SetWidth(60)
    text:SetJustifyH("LEFT")
    text:SetText(label)

    local s = Widgets.CreateSlider(f)
    s:SetPoint("LEFT", text, "RIGHT", 8, 0)
    s:SetWidth(230)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)

    s.valueText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(self, value)
        value = round2(value)
        self.valueText:SetText(string.format("%.2f", value))
        if self._silent then return end
        ItemPropPicker[field] = value
        ItemPropPicker:ApplyFraming()
    end)
    s.label = text
    return s
end

local function createFrame()
    local f = CreateFrame("Frame", "CLN_ItemPropPicker", UIParent, "BackdropTemplate")
    f:SetSize(VIEWER_W + LIST_W, 600)
    Widgets.ApplyBackdrop(f, Widgets.Colors.windowBg, Widgets.Colors.windowBorder)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:Hide()
    tinsert(UISpecialFrames, "CLN_ItemPropPicker") -- close with Escape

    Widgets.CreateTitleBar(f, "Chatty Little NPC", { subtitle = "Item Prop Picker" })

    local viewer = CreateFrame("Frame", nil, f)
    viewer:SetPoint("TOPLEFT", f, "TOPLEFT")
    viewer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    viewer:SetWidth(VIEWER_W)

    -- Slot to edit; choosing one loads its current model
    f.slotLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.slotLabel:SetPoint("TOPLEFT", viewer, "TOPLEFT", 16, -52)
    f.slotLabel:SetText("Slot:")
    f.slot = Widgets.CreateDropdown(f, 200, {
        values = SLOTS,
        sorting = SLOT_ORDER,
        get = function() return ItemPropPicker.slot end,
        set = function(value) ItemPropPicker:SetSlot(value) end,
    })
    f.slot:SetPoint("LEFT", f.slotLabel, "RIGHT", 10, 0)
    f.slotState = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.slotState:SetPoint("LEFT", f.slot, "RIGHT", 8, 0)

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.header:SetPoint("TOP", viewer, "TOP", 0, -88)
    f.details = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.details:SetPoint("TOP", f.header, "BOTTOM", 0, -4)
    f.details:SetWidth(350)
    f.details:SetWordWrap(false)

    -- Model view: drag left/right turns, up/down tilts, wheel zooms
    local modelBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    modelBg:SetPoint("TOPLEFT", viewer, "TOPLEFT", 14, -126)
    modelBg:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", -14, -126)
    modelBg:SetHeight(220)
    modelBg:SetFrameLevel(f:GetFrameLevel() + 5)
    Widgets.ApplyBackdrop(modelBg, { 0, 0, 0, 0.5 }, Widgets.Colors.border)

    local model = CreateFrame("PlayerModel", nil, modelBg)
    model:SetAllPoints(modelBg)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX, self.dragY = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX, self.dragY = nil, nil end)
    -- Closing mid-drag never delivers OnMouseUp
    model:SetScript("OnHide", function(self) self.dragX, self.dragY = nil, nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x, y = GetCursorPosition()
        -- Wrap into -pi..pi to stay in the Facing slider's range
        ItemPropPicker.facing = (ItemPropPicker.facing + (x - self.dragX) * 0.02 + math.pi) % (2 * math.pi) - math.pi
        ItemPropPicker.pitch = math.max(-math.pi, math.min(math.pi, ItemPropPicker.pitch + (y - self.dragY) * 0.02))
        self.dragX, self.dragY = x, y
        ItemPropPicker:ApplyFraming(true)
    end)
    model:SetScript("OnMouseWheel", function(_, delta)
        ItemPropPicker.distance = math.max(0.1, math.min(3, ItemPropPicker.distance - delta * 0.05))
        ItemPropPicker:ApplyFraming(true)
    end)
    f.model = model

    f.noModel = modelBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.noModel:SetPoint("CENTER", modelBg)
    f.noModel:SetText("Pick a model from the list")

    f.pitchSlider = createSlider(f, modelBg, "Pitch", "pitch", -math.pi, math.pi, 0.05)
    f.facingSlider = createSlider(f, f.pitchSlider.label, "Facing", "facing", -math.pi, math.pi, 0.05)
    f.distanceSlider = createSlider(f, f.facingSlider.label, "Zoom", "distance", 0.1, 3, 0.05)
    f.pitchSlider.label:SetPoint("TOPLEFT", modelBg, "BOTTOMLEFT", 2, -14)

    -- Any file ID, for models not in the list
    f.idLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.idLabel:SetPoint("TOPLEFT", f.distanceSlider.label, "BOTTOMLEFT", 0, -18)
    f.idLabel:SetWidth(60)
    f.idLabel:SetJustifyH("LEFT")
    f.idLabel:SetText("File ID")
    f.idInput = Widgets.CreateEditBox(f, 110, 22)
    f.idInput:SetPoint("LEFT", f.idLabel, "RIGHT", 8, 0)
    f.idInput:SetNumeric(true)
    f.idInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ItemPropPicker:LoadFileId(tonumber(self:GetText()))
    end)

    f.prevButton = Widgets.CreateButton(f, "< Prev", 64, 22)
    f.prevButton:SetPoint("LEFT", f.idInput, "RIGHT", 8, 0)
    f.prevButton:SetScript("OnClick", function() ItemPropPicker:Step(-1) end)
    f.nextButton = Widgets.CreateButton(f, "Next >", 64, 22)
    f.nextButton:SetPoint("LEFT", f.prevButton, "RIGHT", 6, 0)
    f.nextButton:SetScript("OnClick", function() ItemPropPicker:Step(1) end)

    f.assignButton = Widgets.CreateButton(f, "Assign to slot", 120, 24)
    f.assignButton:SetPoint("TOPLEFT", f.idLabel, "BOTTOMLEFT", -2, -14)
    f.assignButton:SetScript("OnClick", function() ItemPropPicker:Assign() end)
    f.resetButton = Widgets.CreateButton(f, "Reset slot", 100, 24)
    f.resetButton:SetPoint("LEFT", f.assignButton, "RIGHT", 8, 0)
    f.resetButton:SetScript("OnClick", function() ItemPropPicker:ResetSlot() end)
    f.resetAllButton = Widgets.CreateButton(f, "Reset all", 90, 24)
    f.resetAllButton:SetPoint("LEFT", f.resetButton, "RIGHT", 8, 0)
    f.resetAllButton:SetScript("OnClick", function() StaticPopup_Show("CLN_RESET_ITEM_PROPS") end)

    -- Lua line for hardcoding the pick in ModelFrame.lua (click, Ctrl+C)
    f.luaLine = Widgets.CreateEditBox(f, VIEWER_W - 32, 22)
    f.luaLine:SetPoint("TOPLEFT", f.assignButton, "BOTTOMLEFT", 2, -12)
    f.luaLine:SetFontObject("GameFontHighlightSmall")
    f.luaLine:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.luaLine:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(ItemPropPicker:LuaLine()) self:HighlightText() end
    end)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", viewer, "BOTTOM", 0, 12)
    f.hint:SetText("Drag to turn and tilt, scroll to zoom. Assign updates the portrait.")

    createListPanel(f)
    return f
end

function ItemPropPicker:LuaLine()
    if not self.fileId then return "" end
    local parts = { "fileId = " .. self.fileId }
    if round2(self.pitch) ~= 0 then parts[#parts + 1] = string.format("pitch = %.2f", self.pitch) end
    if round2(self.facing) ~= 0 then parts[#parts + 1] = string.format("facing = %.2f", self.facing) end
    if round2(self.distance) ~= 1 then parts[#parts + 1] = string.format("distance = %.2f", self.distance) end
    return string.format("%s = { %s },", self.slot, table.concat(parts, ", "))
end

--- Path for a file ID if it is in the candidate list.
function ItemPropPicker:PathFor(fileId)
    for i, item in ipairs(self.list) do
        if item[1] == fileId then return item[2], i end
    end
end

--- Reframe the preview; fromMouse also moves the sliders to match.
function ItemPropPicker:ApplyFraming(fromMouse)
    local f = self.frame
    if not f then return end
    applyFraming(f.model, self)
    if fromMouse then self:SyncSliders() end
    f.luaLine:SetText(self:LuaLine())
    f.luaLine:SetCursorPosition(0) -- show the start (slot and file ID), not the tail
end

function ItemPropPicker:SyncSliders()
    local f = self.frame
    for slider, field in pairs({ [f.pitchSlider] = "pitch", [f.facingSlider] = "facing", [f.distanceSlider] = "distance" }) do
        slider._silent = true
        slider:SetValue(self[field])
        slider._silent = false
        -- The slider snaps to its step; label the real value that gets saved
        slider.valueText:SetText(string.format("%.2f", self[field]))
    end
end

--- Show a model by file ID, keeping the current pitch / facing / zoom.
function ItemPropPicker:LoadFileId(fileId)
    local f = self.frame
    if not fileId then return end
    local path, listIndex = self:PathFor(fileId)
    self.fileId = fileId
    self.index = listIndex
    f.model:ClearModel()
    f.model:SetModel(fileId)
    f.noModel:Hide()
    f.header:SetText("File ID: " .. fileId)
    f.details:SetText(path or "(not in the candidate list)")
    f.idInput:SetText(tostring(fileId))
    self:ApplyFraming()
    -- The model's camera can reset when it finishes loading
    C_Timer.After(0.1, function()
        if self.fileId == fileId then applyFraming(f.model, self) end
    end)
    self:RefreshButtons()
    self:RefreshList()
end

function ItemPropPicker:Select(listIndex)
    local item = self.list[listIndex]
    if item then self:LoadFileId(item[1]) end
end

function ItemPropPicker:Step(delta)
    local filtered = self.filtered or {}
    if #filtered == 0 then return end
    local pos = 0
    for i, listIndex in ipairs(filtered) do
        if listIndex == self.index then pos = i break end
    end
    pos = math.max(1, math.min(#filtered, pos + delta))
    self:Select(filtered[pos])
end

--- Load a slot's current prop (override or default) for editing.
function ItemPropPicker:SetSlot(key)
    self.slot = key
    local prop = CLN.ReplayFrame:GetItemProp(key)
    self.pitch = round2(prop.pitch or 0)
    self.facing = round2(prop.facing or 0)
    self.distance = round2(prop.distance or 1)
    self:SyncSliders()
    self:LoadFileId(prop.fileId)
end

function ItemPropPicker:Assign()
    if not self.fileId then return end
    local overrides = CLN.db.profile.itemPropOverrides or {}
    CLN.db.profile.itemPropOverrides = overrides
    overrides[self.slot] = {
        fileId = self.fileId,
        pitch = round2(self.pitch),
        facing = round2(self.facing),
        distance = round2(self.distance),
    }
    if CLN.Logger then
        CLN.Logger:info("Item prop " .. self.slot .. " = " .. self:LuaLine(), true, CLN.Utils.LogCategories.ui)
    end
    CLN.ReplayFrame:RefreshItemProp()
    self:RefreshButtons()
end

function ItemPropPicker:ResetSlot()
    local overrides = CLN.db.profile.itemPropOverrides
    if overrides then overrides[self.slot] = nil end
    CLN.ReplayFrame:RefreshItemProp()
    self:SetSlot(self.slot)
end

--- Drop every slot's custom pick, back to the built-in defaults.
function ItemPropPicker:ResetAll()
    CLN.db.profile.itemPropOverrides = {}
    CLN.ReplayFrame:RefreshItemProp()
    if self.frame and self.frame:IsShown() then self:SetSlot(self.slot) end
end

StaticPopupDialogs["CLN_RESET_ITEM_PROPS"] = {
    text = "Reset all book, letter and plaque models to their defaults?",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function() ItemPropPicker:ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ItemPropPicker:RefreshButtons()
    local f = self.frame
    local overrides = CLN.db.profile.itemPropOverrides
    local overridden = overrides and overrides[self.slot] ~= nil
    f.slotState:SetText(overridden and "|cff80ff80custom|r" or "default")
    f.resetButton:SetEnabled(overridden)
    f.resetAllButton:SetEnabled(overrides ~= nil and next(overrides) ~= nil)
    f.assignButton:SetEnabled(self.fileId ~= nil)
    local pos
    for i, listIndex in ipairs(self.filtered or {}) do
        if listIndex == self.index then pos = i break end
    end
    local count = self.filtered and #self.filtered or 0
    f.prevButton:SetEnabled(pos ~= nil and pos > 1)
    f.nextButton:SetEnabled(count > 0 and (pos == nil or pos < count))
end

local function matchesQuery(item, query)
    if query == "" then return true end
    return (tostring(item[1]) .. "\n" .. item[2]):lower():find(query, 1, true) ~= nil
end

--- Redraw the model list, keeping the selected model in view.
--- resetScroll jumps to the top instead (used when the search text changes).
function ItemPropPicker:RefreshList(resetScroll)
    local f = self.frame
    local query = strtrim(self.query or ""):lower()
    local filtered = {}
    for i, item in ipairs(self.list) do
        if matchesQuery(item, query) then filtered[#filtered + 1] = i end
    end
    self.filtered = filtered

    local selectedPos
    for pos, listIndex in ipairs(filtered) do
        local item = self.list[listIndex]
        local row = getListRow(f, pos)
        row.listIndex = listIndex
        row.fullPath = item[2]
        row.id:SetText(item[1])
        row.path:SetText(item[2]:match("[^/]+$") or item[2])
        local isSelected = listIndex == self.index
        row.selected:SetShown(isSelected)
        row.selBar:SetShown(isSelected)
        if isSelected then selectedPos = pos end
        row:Show()
    end
    for i = #filtered + 1, #f.listRows do f.listRows[i]:Hide() end

    f.listEmpty:SetShown(#filtered == 0)
    f.listCount:SetText(query == "" and (#self.list .. " models")
        or (#filtered .. " of " .. #self.list .. " models"))
    f.listContent:SetHeight(math.max(1, #filtered * ROW_H))

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
    self:RefreshButtons()
end

function ItemPropPicker:Show()
    self.frame = self.frame or createFrame()
    self.list = CLN.ItemPropCandidates or {}
    self.frame:Show()
    self.frame:Raise()
    self.frame.slot:Refresh()
    self:SetSlot(self.slot)
end

function ItemPropPicker:Hide()
    if self.frame then self.frame:Hide() end
end

function ItemPropPicker:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

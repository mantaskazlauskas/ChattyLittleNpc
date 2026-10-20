-- Config.lua - Configuration UI system
-- Builds option controls from an AceConfig-style options table using the
-- custom widgets in Widgets.lua. Each option is a row: label on the left,
-- control in a fixed-width column on the right. Groups render as cards.

---@class ConfigSystem
local ConfigSystem = {}
ConfigSystem.__index = ConfigSystem

local Widgets = _G.ChattyLittleNpc.Widgets
local C, rgba = Widgets.Colors, Widgets.rgba

local ROW_H     = 30    -- standard option row height
local ROW_GAP   = 2     -- vertical gap between rows
local CONTROL_W = 280   -- width of the right-hand control column
local CARD_PAD  = 12    -- inner padding of a group card
local CARD_GAP  = 12    -- vertical gap between group cards

-- Create a new config system instance
---@return ConfigSystem
function ConfigSystem:New()
    local instance = setmetatable({}, ConfigSystem)
    instance.categories = {}
    instance.options = {}
    return instance
end

-- Helper: evaluate a value-or-function field (for hidden, disabled, etc.)
---@param field any A boolean, function, or nil
---@return boolean
local function evalField(field)
    if type(field) == "function" then return field() end
    return field and true or false
end

-- Helper: evaluate a string-or-function field (for name, desc)
local function evalText(field)
    if type(field) == "function" then field = field() end
    return field or ""
end

-- Helper: show the option's name + desc in GameTooltip
local function showTooltip(owner, info)
    if not info.desc then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(evalText(info.name), 1, 1, 1)
    GameTooltip:AddLine(evalText(info.desc), nil, nil, nil, true)
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

-- Helper: refresh every tracked control on the frame that owns this row
local function refreshSiblings(row)
    local parent = row:GetParent()
    if parent then ConfigSystem._RefreshVisibleControls(parent) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Rows
-- ─────────────────────────────────────────────────────────────────────────────

-- Create an option row: hover highlight + left-hand label.
-- The control goes in the right-hand column (anchor at "RIGHT", -CONTROL_W).
local function createRow(parent, info, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or ROW_H)
    row:EnableMouse(true)
    row.info = info

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(rgba(C.rowHover))
    hl:Hide()
    row._hl = hl

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(CONTROL_W + 12), 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(rgba(C.text))
    row.label = label
    return row
end

-- Highlight the row and show its tooltip while the cursor is over the row
-- or any of the given child controls.
local function bindRowHover(row, ...)
    local function enter() row._hl:Show(); showTooltip(row, row.info) end
    local function leave() row._hl:Hide(); hideTooltip() end
    row:SetScript("OnEnter", enter)
    row:SetScript("OnLeave", leave)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        child:HookScript("OnEnter", enter)
        child:HookScript("OnLeave", leave)
    end
end

-- Dim the row and enable/disable its interactive children.
local function setRowDisabled(row, disabled, ...)
    row:SetAlpha(disabled and 0.4 or 1)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if disabled then child:Disable() else child:Enable() end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Controls
-- ─────────────────────────────────────────────────────────────────────────────

-- Create a toggle setting (switch)
---@param parent table Parent frame
---@param info table Setting info {name, desc, get, set, disabled}
---@return table
function ConfigSystem:CreateCheckbox(parent, info)
    local row = createRow(parent, info)
    local sw = Widgets.CreateSwitch(row)
    sw:SetPoint("LEFT", row, "RIGHT", -CONTROL_W, 0)

    local function toggle()
        if evalField(info.disabled) then return end
        info.set(nil, not sw:GetChecked())
        sw:SetChecked(info.get())
        Widgets.PlayClick(sw:GetChecked())
        -- Refresh siblings (e.g. toggling debug mode updates dependent controls)
        refreshSiblings(row)
    end
    sw:SetScript("OnClick", toggle)
    -- Clicking anywhere on the row toggles too.
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self:IsMouseOver() then toggle() end
    end)

    row:SetScript("OnShow", function(self)
        self.label:SetText(evalText(info.name))
        sw:SetChecked(info.get())
        setRowDisabled(self, evalField(info.disabled), sw)
    end)

    bindRowHover(row, sw)
    return row
end

-- Create a multiselect setting as a labeled group of checkboxes
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, get, set, disabled}
---@return table
function ConfigSystem:CreateMultiselect(parent, info)
    local row = createRow(parent, info)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
    row.label:SetWidth(240)
    row.checkboxes = {}

    local CHECK_H = 22

    local function getValues()
        local values = info.values
        if type(values) == "function" then values = values() end
        return values or {}
    end

    local function refreshCheckbox(checkbox)
        checkbox:SetChecked(info.get(nil, checkbox.key))
        local disabled = evalField(info.disabled)
        checkbox:SetAlpha(disabled and 0.4 or 1)
        checkbox:EnableMouse(not disabled)
    end

    function row:Refresh()
        local nameText = evalText(info.name)
        self.label:SetText(nameText)

        local values = getValues()
        local keys = {}
        for key in pairs(values) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            local textA = tostring(values[a] or a)
            local textB = tostring(values[b] or b)
            if textA == textB then return tostring(a) < tostring(b) end
            return textA < textB
        end)

        for index, key in ipairs(keys) do
            local checkbox = self.checkboxes[index]
            if not checkbox then
                checkbox = Widgets.CreateCheckbox(self)
                checkbox:SetScript("OnClick", function(btn)
                    if evalField(info.disabled) then return end
                    info.set(nil, btn.key, not btn:GetChecked())
                    refreshCheckbox(btn)
                    Widgets.PlayClick(btn:GetChecked())
                    refreshSiblings(self)
                end)
                bindRowHover(self, checkbox)
                self.checkboxes[index] = checkbox
            end
            checkbox.key = key
            checkbox.Text:SetText(values[key] or key or "")
            checkbox:ClearAllPoints()
            -- Unlabelled lists use the full row width; labelled ones sit in the control column.
            if nameText ~= "" then
                checkbox:SetPoint("TOPLEFT", self, "TOPRIGHT", -CONTROL_W, -5 - (index - 1) * CHECK_H)
            else
                checkbox:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -5 - (index - 1) * CHECK_H)
            end
            checkbox:SetPoint("RIGHT", self, "RIGHT", -8, 0)
            checkbox:Show()
            refreshCheckbox(checkbox)
        end

        for index = #keys + 1, #self.checkboxes do
            self.checkboxes[index]:Hide()
        end

        self:SetHeight(math.max(ROW_H, #keys * CHECK_H + 10))
        self.label:SetAlpha(evalField(info.disabled) and 0.4 or 1)
    end

    row:SetScript("OnShow", row.Refresh)
    bindRowHover(row)
    row:Refresh()
    return row
end

-- Format a slider value for display
local function formatValue(info, value)
    if info.isPercent then
        return string.format("%d%%", math.floor(value * 100 + 0.5))
    elseif info.step >= 1 then
        return string.format("%d", math.floor(value + 0.5))
    end
    return string.format("%.2f", value)
end

-- Create a slider setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, min, max, step, isPercent, get, set, disabled}
---@return table
function ConfigSystem:CreateSlider(parent, info)
    local row = createRow(parent, info)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    valueText:SetWidth(46)
    valueText:SetJustifyH("RIGHT")
    valueText:SetTextColor(rgba(C.accent))

    local dec = Widgets.CreateArrowButton(row, "left")
    dec:SetPoint("LEFT", row, "RIGHT", -CONTROL_W, 0)
    local inc = Widgets.CreateArrowButton(row, "right")
    inc:SetPoint("RIGHT", valueText, "LEFT", -8, 0)

    local slider = Widgets.CreateSlider(row)
    slider:SetPoint("LEFT", dec, "RIGHT", 10, 0)
    slider:SetPoint("RIGHT", inc, "LEFT", -10, 0)
    slider:SetMinMaxValues(info.min, info.max)
    slider:SetValueStep(info.step)
    slider:SetObeyStepOnDrag(true)

    slider:SetScript("OnValueChanged", function(_, value)
        valueText:SetText(formatValue(info, value))
        -- Skip writes while syncing from the saved value.
        if row._syncing or evalField(info.disabled) then return end
        info.set(nil, value)
    end)

    local function step(delta)
        if evalField(info.disabled) then return end
        local value = slider:GetValue() + delta * info.step
        slider:SetValue(math.min(info.max, math.max(info.min, value)))
    end
    dec:SetScript("OnClick", function() step(-1) end)
    inc:SetScript("OnClick", function() step(1) end)

    row:SetScript("OnShow", function(self)
        self.label:SetText(evalText(info.name))
        self._syncing = true
        slider:SetValue(info.get() or info.min)
        self._syncing = false
        valueText:SetText(formatValue(info, slider:GetValue()))
        setRowDisabled(self, evalField(info.disabled), slider, dec, inc)
    end)

    bindRowHover(row, slider, dec, inc)
    return row
end

-- Create a dropdown setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, sorting, get, set, disabled}
---@return table
function ConfigSystem:CreateDropdown(parent, info)
    local row = createRow(parent, info)
    local dd = Widgets.CreateDropdown(row, CONTROL_W, {
        values  = info.values,
        sorting = info.sorting,
        get     = info.get,
        set     = function(value)
            if evalField(info.disabled) then return end
            info.set(nil, value)
            -- Refresh siblings in case this changes disabled state of other controls
            refreshSiblings(row)
        end,
    })
    dd:SetPoint("LEFT", row, "RIGHT", -CONTROL_W, 0)

    row:SetScript("OnShow", function(self)
        self.label:SetText(evalText(info.name))
        dd:Refresh()
        setRowDisabled(self, evalField(info.disabled), dd)
    end)

    bindRowHover(row, dd)
    return row
end

-- Create a button
---@param parent table Parent category or frame
---@param info table Button info {name, desc, func, disabled}
---@return table
function ConfigSystem:CreateButton(parent, info)
    local button = Widgets.CreateButton(parent, evalText(info.name), nil, 24)
    button:FitToText(140)
    button.info = info

    button:SetScript("OnClick", function()
        if not evalField(info.disabled) then info.func() end
    end)
    -- Name may be dynamic (e.g. includes a count), so re-read and re-fit on refresh.
    button:SetScript("OnShow", function(self)
        self:SetText(evalText(info.name))
        self:FitToText(140)
        self:SetEnabled(not evalField(info.disabled))
    end)
    button:HookScript("OnEnter", function(self) showTooltip(self, info) end)
    button:HookScript("OnLeave", hideTooltip)

    return button
end

-- Create a sub-header inside a group: label followed by a thin rule
---@param parent table Parent frame
---@param text string|function Header text
---@return table
function ConfigSystem:CreateHeader(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(30)

    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 6)
    fs:SetTextColor(rgba(C.textHeader))

    local rule = row:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    rule:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    rule:SetColorTexture(rgba(C.cardBorder))

    local function refresh() fs:SetText(evalText(text)) end
    row:SetScript("OnShow", refresh)
    refresh()
    return row
end

-- Create a muted, wrapping description text
---@param parent table Parent frame
---@param textOrFn string|function Description text or function returning text
---@return table
function ConfigSystem:CreateDescription(parent, textOrFn)
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetText(evalText(textOrFn))
    desc:SetTextColor(rgba(C.textMuted))
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(2)
    desc:SetWidth(540)
    -- Dynamic text is re-read by _RefreshVisibleControls (FontStrings have no OnShow).
    if type(textOrFn) == "function" then desc._textFn = textOrFn end
    return desc
end

-- Create an input text box
---@param parent table Parent frame
---@param info table Setting info {name, desc, get, set}
---@return table
function ConfigSystem:CreateInput(parent, info)
    local row = createRow(parent, info)
    local eb = Widgets.CreateEditBox(row, CONTROL_W, 24)
    eb:SetPoint("LEFT", row, "RIGHT", -CONTROL_W, 0)
    eb:SetScript("OnEnterPressed", function(self)
        local val = self:GetText()
        if info.set then info.set(nil, val) end
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    row:SetScript("OnShow", function(self) self.label:SetText(evalText(info.name)) end)
    bindRowHover(row, eb)
    return row
end

-- Create a keybinding widget: label + button that captures the next keypress
---@param parent table Parent frame
---@param info table Setting info {name, desc, get, set}
---@return table
function ConfigSystem:CreateKeybinding(parent, info)
    local row = createRow(parent, info)
    local btn = Widgets.CreateButton(row, "", 160, 24)
    btn:SetPoint("LEFT", row, "RIGHT", -CONTROL_W, 0)

    local function refreshLabel()
        local key = info.get and info.get()
        btn:SetText(key and key ~= "" and key or "|cFF888888(unbound)|r")
    end

    -- Hidden frame that captures the next keypress
    local listener = CreateFrame("Frame", nil, btn)
    listener:Hide()
    listener:SetAllPoints(btn)
    listener:SetFrameStrata("TOOLTIP")

    local function stopListening()
        listener:Hide()
        listener:SetScript("OnKeyDown", nil)
        listener:UnregisterAllEvents()
        btn:SetActive(false)
        refreshLabel()
    end

    local function startListening()
        -- SetPropagateKeyboardInput is restricted for addon code in combat
        if InCombatLockdown() then return end
        btn:SetText("|cFFFFD100Press a key...|r")
        btn:SetActive(true)
        listener:Show()
        listener:SetPropagateKeyboardInput(false)
        listener:RegisterEvent("PLAYER_REGEN_DISABLED")  -- abort in combat
        listener:SetScript("OnEvent", function() stopListening() end)
        listener:SetScript("OnKeyDown", function(self, key)
            if key == "LSHIFT" or key == "RSHIFT"
               or key == "LCTRL" or key == "RCTRL"
               or key == "LALT"  or key == "RALT"
               or key == "LMETA" or key == "RMETA" then
                return -- wait for the key the modifier is held with
            end
            if key == "ESCAPE" then
                -- clear binding
                if info.set then info.set(nil, "") end
            elseif key ~= "PRINTSCREEN" and key ~= "UNKNOWN" then
                -- Same modifier order WoW uses in binding strings: ALT-CTRL-SHIFT-KEY
                local prefix = (IsAltKeyDown() and "ALT-" or "")
                    .. (IsControlKeyDown() and "CTRL-" or "")
                    .. (IsShiftKeyDown() and "SHIFT-" or "")
                if info.set then info.set(nil, prefix .. key) end
            end
            stopListening()
        end)
    end

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if info.set then info.set(nil, "") end
            stopListening()
        else
            startListening()
        end
    end)

    row:SetScript("OnShow", function(self)
        self.label:SetText(evalText(info.name))
        refreshLabel()
    end)
    refreshLabel()

    bindRowHover(row, btn)
    return row
end

-- Create a control based on type
---@param parent table Parent frame
---@param opt table Option definition
---@return table|nil
function ConfigSystem:CreateControl(parent, opt)
    if opt.type == "toggle" then
        return self:CreateCheckbox(parent, opt)
    elseif opt.type == "range" then
        return self:CreateSlider(parent, opt)
    elseif opt.type == "select" then
        return self:CreateDropdown(parent, opt)
    elseif opt.type == "execute" then
        return self:CreateButton(parent, opt)
    elseif opt.type == "description" then
        return self:CreateDescription(parent, opt.name)
    elseif opt.type == "header" then
        return self:CreateHeader(parent, opt.name)
    elseif opt.type == "input" then
        return self:CreateInput(parent, opt)
    elseif opt.type == "multiselect" then
        return self:CreateMultiselect(parent, opt)
    elseif opt.type == "keybinding" then
        return self:CreateKeybinding(parent, opt)
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Refresh
-- ─────────────────────────────────────────────────────────────────────────────

-- Re-query and redraw all controls on the options panel (call after profile switch)
function ConfigSystem:Refresh()
    if self.contentFrame then
        ConfigSystem._RefreshVisibleControls(self.contentFrame)
    end
end

-- Refresh value and disabled state of all tracked controls on a content frame
---@param contentFrame table The content frame containing controls
function ConfigSystem._RefreshVisibleControls(contentFrame)
    if not contentFrame._trackedControls then return end
    for _, entry in ipairs(contentFrame._trackedControls) do
        local control = entry.control
        if control and control.IsShown and control:IsShown() then
            if control._textFn then
                control:SetText(control._textFn() or "")
            -- Re-trigger OnShow to update value and disabled state
            elseif control:GetScript("OnShow") then
                control:GetScript("OnShow")(control)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Layout
-- ─────────────────────────────────────────────────────────────────────────────

local function sortByOrder(keys, args)
    table.sort(keys, function(a, b)
        local orderA = args[a].order or 999
        local orderB = args[b].order or 999
        if orderA == orderB then return a < b end
        return orderA < orderB
    end)
end

-- Card background + border spanning [top, bottom] (frame-relative Y offsets).
local function drawCard(frame, top, bottom)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(rgba(C.cardBg))
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
    bg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, bottom)
    Widgets.AddBorder(frame, bg, C.cardBorder)

    -- Gold tab on the card's left edge, level with the group title.
    local marker = frame:CreateTexture(nil, "ARTWORK")
    marker:SetColorTexture(rgba(C.accent))
    marker:SetSize(3, 18)
    marker:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top - CARD_PAD + 1)
end

-- Lay out a specific subset of option groups into an existing content frame.
-- groupKeys : ordered list of group-key strings to include (e.g. {"Playback"}).
-- allArgs   : the top-level options.args table containing the group definitions.
-- The frame's width must be set before calling.
-- Returns the total height (in pixels) of the content that was laid out.
function ConfigSystem:LayoutGroupsInFrame(frame, groupKeys, allArgs)
    if not frame._trackedControls then
        frame._trackedControls = {}
    end

    local sortedKeys = {}
    for _, key in ipairs(groupKeys) do
        if allArgs[key] then sortedKeys[#sortedKeys + 1] = key end
    end
    sortByOrder(sortedKeys, allArgs)

    local textW = frame:GetWidth() - CARD_PAD * 2 - 16
    local y = 0

    local function track(control, opt)
        table.insert(frame._trackedControls, { control = control, opt = opt })
    end

    for _, groupKey in ipairs(sortedKeys) do
        local group = allArgs[groupKey]
        if group.type == "group" then
            local cardTop = y
            y = y - CARD_PAD

            -- Group title.
            local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD + 8, y)
            title:SetText(evalText(group.name))
            title:SetTextColor(rgba(C.textHeader))
            y = y - 22

            -- Optional group description.
            if group.desc then
                local desc = self:CreateDescription(frame, group.desc)
                desc:SetWidth(textW)
                desc:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD + 8, y)
                if desc._textFn then track(desc, group) end
                y = y - math.ceil(desc:GetStringHeight() + 4)
            end
            y = y - 6

            -- Controls within the group.
            if group.args then
                local sortedControlKeys = {}
                for key in pairs(group.args) do
                    sortedControlKeys[#sortedControlKeys + 1] = key
                end
                sortByOrder(sortedControlKeys, group.args)

                local prevButton, buttonsW = nil, 0
                local rowW = frame:GetWidth() - CARD_PAD * 2
                for _, key in ipairs(sortedControlKeys) do
                    local opt = group.args[key]
                    if not evalField(opt.hidden) then
                        local control = self:CreateControl(frame, opt)
                        if control then
                            if opt.type == "execute" then
                                -- Consecutive buttons share a line while they fit.
                                local w = control:GetWidth()
                                if prevButton and buttonsW + 8 + w <= rowW - 16 then
                                    control:SetPoint("LEFT", prevButton, "RIGHT", 8, 0)
                                    buttonsW = buttonsW + 8 + w
                                else
                                    control:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD + 8, y - 3)
                                    y = y - (ROW_H + ROW_GAP)
                                    buttonsW = w
                                end
                                prevButton = control
                            elseif opt.type == "description" then
                                control:SetWidth(textW)
                                control:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD + 8, y - 4)
                                y = y - math.ceil(control:GetStringHeight() + 12)
                                prevButton = nil
                            else
                                control:SetPoint("TOPLEFT", frame, "TOPLEFT", CARD_PAD, y)
                                control:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CARD_PAD, y)
                                y = y - (control:GetHeight() + ROW_GAP)
                                prevButton = nil
                            end
                            track(control, opt)
                        end
                    end
                end
            end

            y = y - CARD_PAD + ROW_GAP
            drawCard(frame, cardTop, y)
            y = y - CARD_GAP
        end
    end

    return -y
end

-- Register options and create a Blizzard settings panel containing every group
---@param addonName string Addon name for the panel
---@param options table Options table structure
---@param db table Database reference
function ConfigSystem:RegisterOptions(addonName, options, db)
    self.db = db
    self.optionsTable = options

    local panel = CreateFrame("Frame")
    panel.name = options.name or addonName

    local scrollFrame, content = Widgets.CreateScrollFrame(panel)
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 10)
    content:SetWidth(570)

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 6, -6)
    title:SetText(options.name or addonName)

    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -36)
    body:SetWidth(570)
    body._trackedControls = {}
    self.contentFrame = body -- stored so Refresh() can re-query all controls

    local groupKeys = {}
    for key, group in pairs(options.args or {}) do
        if group.type == "group" then groupKeys[#groupKeys + 1] = key end
    end
    local height = self:LayoutGroupsInFrame(body, groupKeys, options.args or {})
    body:SetHeight(math.max(height, 1))
    content:SetHeight(height + 36)

    -- Modern API (10.0+)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    else
        -- Legacy API
        InterfaceOptions_AddCategory(panel)
    end

    self.panel = panel
    return panel
end

-- Open the settings panel
function ConfigSystem:Open()
    if Settings and Settings.OpenToCategory and self.category then
        -- Modern API needs the numeric category ID, not the object
        local id = self.category.ID or (self.category.GetID and self.category:GetID())
        if type(id) == "table" then id = id.ID end -- safety: unwrap if GetID returns object
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel) -- Call twice for legacy API bug
    end
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.ConfigSystem = ConfigSystem

return ConfigSystem

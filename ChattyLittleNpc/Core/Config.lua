-- Config.lua - Configuration UI system
-- Provides a simplified options panel builder for WoW's Settings API

---@class ConfigSystem
local ConfigSystem = {}
ConfigSystem.__index = ConfigSystem

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

-- Helper: attach GameTooltip on hover for a control
---@param control table The frame to attach tooltip to
---@param info table Setting info with desc field
local function attachTooltip(control, info)
    if not info.desc then return end
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local tipName = type(info.name) == "function" and info.name() or info.name or ""
        GameTooltip:SetText(tipName, 1, 1, 1)
        local tipDesc = type(info.desc) == "function" and info.desc() or info.desc or ""
        GameTooltip:AddLine(tipDesc, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Helper: update the disabled visual state of a checkbox
---@param checkbox table The checkbox frame
local function updateCheckboxDisabled(checkbox)
    local isDisabled = evalField(checkbox.info.disabled)
    if isDisabled then
        checkbox:Disable()
        checkbox.Text:SetTextColor(0.5, 0.5, 0.5)
    else
        checkbox:Enable()
        checkbox.Text:SetTextColor(1, 0.82, 0)
    end
end

-- Create a checkbox setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, get, set, disabled}
---@return table
function ConfigSystem:CreateCheckbox(parent, info)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    local nameText = type(info.name) == "function" and info.name() or info.name or ""
    checkbox.Text:SetText(nameText)
    checkbox.tooltipText = info.desc
    
    -- Store the info for later use
    checkbox.info = info
    
    checkbox:SetScript("OnShow", function(self)
        self:SetChecked(self.info.get())
        updateCheckboxDisabled(self)
    end)
    
    checkbox:SetScript("OnClick", function(self)
        if evalField(self.info.disabled) then
            self:SetChecked(self.info.get())
            return
        end
        local checked = self:GetChecked()
        self.info.set(nil, checked and true or false)
        self:SetChecked(self.info.get())
        -- Refresh all sibling controls (toggling debug mode should update dependent controls)
        if self:GetParent() then
            ConfigSystem._RefreshVisibleControls(self:GetParent())
        end
    end)
    
    attachTooltip(checkbox, info)
    
    return checkbox
end

-- Create a multiselect setting as a labeled group of checkboxes
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, get, set, disabled}
---@return table
function ConfigSystem:CreateMultiselect(parent, info)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(540, 24)
    container:EnableMouse(true)
    container.info = info
    container.checkboxes = {}

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 0.82, 0)
    container.label = label

    local function getValues()
        local values = info.values
        if type(values) == "function" then
            values = values()
        end
        return values or {}
    end

    local function refreshCheckbox(checkbox)
        checkbox:SetChecked(info.get(nil, checkbox.key) and true or false)
        updateCheckboxDisabled(checkbox)
    end

    function container:Refresh()
        local nameText = type(info.name) == "function" and info.name() or info.name or ""
        self.label:SetText(nameText)

        local values = getValues()
        local keys = {}
        for key in pairs(values) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            local textA = tostring(values[a] or a)
            local textB = tostring(values[b] or b)
            if textA == textB then
                return tostring(a) < tostring(b)
            end
            return textA < textB
        end)

        local topOffset = nameText ~= "" and -18 or 0
        for index, key in ipairs(keys) do
            local checkbox = self.checkboxes[index]
            if not checkbox then
                checkbox = CreateFrame("CheckButton", nil, self, "InterfaceOptionsCheckButtonTemplate")
                checkbox:SetScript("OnShow", refreshCheckbox)
                checkbox:SetScript("OnClick", function(btn)
                    if evalField(info.disabled) then
                        refreshCheckbox(btn)
                        return
                    end
                    local checked = btn:GetChecked() and true or false
                    info.set(nil, btn.key, checked)
                    refreshCheckbox(btn)
                    if self:GetParent() then
                        ConfigSystem._RefreshVisibleControls(self:GetParent())
                    end
                end)
                checkbox.info = { disabled = info.disabled }
                attachTooltip(checkbox, info)
                self.checkboxes[index] = checkbox
            end

            checkbox.key = key
            checkbox.Text:SetText(values[key] or key or "")
            checkbox:SetPoint("TOPLEFT", self, "TOPLEFT", 0, topOffset - ((index - 1) * 24))
            checkbox:Show()
            refreshCheckbox(checkbox)
        end

        for index = #keys + 1, #self.checkboxes do
            self.checkboxes[index]:Hide()
        end

        local height = math.max(24, (#keys * 24) + (nameText ~= "" and 20 or 0))
        self:SetHeight(height)
    end

    container:SetScript("OnShow", function(self)
        self:Refresh()
        local isDisabled = evalField(info.disabled)
        if isDisabled then
            self.label:SetTextColor(0.5, 0.5, 0.5)
        else
            self.label:SetTextColor(1, 0.82, 0)
        end
    end)

    attachTooltip(container, info)
    container:Refresh()

    return container
end

-- Auto-incrementing counter for unique slider names (required by Classic OptionsSliderTemplate)
ConfigSystem._sliderCounter = 0

-- Create a slider setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, min, max, step, get, set, disabled}
---@return table
function ConfigSystem:CreateSlider(parent, info)
    ConfigSystem._sliderCounter = ConfigSystem._sliderCounter + 1
    local sliderName = "CLNConfigSlider" .. ConfigSystem._sliderCounter
    local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    slider.tooltipText = info.desc
    
    -- Set a reasonable width to prevent text cutoff
    if info.width == "full" then
        slider:SetWidth(400)
    else
        slider:SetWidth(250)
    end
    
    slider:SetMinMaxValues(info.min, info.max)
    slider:SetValueStep(info.step)
    slider:SetObeyStepOnDrag(true)
    
    -- Store the info for later use
    slider.info = info
    
    -- Choose format string based on step size (integers vs decimals)
    local isInteger = (info.step >= 1)
    local fmt = isInteger and "%d" or "%.2f"
    
    -- Hide the Low/High range labels to reduce clutter
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end
    
    -- Store the base name for title updates
    slider._baseName = info.name
    
    -- Helper: update title to include current value
    local function updateTitle(self, value)
        self.Text:SetText(self._baseName .. ": " .. string.format(fmt, value))
    end
    
    slider:SetScript("OnShow", function(self)
        local value = self.info.get()
        self:SetValue(value)
        updateTitle(self, value)
        local isDisabled = evalField(self.info.disabled)
        if isDisabled then
            self:Disable()
            self.Text:SetTextColor(0.5, 0.5, 0.5)
        else
            self:Enable()
            self.Text:SetTextColor(1, 0.82, 0)
        end
    end)
    
    slider:SetScript("OnValueChanged", function(self, value)
        if evalField(self.info.disabled) then return end
        updateTitle(self, value)
        self.info.set(nil, value)
    end)
    
    attachTooltip(slider, info)
    
    -- Arrow buttons for stepping the slider by one step.
    -- Parented to the slider's parent so they aren't clipped by the slider frame.
    local stepSize = info.step
    local sliderParent = slider:GetParent()

    local leftBtn = CreateFrame("Button", nil, sliderParent)
    leftBtn:SetSize(20, 20)
    leftBtn:SetPoint("RIGHT", slider, "LEFT", -2, 0)
    leftBtn:SetFrameLevel(slider:GetFrameLevel() + 2)
    leftBtn:SetNormalFontObject("GameFontNormalSmall")
    leftBtn:SetHighlightFontObject("GameFontHighlightSmall")
    leftBtn:SetText("<")
    leftBtn:GetFontString():SetPoint("CENTER")
    leftBtn:SetScript("OnClick", function()
        if evalField(info.disabled) then return end
        local cur = slider:GetValue()
        local newVal = math.max(info.min, cur - stepSize)
        slider:SetValue(newVal)
    end)

    local rightBtn = CreateFrame("Button", nil, sliderParent)
    rightBtn:SetSize(20, 20)
    rightBtn:SetPoint("LEFT", slider, "RIGHT", 2, 0)
    rightBtn:SetFrameLevel(slider:GetFrameLevel() + 2)
    rightBtn:SetNormalFontObject("GameFontNormalSmall")
    rightBtn:SetHighlightFontObject("GameFontHighlightSmall")
    rightBtn:SetText(">")
    rightBtn:GetFontString():SetPoint("CENTER")
    rightBtn:SetScript("OnClick", function()
        if evalField(info.disabled) then return end
        local cur = slider:GetValue()
        local newVal = math.min(info.max, cur + stepSize)
        slider:SetValue(newVal)
    end)

    slider._leftBtn = leftBtn
    slider._rightBtn = rightBtn

    return slider
end

-- Auto-incrementing counter for unique dropdown names (required by Classic UIDropDownMenu)
ConfigSystem._dropdownCounter = 0

-- Create a dropdown setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, get, set, disabled}
---@return table
function ConfigSystem:CreateDropdown(parent, info)
    ConfigSystem._dropdownCounter = ConfigSystem._dropdownCounter + 1
    local dropdownName = "CLNConfigDropdown" .. ConfigSystem._dropdownCounter
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    
    -- Store the info for later use
    dropdown.info = info
    
    local label = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
    label:SetText(type(info.name) == "function" and info.name() or info.name or "")
    dropdown.label = label
    
    -- Set dropdown width
    if info.width == "full" then
        UIDropDownMenu_SetWidth(dropdown, 380)
    else
        UIDropDownMenu_SetWidth(dropdown, 200)
    end
    
    local function OnClick(self)
        if evalField(dropdown.info.disabled) then return end
        dropdown.info.set(nil, self.value)
        UIDropDownMenu_SetText(dropdown, self:GetText())
        -- Refresh siblings in case this changes disabled state of other controls
        if dropdown:GetParent() then
            ConfigSystem._RefreshVisibleControls(dropdown:GetParent())
        end
    end
    
    local function Initialize(self, level)
        local vals = dropdown.info.values
        if type(vals) == "function" then vals = vals() end
        local currentValue = dropdown.info.get()
        for value, text in pairs(vals) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = text
            item.value = value
            item.func = OnClick
            item.checked = (value == currentValue)
            UIDropDownMenu_AddButton(item, level)
        end
    end
    
    UIDropDownMenu_Initialize(dropdown, Initialize)
    
    dropdown:SetScript("OnShow", function(self)
        local currentValue = self.info.get()
        local vals = self.info.values
        if type(vals) == "function" then vals = vals() end
        UIDropDownMenu_SetText(self, vals[currentValue] or currentValue)
        local isDisabled = evalField(self.info.disabled)
        if isDisabled then
            UIDropDownMenu_DisableDropDown(self)
            self.label:SetTextColor(0.5, 0.5, 0.5)
        else
            UIDropDownMenu_EnableDropDown(self)
            self.label:SetTextColor(1, 0.82, 0)
        end
    end)
    
    return dropdown
end

-- Create a button
---@param parent table Parent category or frame
---@param info table Button info {name, desc, func}
---@return table
function ConfigSystem:CreateButton(parent, info)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(type(info.name) == "function" and info.name() or info.name or "")
    
    -- Set button width based on width parameter
    if info.width == "full" then
        button:SetWidth(400)
    else
        button:SetWidth(200)
    end
    button:SetHeight(22)
    button.tooltipText = info.desc
    
    button:SetScript("OnClick", function(self)
        info.func()
    end)
    
    attachTooltip(button, info)
    
    return button
end

-- Create a header/label
---@param parent table Parent category or frame
---@param text string Header text
---@return table
function ConfigSystem:CreateHeader(parent, text)
    if type(text) == "function" then text = text() end
    text = text or ""
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(text)
    return header
end

-- Create a description text under a group header
---@param parent table Parent frame
---@param textOrFn string|function Description text or function returning text
---@return table
function ConfigSystem:CreateDescription(parent, textOrFn)
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local text = type(textOrFn) == "function" and textOrFn() or (textOrFn or "")
    desc:SetText(text)
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetJustifyH("LEFT")
    desc:SetWidth(540)
    -- If name is a function, refresh on show to pick up dynamic content
    if type(textOrFn) == "function" then
        desc:SetScript("OnShow", function(self) self:SetText(textOrFn()) end)
    end
    return desc
end

-- Create a horizontal separator line
---@param parent table Parent frame
---@return table
function ConfigSystem:CreateSeparator(parent)
    local separator = parent:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetWidth(540)
    separator:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    return separator
end

-- Refresh disabled/enabled visual state of all tracked controls on a content frame
---@param contentFrame table The content frame containing controls
-- Re-query and redraw all controls on the options panel (call after profile switch)
function ConfigSystem:Refresh()
    if self.contentFrame then
        ConfigSystem._RefreshVisibleControls(self.contentFrame)
    end
end

function ConfigSystem._RefreshVisibleControls(contentFrame)
    if not contentFrame._trackedControls then return end
    for _, entry in ipairs(contentFrame._trackedControls) do
        local control = entry.control
        local opt = entry.opt
        if control and control.IsShown and control:IsShown() then
            -- Re-trigger OnShow to update disabled state
            if control:GetScript("OnShow") then
                control:GetScript("OnShow")(control)
            end
        end
    end
end

-- Register options and create settings panel
---@param addonName string Addon name for the panel
---@param options table Options table structure
---@param db table Database reference
function ConfigSystem:RegisterOptions(addonName, options, db)
    self.db = db
    self.optionsTable = options
    
    -- Create main category panel
    local panel = CreateFrame("Frame")
    panel.name = options.name or addonName
    
    -- Create a scroll frame for the content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    -- Create content frame inside scroll frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(570, 1) -- Width fixed, height will grow
    scrollFrame:SetScrollChild(content)
    self.contentFrame = content -- stored so Refresh() can re-query all controls
    
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 6, -6)
    title:SetText(options.name or addonName)
    
    local yOffset = -40
    local contentHeight = 60 -- Start with title space
    
    -- Track all controls for disabled-state refresh
    content._trackedControls = {}
    
    -- Process option groups in sorted order
    if options.args then
        -- Get sorted keys (respect order field on groups)
        local sortedKeys = {}
        for key in pairs(options.args) do
            table.insert(sortedKeys, key)
        end
        table.sort(sortedKeys, function(a, b)
            local orderA = options.args[a].order or 999
            local orderB = options.args[b].order or 999
            if orderA == orderB then
                return a < b
            end
            return orderA < orderB
        end)
        
        local isFirstGroup = true
        for _, groupKey in ipairs(sortedKeys) do
            local group = options.args[groupKey]
            if group.type == "group" then
                -- Add separator line between groups (not before the first)
                if not isFirstGroup then
                    local sep = self:CreateSeparator(content)
                    sep:SetPoint("TOPLEFT", 6, yOffset - 4)
                    yOffset = yOffset - 14
                    contentHeight = contentHeight + 14
                end
                isFirstGroup = false
                
                -- Create group header
                local headerText = group.name or ""
                if type(headerText) == "function" then headerText = headerText() or "" end
                local header = self:CreateHeader(content, headerText)
                header:SetPoint("TOPLEFT", 6, yOffset)
                yOffset = yOffset - 24
                contentHeight = contentHeight + 24
                
                -- Optional group description
                if group.desc then
                    local descText = group.desc
                    if type(descText) == "function" then descText = descText() or "" end
                    local desc = self:CreateDescription(content, descText)
                    desc:SetPoint("TOPLEFT", 8, yOffset)
                    local descHeight = 20
                    yOffset = yOffset - descHeight
                    contentHeight = contentHeight + descHeight
                end
                
                -- Process group args
                if group.args then
                    -- Get sorted keys for controls within the group
                    local sortedControlKeys = {}
                    for key in pairs(group.args) do
                        table.insert(sortedControlKeys, key)
                    end
                    -- Sort by order parameter if it exists, otherwise alphabetically
                    table.sort(sortedControlKeys, function(a, b)
                        local orderA = group.args[a].order or 999
                        local orderB = group.args[b].order or 999
                        if orderA == orderB then
                            return a < b
                        end
                        return orderA < orderB
                    end)
                    
                    for _, key in ipairs(sortedControlKeys) do
                        local opt = group.args[key]
                        -- Skip hidden controls
                        if evalField(opt.hidden) then
                            -- do nothing
                        else
                            local control = self:CreateControl(content, opt)
                            if control then
                                -- Dropdowns have a label above the frame; add extra
                                -- top margin so it doesn't overlap the previous control.
                                if opt.type == "select" then
                                    yOffset = yOffset - 18
                                    contentHeight = contentHeight + 18
                                end
                                control:SetPoint("TOPLEFT", opt.type == "range" and 26 or 6, yOffset)
                                table.insert(content._trackedControls, { control = control, opt = opt })
                                if opt.type == "range" then
                                    yOffset = yOffset - 50
                                    contentHeight = contentHeight + 50
                                elseif opt.type == "select" then
                                    yOffset = yOffset - 42
                                    contentHeight = contentHeight + 42
                                elseif opt.type == "multiselect" then
                                    local controlHeight = control:GetHeight() or 32
                                    yOffset = yOffset - controlHeight
                                    contentHeight = contentHeight + controlHeight
                                elseif opt.type == "description" then
                                    yOffset = yOffset - 40
                                    contentHeight = contentHeight + 40
                                elseif opt.type == "keybinding" then
                                    yOffset = yOffset - 32
                                    contentHeight = contentHeight + 32
                                else
                                    yOffset = yOffset - 32
                                    contentHeight = contentHeight + 32
                                end
                            end
                        end
                    end
                end
                
                yOffset = yOffset - 8 -- Space after group before separator
                contentHeight = contentHeight + 8
            end
        end
    end
    
    -- Set the actual content height
    content:SetHeight(contentHeight)
    
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

-- Create an input text box
---@param parent table Parent frame
---@param info table Setting info {name, desc, get, set}
---@return table
function ConfigSystem:CreateInput(parent, info)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(540, 28)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(info.name or "")
    label:SetTextColor(1, 0.82, 0)

    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(200, 20)
    eb:SetPoint("LEFT", label, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self)
        local val = self:GetText()
        if info.set then info.set(nil, val) end
        self:SetText("")
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    attachTooltip(container, info)
    return container
end

-- Create a control based on type
---@param parent table Parent frame
---@param opt table Option definition
---@return table|nil
-- Create a keybinding widget: label + button that captures the next keypress
---@param parent table Parent frame
---@param info table Setting info {name, desc, get, set}
---@return table
function ConfigSystem:CreateKeybinding(parent, info)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(540, 28)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 0, 0)
    local nameText = type(info.name) == "function" and info.name() or info.name or ""
    label:SetText(nameText)
    label:SetTextColor(1, 0.82, 0)

    local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    btn:SetSize(140, 22)
    btn:SetPoint("LEFT", label, "RIGHT", 12, 0)

    local function refreshLabel()
        local key = info.get and info.get()
        btn:SetText(key and key ~= "" and key or "|cFF888888(unbound)|r")
    end
    refreshLabel()

    -- Hidden frame that captures the next keypress
    local listener = CreateFrame("Frame", nil, btn)
    listener:Hide()
    listener:SetAllPoints(btn)
    listener:SetFrameStrata("TOOLTIP")

    local function stopListening()
        listener:Hide()
        listener:SetScript("OnKeyDown", nil)
        listener:UnregisterAllEvents()
        btn:SetText(info.get and info.get() or "|cFF888888(unbound)|r")
    end

    local function startListening()
        btn:SetText("|cFFFFD100Press a key...|r")
        listener:Show()
        listener:SetPropagateKeyboardInput(false)
        listener:RegisterEvent("PLAYER_REGEN_DISABLED")  -- abort in combat
        listener:SetScript("OnEvent", function() stopListening() end)
        listener:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                -- clear binding
                if info.set then info.set(nil, "") end
            elseif key ~= "LSHIFT" and key ~= "RSHIFT"
                   and key ~= "LCTRL"  and key ~= "RCTRL"
                   and key ~= "LALT"   and key ~= "RALT"
                   and key ~= "PRINTSCREEN" and key ~= "UNKNOWN" then
                if info.set then info.set(nil, key) end
            end
            stopListening()
        end)
    end

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if info.set then info.set(nil, "") end
            stopListening()
            refreshLabel()
        else
            startListening()
        end
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    container:SetScript("OnShow", function() refreshLabel() end)

    attachTooltip(container, info)
    return container
end

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
        local text = opt.name or ""
        if type(text) == "function" then text = text() or "" end
        return self:CreateDescription(parent, text)
    elseif opt.type == "header" then
        local text = opt.name or ""
        if type(text) == "function" then text = text() or "" end
        return self:CreateHeader(parent, text)
    elseif opt.type == "input" then
        return self:CreateInput(parent, opt)
    elseif opt.type == "multiselect" then
        return self:CreateMultiselect(parent, opt)
    elseif opt.type == "keybinding" then
        return self:CreateKeybinding(parent, opt)
    end
    return nil
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

-- Lay out a specific subset of option groups into an existing content frame.
-- groupKeys : ordered list of group-key strings to include (e.g. {"Playback"}).
-- allArgs   : the top-level options.args table containing the group definitions.
-- Returns the total height (in pixels) of the content that was laid out.
function ConfigSystem:LayoutGroupsInFrame(frame, groupKeys, allArgs)
    if not frame._trackedControls then
        frame._trackedControls = {}
    end

    -- Sort the requested group keys by their .order field.
    local sortedKeys = {}
    for _, key in ipairs(groupKeys) do
        if allArgs[key] then sortedKeys[#sortedKeys + 1] = key end
    end
    table.sort(sortedKeys, function(a, b)
        local orderA = allArgs[a].order or 999
        local orderB = allArgs[b].order or 999
        if orderA == orderB then return a < b end
        return orderA < orderB
    end)

    local yOffset      = -8   -- small top margin
    local contentHeight = 8
    local isFirstGroup  = true

    for _, groupKey in ipairs(sortedKeys) do
        local group = allArgs[groupKey]
        if group.type == "group" then
            -- Separator before every group except the first.
            if not isFirstGroup then
                local sep = self:CreateSeparator(frame)
                sep:SetPoint("TOPLEFT", 6, yOffset - 4)
                yOffset       = yOffset - 14
                contentHeight = contentHeight + 14
            end
            isFirstGroup = false

            -- Group header.
            local headerText = group.name or ""
            if type(headerText) == "function" then headerText = headerText() or "" end
            local header = self:CreateHeader(frame, headerText)
            header:SetPoint("TOPLEFT", 6, yOffset)
            yOffset       = yOffset - 24
            contentHeight = contentHeight + 24

            -- Optional group description.
            if group.desc then
                local desc = self:CreateDescription(frame, group.desc)
                desc:SetPoint("TOPLEFT", 8, yOffset)
                yOffset       = yOffset - 20
                contentHeight = contentHeight + 20
            end

            -- Controls within the group.
            if group.args then
                local sortedControlKeys = {}
                for key in pairs(group.args) do
                    sortedControlKeys[#sortedControlKeys + 1] = key
                end
                table.sort(sortedControlKeys, function(a, b)
                    local orderA = group.args[a].order or 999
                    local orderB = group.args[b].order or 999
                    if orderA == orderB then return a < b end
                    return orderA < orderB
                end)

                for _, key in ipairs(sortedControlKeys) do
                    local opt = group.args[key]
                    if not evalField(opt.hidden) then
                        local control = self:CreateControl(frame, opt)
                        if control then
                            -- Dropdowns need extra top-margin for their label.
                            if opt.type == "select" then
                                yOffset       = yOffset - 18
                                contentHeight = contentHeight + 18
                            end
                            control:SetPoint("TOPLEFT", opt.type == "range" and 26 or 6, yOffset)
                            table.insert(frame._trackedControls, { control = control, opt = opt })
                            if opt.type == "range" then
                                yOffset       = yOffset - 50
                                contentHeight = contentHeight + 50
                            elseif opt.type == "select" then
                                yOffset       = yOffset - 42
                                contentHeight = contentHeight + 42
                            elseif opt.type == "multiselect" then
                                local h = control:GetHeight() or 32
                                yOffset       = yOffset - h
                                contentHeight = contentHeight + h
                            elseif opt.type == "description" then
                                yOffset       = yOffset - 40
                                contentHeight = contentHeight + 40
                            elseif opt.type == "keybinding" then
                                yOffset       = yOffset - 32
                                contentHeight = contentHeight + 32
                            else
                                yOffset       = yOffset - 32
                                contentHeight = contentHeight + 32
                            end
                        end
                    end
                end
            end

            yOffset       = yOffset - 8
            contentHeight = contentHeight + 8
        end
    end

    return contentHeight
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.ConfigSystem = ConfigSystem

return ConfigSystem

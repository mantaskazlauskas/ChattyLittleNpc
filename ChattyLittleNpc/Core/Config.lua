-- Config.lua - Configuration UI system to replace AceConfig/AceConfigDialog
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
        GameTooltip:SetText(info.name or "", 1, 1, 1)
        GameTooltip:AddLine(info.desc, nil, nil, nil, true)
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
    checkbox.Text:SetText(info.name)
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

-- Create a slider setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, min, max, step, get, set, disabled}
---@return table
function ConfigSystem:CreateSlider(parent, info)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
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
    
    return slider
end

-- Create a dropdown setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, get, set, disabled}
---@return table
function ConfigSystem:CreateDropdown(parent, info)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    
    -- Store the info for later use
    dropdown.info = info
    
    local label = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
    label:SetText(info.name)
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
    button:SetText(info.name)
    
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
                                control:SetPoint("TOPLEFT", 6, yOffset)
                                table.insert(content._trackedControls, { control = control, opt = opt })
                                if opt.type == "range" then
                                    yOffset = yOffset - 50
                                    contentHeight = contentHeight + 50
                                elseif opt.type == "select" then
                                    yOffset = yOffset - 42
                                    contentHeight = contentHeight + 42
                                elseif opt.type == "description" then
                                    yOffset = yOffset - 40
                                    contentHeight = contentHeight + 40
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

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.ConfigSystem = ConfigSystem

return ConfigSystem

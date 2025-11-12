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

-- Create a checkbox setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, get, set}
---@return table
function ConfigSystem:CreateCheckbox(parent, info)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox.Text:SetText(info.name)
    checkbox.tooltipText = info.desc
    
    -- Store the info for later use
    checkbox.info = info
    
    checkbox:SetScript("OnShow", function(self)
        local value = self.info.get()
        self:SetChecked(value)
    end)
    
    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        self.info.set(nil, checked and true or false)
        -- Force update to ensure visual state matches stored value
        self:SetChecked(self.info.get())
    end)
    
    return checkbox
end

-- Create a slider setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, min, max, step, get, set}
---@return table
function ConfigSystem:CreateSlider(parent, info)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider.Text:SetText(info.name)
    slider.tooltipText = info.desc
    
    slider:SetMinMaxValues(info.min, info.max)
    slider:SetValueStep(info.step)
    slider:SetObeyStepOnDrag(true)
    
    -- Store the info for later use
    slider.info = info
    
    -- Value text
    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    slider.valueText = valueText
    
    slider:SetScript("OnShow", function(self)
        local value = self.info.get()
        self:SetValue(value)
        self.valueText:SetText(string.format("%.2f", value))
    end)
    
    slider:SetScript("OnValueChanged", function(self, value)
        self.valueText:SetText(string.format("%.2f", value))
        self.info.set(nil, value)
    end)
    
    return slider
end

-- Create a dropdown setting
---@param parent table Parent category or frame
---@param info table Setting info {name, desc, values, get, set}
---@return table
function ConfigSystem:CreateDropdown(parent, info)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    
    -- Store the info for later use
    dropdown.info = info
    
    local label = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 16, 3)
    label:SetText(info.name)
    dropdown.label = label
    
    UIDropDownMenu_SetWidth(dropdown, 150)
    
    local function OnClick(self)
        dropdown.info.set(nil, self.value)
        UIDropDownMenu_SetText(dropdown, self:GetText())
    end
    
    local function Initialize(self, level)
        for value, text in pairs(dropdown.info.values) do
            local item = UIDropDownMenu_CreateInfo()
            item.text = text
            item.value = value
            item.func = OnClick
            UIDropDownMenu_AddButton(item, level)
        end
    end
    
    UIDropDownMenu_Initialize(dropdown, Initialize)
    
    dropdown:SetScript("OnShow", function(self)
        local currentValue = self.info.get()
        UIDropDownMenu_SetText(self, self.info.values[currentValue] or currentValue)
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
    button:SetWidth(200)
    button:SetHeight(22)
    button.tooltipText = info.desc
    
    button:SetScript("OnClick", function(self)
        info.func()
    end)
    
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
    
    -- Process option groups
    if options.args then
        for groupKey, group in pairs(options.args) do
            if group.type == "group" then
                -- Create group header
                local header = self:CreateHeader(content, group.name)
                header:SetPoint("TOPLEFT", 6, yOffset)
                yOffset = yOffset - 30
                contentHeight = contentHeight + 30
                
                -- Process group args
                if group.args then
                    for key, opt in pairs(group.args) do
                        local control = self:CreateControl(content, opt)
                        if control then
                            control:SetPoint("TOPLEFT", 6, yOffset)
                            if opt.type == "range" then
                                yOffset = yOffset - 60 -- Sliders need more space
                                contentHeight = contentHeight + 60
                            else
                                yOffset = yOffset - 40
                                contentHeight = contentHeight + 40
                            end
                        end
                    end
                end
                
                yOffset = yOffset - 10 -- Extra space between groups
                contentHeight = contentHeight + 10
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
    end
    return nil
end

-- Open the settings panel
function ConfigSystem:Open()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel) -- Call twice for legacy API bug
    end
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.ConfigSystem = ConfigSystem

return ConfigSystem

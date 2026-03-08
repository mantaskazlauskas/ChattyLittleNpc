# Settings API & Options Panel (10.0+)

> Modern Settings API for registering addon options in the game settings UI.
> Source: https://warcraft.wiki.gg/wiki/Create_a_WoW_AddOn_in_15_Minutes

## Quick Setup (Canvas Layout)

```lua
-- Create options panel frame
local panel = CreateFrame("Frame")
panel.name = "MyAddon"

-- Add UI elements to panel
local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
cb:SetPoint("TOPLEFT", 20, -20)
cb.Text:SetText("Enable feature")
cb:SetChecked(MyAddonDB.enabled)
cb:HookScript("OnClick", function()
    MyAddonDB.enabled = cb:GetChecked()
end)

-- Register with Settings system
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
category.ID = panel.name
Settings.RegisterAddOnCategory(category)

-- Open programmatically
Settings.OpenToCategory(panel.name)
```

## Modern Settings API (Declarative)

```lua
-- Register a vertical layout category
local category = Settings.RegisterVerticalLayoutCategory("MyAddon")

-- Checkbox setting
local setting = Settings.RegisterAddOnSetting(
    category,
    "enabled",          -- variable name
    "enabled",          -- display variable
    MyAddonDB,          -- database table
    type(true),         -- value type
    "Enable MyAddon",   -- display name
    true                -- default value
)
Settings.CreateCheckbox(category, setting, "Toggle the addon on/off")

-- Slider setting
local sliderSetting = Settings.RegisterAddOnSetting(
    category, "volume", "volume", MyAddonDB, type(0.8), "Volume", 0.8
)
local options = Settings.CreateSliderOptions(0, 1, 0.05)  -- min, max, step
options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
    return string.format("%.0f%%", value * 100)
end)
Settings.CreateSlider(category, sliderSetting, options, "Adjust volume level")

-- Dropdown setting
local dropSetting = Settings.RegisterAddOnSetting(
    category, "mode", "mode", MyAddonDB, type("auto"), "Mode", "auto"
)
local function GetOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("auto", "Automatic")
    container:Add("manual", "Manual")
    container:Add("off", "Disabled")
    return container:GetData()
end
Settings.CreateDropdown(category, dropSetting, GetOptions, "Select operating mode")

-- Register and open
Settings.RegisterAddOnCategory(category)
-- /run Settings.OpenToCategory("MyAddon")
```

## Settings API Functions

```lua
-- Category registration
Settings.RegisterVerticalLayoutCategory(name) : category
Settings.RegisterCanvasLayoutCategory(frame, name, title) : category
Settings.RegisterAddOnCategory(category)

-- Setting registration
Settings.RegisterAddOnSetting(category, variable, display, db, valueType, name, default) : setting

-- Control creation
Settings.CreateCheckbox(category, setting, tooltip)
Settings.CreateSlider(category, setting, options, tooltip)
Settings.CreateDropdown(category, setting, getOptionsFunc, tooltip)

-- Slider options
Settings.CreateSliderOptions(min, max, step) : options

-- Navigation
Settings.OpenToCategory(categoryName)
```

## Legacy InterfaceOptions Templates

Still work but prefer the modern Settings API:

```lua
-- Checkbox
local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
cb.Text:SetText("Label")
cb:SetChecked(value)
cb:HookScript("OnClick", function()
    -- save cb:GetChecked()
end)

-- Button
local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
btn:SetText("Click Me")
btn:SetSize(100, 30)
btn:SetScript("OnClick", function()
    -- handle click
end)

-- Slider
local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
slider:SetMinMaxValues(0, 100)
slider:SetValue(50)
slider:SetValueStep(1)
slider.Text:SetText("My Slider")
slider.Low:SetText("0")
slider.High:SetText("100")
slider:SetScript("OnValueChanged", function(self, value)
    -- handle change
end)
```

## Complete Options Panel Example

```lua
-- In ADDON_LOADED handler:
local function InitOptions(db, defaults)
    local panel = CreateFrame("Frame")
    panel.name = "MyAddon"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("MyAddon Options")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Configure MyAddon settings below.")
    desc:SetJustifyH("LEFT")

    local yOffset = -70

    -- Checkboxes
    for _, opt in ipairs({
        { key = "enabled", label = "Enable addon" },
        { key = "showFrame", label = "Show display frame" },
        { key = "autoPlay", label = "Auto-play voiceovers" },
    }) do
        local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, yOffset)
        cb.Text:SetText(opt.label)
        cb:SetChecked(db[opt.key])
        cb:HookScript("OnClick", function()
            db[opt.key] = cb:GetChecked()
        end)
        yOffset = yOffset - 30
    end

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", 20, yOffset - 20)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetSize(140, 25)
    resetBtn:SetScript("OnClick", function()
        for k, v in pairs(defaults) do
            db[k] = v
        end
        -- Refresh UI...
    end)

    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
    cat.ID = panel.name
    Settings.RegisterAddOnCategory(cat)
    return panel
end
```

## Opening Settings

```lua
-- From slash command
SLASH_MYADDON1 = "/myaddon"
SlashCmdList.MYADDON = function(msg)
    if msg == "" or msg == "config" then
        Settings.OpenToCategory("MyAddon")
    end
end

-- From addon compartment
-- In TOC:
-- ## AddonCompartmentFunc: MyAddon_OnCompartmentClick
function MyAddon_OnCompartmentClick()
    Settings.OpenToCategory("MyAddon")
end
```

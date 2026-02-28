# Common Addon Patterns & Best Practices

> Idiomatic patterns for WoW addon development targeting Midnight (12.0.1).

## Addon Initialization Pattern

```lua
local ADDON_NAME, ns = ...  -- Addon name and private namespace table

-- Private namespace is shared across all files in the addon
ns.version = "1.0.0"
ns.db = nil  -- Will hold SavedVariables reference

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            -- Initialize SavedVariables
            MyAddonDB = MyAddonDB or {}
            ns.db = MyAddonDB
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        -- Safe to use all APIs here
        ns:Initialize()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

function ns:Initialize()
    -- Addon fully ready
    print(ADDON_NAME .. " loaded!")
end
```

## Private Namespace (Sharing Data Between Files)

The `...` vararg in the first file-scope line returns the addon name and a shared table:

```lua
-- File1.lua
local ADDON_NAME, ns = ...
ns.Utils = {}
function ns.Utils.FormatName(name)
    return "|cff00ff00" .. name .. "|r"
end

-- File2.lua
local ADDON_NAME, ns = ...
local formatted = ns.Utils.FormatName("Player")
```

## Event Handler Dispatch Pattern

```lua
local ADDON_NAME, ns = ...
local EventHandler = CreateFrame("Frame")
ns.EventHandler = EventHandler

local handlers = {}

function handlers:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end
    -- init
end

function handlers:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        -- first login or /reload
    end
end

function handlers:CHAT_MSG_MONSTER_SAY(text, playerName, ...)
    -- NPC said something
end

EventHandler:SetScript("OnEvent", function(self, event, ...)
    if handlers[event] then
        handlers[event](self, ...)
    end
end)

for event in pairs(handlers) do
    EventHandler:RegisterEvent(event)
end
```

## Slash Command Registration

```lua
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"

function SlashCmdList.MYADDON(msg, editBox)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "config" or cmd == "options" then
        -- Open options
    elseif cmd == "reset" then
        -- Reset settings
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        print("Debug mode:", ns.db.debug and "ON" or "OFF")
    else
        print("Usage: /myaddon [config|reset|debug]")
    end
end
```

## Throttling / Debouncing

```lua
-- Throttle: Execute at most once per interval
local function Throttle(interval, func)
    local timer = 0
    return function(...)
        local now = GetTime()
        if now - timer >= interval then
            timer = now
            return func(...)
        end
    end
end

-- Usage
local throttledUpdate = Throttle(0.5, function()
    -- expensive operation
end)
frame:SetScript("OnUpdate", function(self, elapsed)
    throttledUpdate()
end)

-- Debounce: Wait until input stops for interval
local function Debounce(interval, func)
    local timer = nil
    return function(...)
        local args = {...}
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(interval, function()
            func(unpack(args))
        end)
    end
end
```

## Mixin Pattern

```lua
-- Define a mixin
MyMixin = {}

function MyMixin:Init(name)
    self.name = name
    self.data = {}
end

function MyMixin:GetName()
    return self.name
end

function MyMixin:AddData(key, value)
    self.data[key] = value
end

-- Apply mixin to frame
local frame = CreateFrame("Frame")
Mixin(frame, MyMixin)
frame:Init("MyFrame")
```

## Color Codes & Formatting

```lua
-- Color codes in strings
local red = "|cFFFF0000Red Text|r"
local green = "|cFF00FF00Green Text|r"
local classColor = "|cFF" .. "FF7C0A" .. "Druid|r"

-- WrapTextInColorCode (FrameXML helper)
local colored = WrapTextInColorCode("Hello", "FF00FF00")

-- Texture in strings
local icon = "|TInterface/Icons/INV_Misc_QuestionMark:16|t"
local chat = icon .. " Click here"

-- Hyperlinks
local itemLink = "|cff0070dd|Hitem:12345::::::::60:::::|h[Item Name]|h|r"
```

## Combat Lockdown Safety

```lua
local pendingActions = {}

local function SafeAction(action)
    if InCombatLockdown() then
        table.insert(pendingActions, action)
        return false
    end
    action()
    return true
end

-- Execute pending actions when combat ends
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:HookScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        for _, action in ipairs(pendingActions) do
            action()
        end
        table.wipe(pendingActions)
    end
end)
```

## Frame Pool Pattern

```lua
-- Reuse frames instead of creating new ones (frames can't be GC'd)
local pool = CreateFramePool("Frame", UIParent, "MyTemplate")

-- Acquire a frame
local frame = pool:Acquire()
frame:Show()
frame:SetPoint("CENTER")

-- Release back to pool
pool:Release(frame)
-- or release all
pool:ReleaseAll()
```

## Options Panel (Settings API)

```lua
-- Modern Settings API (10.0+)
local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

-- Add a checkbox
local variable = "MyAddonEnabled"
local name = "Enable MyAddon"
local tooltip = "Toggle the addon on/off"
local defaultValue = true

local setting = Settings.RegisterAddOnSetting(category, variable, variable, ns.db, type(defaultValue), name, defaultValue)
Settings.CreateCheckbox(category, setting, tooltip)

-- Add a slider
local sliderSetting = Settings.RegisterAddOnSetting(category, "volume", "volume", ns.db, type(0.8), "Volume", 0.8)
local sliderOptions = Settings.CreateSliderOptions(0, 1, 0.05)
sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
    return string.format("%.0f%%", value * 100)
end)
Settings.CreateSlider(category, sliderSetting, sliderOptions, "Adjust volume")

Settings.RegisterAddOnCategory(category)
```

## Tooltip Pattern

```lua
-- Show tooltip on frame hover
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Title", 1, 1, 1)
    GameTooltip:AddLine("Description text", 0.8, 0.8, 0.8, true)  -- true = wrap
    GameTooltip:AddDoubleLine("Left", "Right", 1, 1, 0, 0, 1, 0)
    GameTooltip:Show()
end)

frame:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)
```

## Secure Hook Pattern

```lua
-- Observe Blizzard function calls without causing taint
hooksecurefunc("TargetUnit", function(name)
    print("Player targeted:", name)
end)

hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID, text, confirmed)
    print("Gossip option selected:", optionID)
end)

-- Hook a widget method
hooksecurefunc(GameTooltip, "SetUnit", function(self, unit)
    -- Add custom lines to unit tooltip
    GameTooltip:AddLine("Custom info here", 0.5, 1, 0.5)
    GameTooltip:Show()
end)
```

## Addon Communication

```lua
-- Register prefix (max 16 chars, must be done once)
C_ChatInfo.RegisterAddonMessagePrefix("MyAddon")

-- Send message
C_ChatInfo.SendAddonMessage("MyAddon", "hello world", "PARTY")
-- chatType: "PARTY", "RAID", "GUILD", "WHISPER" (needs target), "CHANNEL" (needs channelID)

-- Receive message
frame:RegisterEvent("CHAT_MSG_ADDON")
function handlers:CHAT_MSG_ADDON(prefix, message, channel, sender, ...)
    if prefix == "MyAddon" then
        print("Received from", sender, ":", message)
    end
end
```

## Localization Pattern

```lua
local L = {}
ns.L = L

-- Default (English) strings
setmetatable(L, { __index = function(t, key)
    return key  -- Fallback: return key as string
end})

-- Override for specific locale
local locale = GetLocale()
if locale == "deDE" then
    L["Hello"] = "Hallo"
    L["Settings"] = "Einstellungen"
elseif locale == "frFR" then
    L["Hello"] = "Bonjour"
    L["Settings"] = "Paramètres"
end

-- Usage
print(L["Hello"])  -- "Hello" in English, "Hallo" in German
```

## Error Handling

```lua
-- Safe function calls
local success, result = pcall(function()
    -- potentially dangerous code
    return SomethingThatMightFail()
end)

if not success then
    print("Error:", result)
end

-- With xpcall for stack trace
local success, result = xpcall(function()
    return SomethingRisky()
end, function(err)
    return err .. "\n" .. debugstack(2)
end)
```

## Performance Tips

1. **Cache frequently used globals**: `local GetTime = GetTime`
2. **Avoid OnUpdate when possible**: Use C_Timer.After/NewTicker
3. **Throttle expensive operations**: Don't update every frame
4. **Use RegisterUnitEvent**: Filters events to specific units
5. **Unregister events when not needed**: Clean up when hiding frames
6. **Reuse tables**: `table.wipe(t)` instead of `t = {}`
7. **Use frame pools**: `CreateFramePool` for dynamic frame creation
8. **Minimize string concatenation**: Use `string.format` or `table.concat`
9. **Profile with /etrace and C_AddOnProfiler**: Identify bottlenecks

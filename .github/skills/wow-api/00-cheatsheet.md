# WoW Addon Cheat Sheet — Quick Lookup

> One-page reference for the most commonly needed APIs, patterns, and gotchas.
> For deep dives, see the numbered files in this directory.

## Addon Skeleton

```lua
-- MyAddon.toc
-- ## Interface: 120001
-- ## Title: MyAddon
-- ## SavedVariables: MyAddonDB
-- MyAddon.lua

-- MyAddon.lua
local ADDON_NAME, ns = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name == ADDON_NAME then
        MyAddonDB = MyAddonDB or { enabled = true }
        ns.db = MyAddonDB
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_MYADDON1 = "/myaddon"
SlashCmdList.MYADDON = function(msg) print("Hello!") end
```

## Top 20 API Functions

```lua
-- Frames
CreateFrame(type [, name, parent, template, id]) : frame
frame:SetPoint(point [, relativeTo, relativePoint, x, y])
frame:SetSize(width, height)
frame:Show() / frame:Hide() / frame:SetShown(bool)

-- Events
frame:RegisterEvent("EVENT_NAME")
frame:UnregisterEvent("EVENT_NAME")
frame:SetScript("OnEvent", function(self, event, ...) end)

-- Timers
C_Timer.After(seconds, callback)
C_Timer.NewTicker(seconds, callback [, iterations]) : ticker
ticker:Cancel()

-- Unit info
UnitName(unitID) : name, realm
UnitGUID(unitID) : guid
UnitSex(unitID) : sex  -- 1=unknown, 2=male, 3=female

-- Sound
PlaySoundFile(path, channel) : willPlay, soundHandle
StopSound(soundHandle, fadeout)
C_Sound.IsPlaying(soundHandle) : bool

-- Output
print(...)
GetTime() : seconds  -- High-precision game time
```

## Event Lifecycle (Loading Order)

```
Lua files execute          → set up frames, register events
SavedVariables load        → ADDON_LOADED per addon
All addons loaded          → PLAYER_LOGIN
Entering world             → PLAYER_ENTERING_WORLD
Combat starts              → PLAYER_REGEN_DISABLED
Combat ends                → PLAYER_REGEN_ENABLED
Logging out                → PLAYER_LOGOUT (last chance to save)
```

## NPC Dialog Events (ChattyLittleNpc Core)

```
GOSSIP_SHOW       → C_GossipInfo.GetText(), UnitName("npc")
QUEST_GREETING    → GetGreetingText()
QUEST_DETAIL      → GetQuestText(), GetTitleText()
QUEST_PROGRESS    → GetProgressText()
QUEST_COMPLETE    → GetRewardText()
QUEST_FINISHED    → (any dialog closed)
GOSSIP_CLOSED     → (gossip closed)
ITEM_TEXT_READY   → ItemTextGetText()
```

## GUID Parsing

```lua
local guid = UnitGUID("target")
-- "Creature-0-1465-0-2105-448-000043F59F"
local type, _, server, instance, zone, npcID, spawn = strsplit("-", guid)
npcID = tonumber(npcID)  -- 448
```

## Frame Anchoring Cheat

```lua
frame:SetPoint("CENTER")                            -- Center of parent
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)  -- Top-left with margin
frame:SetPoint("TOP", other, "BOTTOM", 0, -5)       -- Below another frame
frame:SetAllPoints(parent)                           -- Fill parent
frame:ClearAllPoints()                               -- Reset before re-anchoring
```

## Common Gotchas

| Gotcha | Solution |
|--------|----------|
| SavedVariables nil on load | Check in ADDON_LOADED, not at file scope |
| `frame:SetScript` replaces handler | Use `frame:HookScript` on Blizzard frames |
| Protected frame in combat | Check `InCombatLockdown()` first; queue changes for PLAYER_REGEN_ENABLED |
| Frames never garbage collected | Use `CreateFramePool()` to reuse |
| Trig functions use degrees | `math.sin(degrees)` not radians |
| No file I/O or os/debug libs | Use SavedVariables for persistence |
| `|` in chat = escaped | Use `\124` in macros/chat for pipe character |
| Stale data from C_Item.GetItemInfo | May return nil; use `C_Item.RequestLoadItemDataByID()` |
| OnUpdate fires every frame | Throttle with elapsed time or use C_Timer |

## Color Quick Reference

```lua
-- Inline color
"|cFFFF0000Red|r"
"|cFF00FF00Green|r"

-- Class colors
RAID_CLASS_COLORS["WARRIOR"].colorStr  -- "FFC69B6D"

-- Quality colors
"|cnIQ4:Epic Text|r"  -- 0=Poor,1=Common,2=Uncommon,3=Rare,4=Epic,5=Legendary
```

## Secure Hooking (Safe)

```lua
-- Hook global function (runs AFTER original)
hooksecurefunc("TargetUnit", function(name) print("targeted", name) end)

-- Hook method on object
hooksecurefunc(GameTooltip, "SetUnit", function(self, unit) ... end)

-- Hook widget script (runs AFTER existing handler)
frame:HookScript("OnShow", function(self) ... end)
```

## Slash Command Template

```lua
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"
SlashCmdList.MYADDON = function(msg)
    local cmd = msg:lower():trim()
    if cmd == "config" then Settings.OpenToCategory("MyAddon")
    elseif cmd == "reset" then MyAddonDB = nil; ReloadUI()
    else print("Usage: /myaddon [config|reset]")
    end
end
```

## Debug Commands

```
/dump expression        -- Print Lua value
/fstack                 -- Show frames under cursor
/etrace                 -- Event trace panel
/reload                 -- Reload UI
/console scriptErrors 1 -- Show error popups
/console taintLog 1     -- Log taint (check Logs/taint.log)
```

## File Locations

```
WoW/_retail_/Interface/AddOns/MyAddon/        -- Addon files
WTF/Account/NAME/SavedVariables/MyAddon.lua   -- Account-wide saved vars
WTF/Account/NAME/Realm/Char/SavedVariables/   -- Per-character saved vars
Logs/taint.log                                 -- Taint log (when enabled)
```

## Interface Version

```lua
-- Current Midnight: 120001
/dump (select(4, GetBuildInfo()))  -- Get current interface version
```

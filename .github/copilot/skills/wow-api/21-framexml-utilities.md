# FrameXML Utilities & GUIDs

> FrameXML helper functions, mixins, pools, formatting, and GUID parsing.
> Source: https://warcraft.wiki.gg/wiki/FrameXML_functions, https://warcraft.wiki.gg/wiki/GUID

## Mixin System

```lua
-- Copy methods from one or more tables into an existing object
Mixin(existingTable, MixinA, MixinB, ...)

-- Create a new table with mixed-in methods
local obj = CreateFromMixins(MixinA, MixinB, ...)

-- Example
MyMixin = {}
function MyMixin:Init(name)
    self.name = name
end
function MyMixin:GetName()
    return self.name
end

local obj = CreateFromMixins(MyMixin)
obj:Init("Test")

-- Apply to existing frame
local frame = CreateFrame("Frame")
Mixin(frame, MyMixin)
frame:Init("MyFrame")
```

## Object Pools (Frame Reuse)

Frames can never be garbage collected — always reuse them via pools.

```lua
-- Frame pool
local pool = CreateFramePool("Frame", UIParent, "MyTemplate", function(pool, frame)
    -- Optional resetter: called when frame is released
    frame:Hide()
    frame:ClearAllPoints()
end)

local frame = pool:Acquire()   -- Get a frame (creates if needed)
frame:Show()
pool:Release(frame)             -- Return to pool
pool:ReleaseAll()               -- Return all frames
pool:EnumerateActive()          -- Iterator over active frames

-- Texture pool
local texPool = CreateTexturePool(parentFrame, "ARTWORK", 0, "MyTextureTemplate")
local tex = texPool:Acquire()
texPool:Release(tex)

-- FontString pool
local fontPool = CreateFontStringPool(parentFrame, "OVERLAY", 0, "GameFontNormal")

-- Generic object pool
local objPool = CreateObjectPool(
    function() return {} end,             -- creator
    function(pool, obj) wipe(obj) end     -- resetter
)

-- Frame pool collection (multiple frame types)
local collection = CreateFramePoolCollection()
collection:CreatePool("Frame", parent, "Template1")
collection:CreatePool("Button", parent, "Template2")
local frame = collection:Acquire("Frame")
collection:ReleaseAll()
```

## Color Utilities

```lua
-- Create color objects (ColorMixin)
local color = CreateColor(1, 0.5, 0, 1)    -- RGBA
color:GetRGB()                               -- r, g, b
color:GetRGBA()                              -- r, g, b, a
color:GenerateHexColor()                     -- "FFFF8000"
color:WrapTextInColorCode("text")            -- "|cFFFF8000text|r"
color:IsEqualTo(otherColor)                  -- boolean

-- From hex
local c = CreateColorFromHexString("FFFF8000")

-- From bytes (0-255)
local c = CreateColorFromBytes(255, 128, 0, 255)

-- Class colors
local color = GetClassColor("WARRIOR")       -- r, g, b, hex
local colorObj = GetClassColorObj("WARRIOR")  -- ColorMixin
local text = GetClassColoredTextForUnit("player", "Name")

-- Faction colors
local color = GetFactionColor("Alliance")
```

## Formatting Utilities

```lua
FormatLargeNumber(1234567)          -- "1,234,567"
AbbreviateLargeNumbers(1234567)     -- "1.2M"
AbbreviateNumbers(1234567)          -- "1234.6k"
GetMoneyString(12345, true)         -- "1g 23s 45c"
FormatPercentage(0.756)             -- "75.6%"
FormatPercentage(0.756, true)       -- "76%"
FormatFraction(3, 5)                -- "3/5"
FormatValueWithSign(42)             -- "+42"
FormatValueWithSign(-10)            -- "-10"
GetCurrencyString(currencyID, amount, colorCode, abbreviate)

-- Time formatting
SecondsToTime(3661)                 -- "1 Hr 1 Min 1 Sec"
SecondsToTime(3661, true)           -- "1 Hr 1 Min"
SecondsToTimeAbbrev(3661)           -- "1 Hr"
SecondsToClock(3661)                -- "1:01:01"

-- SecondsFormatterMixin (advanced)
local formatter = CreateFromMixins(SecondsFormatterMixin)
formatter:Init(minInterval, maxInterval, roundUp)
formatter:Format(seconds)
```

## EventUtil Helpers

```lua
-- Wait for addon to load, then call back
EventUtil.ContinueOnAddOnLoaded("MyAddon", function()
    -- MyAddon's saved variables are ready
end)

-- Wait for all variables to load
EventUtil.ContinueOnVariablesLoaded(function()
    -- All addon variables loaded
end)

-- Wait for multiple events, then call back
EventUtil.ContinueAfterAllEvents(function()
    -- Both events have fired
end, "PLAYER_ENTERING_WORLD", "ADDON_LOADED")

-- Register for an event once (auto-unregisters)
EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
    -- Fires only once
end)
```

## Fade Utilities

```lua
UIFrameFadeIn(frame, duration, startAlpha, endAlpha)
UIFrameFadeOut(frame, duration, startAlpha, endAlpha)

-- Example: fade in over 0.5 seconds
UIFrameFadeIn(myFrame, 0.5, 0, 1)

-- Example: fade out over 0.3 seconds then hide
UIFrameFadeOut(myFrame, 0.3, 1, 0)
```

## Table Utilities (CopyTable, etc.)

```lua
CopyTable(source)                   -- Deep copy a table
MergeTable(dest, source)            -- Shallow merge source into dest
tInvert(table)                      -- Swap keys and values {a=1,b=2} → {[1]="a",[2]="b"}
tContains(table, value)             -- Returns true if value is in table
tInsertUnique(table, value)         -- Insert only if not already present
tAppendAll(dest, source)            -- Append all values from source array to dest
tFilter(table, pred, extractKey)    -- Filter table by predicate
tDeleteItem(table, value)           -- Remove first occurrence of value
```

## Easing Functions

```lua
EasingUtil.InQuadratic(t)       -- Accelerating
EasingUtil.OutQuadratic(t)      -- Decelerating
EasingUtil.InOutQuadratic(t)    -- Accel then decel
EasingUtil.InCubic(t)           -- Cubic ease in
EasingUtil.OutCubic(t)          -- Cubic ease out
EasingUtil.InOutCubic(t)        -- Cubic in-out
-- Also: InQuartic, OutQuartic, InOutQuartic, InQuintic, OutQuintic, InOutQuintic
-- t is 0.0 to 1.0 (percentage of animation)
```

## AnchorUtil

```lua
-- Create an anchor specification
local anchor = AnchorUtil.CreateAnchor("TOPLEFT", parent, "TOPLEFT", 10, -10)

-- Grid layout
local layout = AnchorUtil.CreateGridLayout(GridLayoutMixin.Direction.TopLeftToBottomRight, 4, 5, 5)
AnchorUtil.GridLayout(frames, initialAnchor, layout)
```

---

## GUIDs (Globally Unique Identifiers)

### Format

```
[UnitType]-[Zero]-[ServerID]-[InstanceID]-[ZoneUID]-[ID]-[SpawnUID]
```

### GUID Types

| Type | Format | Example |
|------|--------|---------|
| **Player** | `Player-[serverID]-[playerUID]` | `Player-970-0002FD64` |
| **Creature** | `Creature-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]` | `Creature-0-1465-0-2105-448-000043F59F` |
| **Pet** | `Pet-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]` | `Pet-0-4234-0-6610-165189-0202F859E9` |
| **GameObject** | `GameObject-0-[serverID]-[instanceID]-[zoneUID]-[objectID]-[spawnUID]` | `GameObject-0-970-0-41-206845-00001B3A2F` |
| **Vehicle** | `Vehicle-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]` | `Vehicle-0-1465-0-2105-12345-000043F59F` |
| **Vignette** | `Vignette-0-[serverID]-[instanceID]-[zoneUID]-[vignetteID]-[spawnUID]` | `Vignette-0-970-1116-7-340-0017CAE465` |
| **BattlePet** | `BattlePet-0-[ID]` | `BattlePet-0-00000338F951` |
| **Item** | `Item-[serverID]-0-[spawnUID]` | `Item-1598-0-4000000A369860E1` |
| **Cast** | `Cast-[type]-[serverID]-[instanceID]-[zoneUID]-[spellID]-[castUID]` | `Cast-3-4170-0-8-84714-000CB03025` |

### Parsing GUIDs

```lua
-- Extract NPC ID from creature GUID
local guid = UnitGUID("target")
local unitType, _, serverID, instanceID, zoneUID, npcID, spawnUID = strsplit("-", guid)
npcID = tonumber(npcID)

-- Helper: get NPC ID from any unit
local function GetNpcID(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local type, _, _, _, _, id = strsplit("-", guid)
    if type == "Creature" or type == "Vehicle" or type == "Pet" then
        return tonumber(id)
    end
    return nil
end

-- Check if GUID is a player
C_PlayerInfo.GUIDIsPlayer(guid) : isPlayer

-- Get player info from GUID
local info = C_PlayerInfo.GetInfoByGUID(guid)
-- info: { className, classFilename, classID, raceName, raceFilename, raceID, sex, name, realm }
```

### GUID Rules

- **Creatures**: New GUID per spawn; recycled after server restart
- **Players**: Permanent GUID; changes on faction/server transfer
- **Pets**: New GUID each summon
- **Rename**: Does NOT change GUID
- **Cross-server**: Player GUIDs are unique across servers

### Spawn UID Decoding

For Creature/Vehicle/GameObject GUIDs, the low 23 bits of spawnUID encode spawn time:

```lua
local spawnEpoch = GetServerTime() - (GetServerTime() % 2^23)
local spawnOffset = bit.band(tonumber(string.sub(spawnUID, 5), 16), 0x7fffff)
local spawnTime = spawnEpoch + spawnOffset
if spawnTime > GetServerTime() then
    spawnTime = spawnTime - ((2^23) - 1)
end
print("Spawned at:", date("%Y-%m-%d %H:%M:%S", spawnTime))
```

## Anchor Points Reference

```
TOPLEFT ─── TOP ─── TOPRIGHT
   │                    │
  LEFT ── CENTER ── RIGHT
   │                    │
BOTTOMLEFT  BOTTOM  BOTTOMRIGHT
```

### Anchor Coordinate System

- **Origin**: Bottom-left of screen
- **X**: Positive = right
- **Y**: Positive = up
- Anchoring TOPLEFT of child to TOPLEFT of parent with offset (10, -10) places child 10px right, 10px down from parent's top-left

### Common Anchoring Patterns

```lua
-- Center on screen
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

-- Top-left corner with margin
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)

-- Below another frame with gap
frame:SetPoint("TOP", otherFrame, "BOTTOM", 0, -5)

-- Fill parent
frame:SetAllPoints(parent)

-- Right of another frame
frame:SetPoint("LEFT", otherFrame, "RIGHT", 5, 0)

-- Two-point anchor (stretches width)
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
frame:SetHeight(30)

-- Four-point anchor (fills with margin)
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
```

### Anchoring During Load

1. **XML anchors** are set during file parsing (before VARIABLES_LOADED)
2. **Layout cache** may overwrite anchors for user-placed frames at PLAYER_ENTERING_WORLD
3. Use `frame:SetDontSavePosition(true)` to prevent layout cache interference
4. For consistent positioning, set anchors in PLAYER_ENTERING_WORLD or later

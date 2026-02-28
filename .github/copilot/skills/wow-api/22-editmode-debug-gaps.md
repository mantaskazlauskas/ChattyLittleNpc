# Edit Mode, Debugging & Missing API Gap-Fill

> APIs used by ChattyLittleNpc that weren't covered elsewhere, plus debugging techniques.

## C_EditMode — Edit Mode API (10.0+)

Edit Mode lets players customize built-in UI frame positions/sizes. Addons can integrate
by hooking into the edit mode lifecycle and storing per-layout frame positions.

### Core Functions

```lua
C_EditMode.GetLayouts() : layouts
-- Returns all custom layouts (NOT default layouts)
-- Each layout: { layoutName, layoutType, systems = { ... } }
-- Each system: { settings, anchorInfo, isInDefaultPosition, systemIndex, system }

C_EditMode.ConvertLayoutInfoToString(layoutInfo) : string
-- Serialize a layout to an export string

C_EditMode.ConvertStringToLayoutInfo(string) : layoutInfo
-- Deserialize an import string to layout info

C_EditMode.SaveLayouts(layouts)
-- Save modified layouts

C_EditMode.SetActiveLayout(layoutIndex)
-- Switch to a specific layout

C_EditMode.IsValidLayoutName(name) : valid
-- Check if layout name is valid

C_EditMode.OnEditModeExit()
-- Signal edit mode exit
```

### Hooking Edit Mode

```lua
-- Hook enter/exit
hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
    -- Edit mode entered
    myFrame:EnableEditMode()
end)

hooksecurefunc(EditModeManagerFrame, "OnEditModeExit", function()
    -- Edit mode exited
    myFrame:DisableEditMode()
end)

-- Events
-- EDIT_MODE_LAYOUTS_UPDATED fires when layouts change
```

### Edit Mode Layout Structure

```lua
{
    layoutName = "MyLayout",
    layoutType = 3,  -- 3 = custom
    systems = {
        [1] = {
            system = 0,         -- 0 = ActionBar
            systemIndex = 1,    -- Which action bar (1-8)
            isInDefaultPosition = true,
            anchorInfo = {
                point = "BOTTOM",
                relativeTo = "UIParent",
                relativePoint = "BOTTOM",
                offsetX = 0,
                offsetY = 0,
            },
            settings = {
                [1] = { setting = 0, value = 0 },  -- Orientation
                [2] = { setting = 1, value = 2 },  -- Rows
                -- etc.
            },
        },
    }
}
```

### Per-Layout Frame Positioning (ChattyLittleNpc Pattern)

```lua
-- Store position per layout index
local function GetCurrentLayoutIndex()
    local layouts = C_EditMode.GetLayouts()
    -- Determine active layout...
    return activeIndex
end

local function SaveFramePosition(frame)
    local idx = GetCurrentLayoutIndex()
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    db.editModeLayouts[idx] = {
        point = point, relativePoint = relativePoint,
        x = x, y = y,
        width = frame:GetWidth(), height = frame:GetHeight(),
    }
end

local function RestoreFramePosition(frame)
    local idx = GetCurrentLayoutIndex()
    local saved = db.editModeLayouts[idx]
    if saved then
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
        frame:SetSize(saved.width, saved.height)
    end
end
```

---

## C_CVar — Console Variable Access

```lua
-- These are the C_ namespace versions (equivalent to GetCVar/SetCVar)
C_CVar.GetCVar(name) : value        -- Returns string
C_CVar.SetCVar(name, value) : bool  -- Returns success
C_CVar.GetCVarBool(name) : bool     -- Returns boolean
C_CVar.GetCVarDefault(name) : value -- Returns default string
C_CVar.RegisterCVar(name, default)  -- Register a custom CVar
```

---

## Quest Dialog Text Functions

> Full lifecycle reference: [23-npc-dialog-lifecycle.md](./23-npc-dialog-lifecycle.md)

```lua
-- Available during specific quest events (see file 23 for which event provides which function)
GetTitleText() : title              -- Quest title from dialog
GetQuestText() : text              -- QUEST_DETAIL body text
GetProgressText() : text           -- QUEST_PROGRESS body text
GetRewardText() : text             -- QUEST_COMPLETE body text
GetGreetingText() : text           -- QUEST_GREETING body text
GetObjectiveText() : text          -- Quest objective text
GetQuestID() : questID             -- Current quest in dialog
QuestGetAutoAccept() : autoAccept  -- Whether quest auto-accepts
```

## Other Missing Unit/Item Functions

```lua
-- Get creature display ID (for model rendering)
-- NOTE: No standalone API — use model:SetUnit("npc") or display info tables

-- Item text (books, letters)
ItemTextGetItem() : itemName
ItemTextGetText() : text
ItemTextGetPage() : page
ItemTextGetMaterial() : material
ItemTextHasNextPage() : hasNext
ItemTextPrevPage()
ItemTextNextPage()
```

---

## C_Item.GetItemInfoInstant

```lua
-- Synchronous item info (limited data but instant, no cache miss)
C_Item.GetItemInfoInstant(itemID) : itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID

-- vs C_Item.GetItemInfo which may return nil on first call (async)
```

---

## Common Blizzard Templates Reference

### Frame Templates

| Template | Type | Description |
|----------|------|-------------|
| `BackdropTemplate` | Frame | Frame with NineSlice backdrop |
| `TooltipBorderBackdropTemplate` | Frame | Tooltip-style border |
| `BasicFrameTemplate` | Frame | Standard panel with close button |
| `BasicFrameTemplateWithInset` | Frame | Panel with inset area |
| `PortraitFrameTemplate` | Frame | Panel with portrait circle |
| `ButtonFrameTemplate` | Frame | Panel with inset and bottom buttons |
| `InsetFrameTemplate` | Frame | Simple inset container |
| `ThinBorderTemplate` | Frame | Thin border decoration |
| `ModelSceneFrameTemplate` | ModelScene | Standard model scene setup |
| `ModelSceneActorTemplate` | Actor | Standard actor template |

### Button Templates

| Template | Description |
|----------|-------------|
| `UIPanelButtonTemplate` | Standard rectangular button |
| `UIPanelDynamicResizeButtonTemplate` | Auto-resizing button |
| `GameMenuButtonTemplate` | Wide game menu-style button |
| `MagicButtonTemplate` | Blue glowing button |
| `UICheckButtonTemplate` | Standard checkbox |
| `InterfaceOptionsCheckButtonTemplate` | Options panel checkbox (has .Text) |
| `ChatConfigCheckButtonTemplate` | Chat config checkbox variant |
| `UIRadioButtonTemplate` | Radio button |

### EditBox Templates

| Template | Description |
|----------|-------------|
| `InputBoxTemplate` | Standard single-line input |
| `InputBoxMultiLine` | Multi-line text input |
| `SearchBoxTemplate` | Search input with icon |
| `ChatFrameEditBoxTemplate` | Chat-style input |

### ScrollFrame Templates

| Template | Description |
|----------|-------------|
| `UIPanelScrollFrameTemplate` | Classic scrollbar frame |
| `ScrollFrameTemplate` | Modern scroll frame |
| `FauxScrollFrameTemplate` | Virtual scrolling (old pattern) |

### Font Objects

| Font Object | Size | Style |
|-------------|------|-------|
| `GameFontNormal` | 12 | Normal |
| `GameFontNormalSmall` | 10 | Normal |
| `GameFontNormalLarge` | 16 | Normal |
| `GameFontNormalHuge` | 20 | Normal |
| `GameFontHighlight` | 12 | Highlight (white) |
| `GameFontHighlightSmall` | 10 | Highlight |
| `GameFontHighlightLarge` | 16 | Highlight |
| `GameFontDisable` | 12 | Disabled (gray) |
| `GameFontGreen` | 12 | Green |
| `GameFontRed` | 12 | Red |
| `GameFontWhite` | 12 | White |
| `GameFontDarkGraySmall` | 10 | Dark gray |
| `GameTooltipHeader` | 14 | Bold (tooltips) |
| `GameTooltipText` | 12 | Normal (tooltips) |
| `ChatFontNormal` | 14 | Chat text |
| `SystemFont_Outline` | 13 | Outline |
| `NumberFontNormal` | 12 | Monospace numbers |

---

## Debugging & Profiling

### In-Game Debugging Commands

```
/dump expression             -- Evaluate and print Lua expression
/tinspect expression         -- Interactive table inspector
/fstack                      -- Show frames under cursor (toggle)
/etrace                      -- Event trace panel (toggle)
/api                         -- API documentation browser
/api function_name           -- Search API docs
/console scriptErrors 1      -- Show Lua error popups
/console scriptErrors 0      -- Hide Lua error popups
/console taintLog 1          -- Enable taint logging
/console taintLog 0          -- Disable taint logging
/reload                      -- Reload UI
```

### Debugging Addons

```lua
-- BugSack/BugGrabber (recommended addon for error capture)
-- Install from CurseForge: BugSack + BugGrabber

-- Manual error checking
/console scriptErrors 1

-- DevTool addon for inspecting tables/frames
-- Install from CurseForge: DevTool
```

### Lua Debugging Techniques

```lua
-- Stack trace
print(debugstack())           -- Full stack trace
print(debugstack(2, 5, 2))   -- (start, top, bottom)

-- Protected call with trace
local ok, err = xpcall(function()
    -- risky code
end, function(msg)
    return msg .. "\n" .. debugstack(2)
end)

-- Print table contents
DevTools_Dump(myTable)         -- Pretty-print (needs Blizzard_DebugTools)
/dump MyGlobalTable            -- From chat

-- Timing
local start = debugprofilestop()   -- Microseconds
DoWork()
local elapsed = debugprofilestop() - start
print(string.format("Took %.3f ms", elapsed / 1000))
```

### Performance Profiling

```lua
-- Enable addon profiling
/console scriptProfile 1
/reload

-- Query addon performance
UpdateAddOnCPUUsage()
local total = GetAddOnCPUUsage("MyAddon")  -- Milliseconds since reset
print("CPU:", total, "ms")

UpdateAddOnMemoryUsage()
local mem = GetAddOnMemoryUsage("MyAddon")  -- KB
print("Memory:", mem, "KB")

-- C_AddOnProfiler (modern, 11.0+)
C_AddOnProfiler.GetAddOnMetric("MyAddon", metric) : result
C_AddOnProfiler.GetOverallMetric(metric) : result
C_AddOnProfiler.IsEnabled() : enabled
```

### Common Debugging Patterns

```lua
-- Conditional debug printing
local DEBUG = false
local function DebugPrint(...)
    if DEBUG then print("|cFF00FFFF[MyAddon Debug]|r", ...) end
end

-- Event logging
local function LogEvent(event, ...)
    if db.debugMode then
        local args = {}
        for i = 1, select("#", ...) do
            args[i] = tostring(select(i, ...))
        end
        print("|cFFFFFF00[Event]|r", event, table.concat(args, ", "))
    end
end

-- Frame inspector (quick)
/run local f = GetMouseFocus(); if f then print(f:GetName(), f:GetObjectType(), f:GetSize()) end

-- Find all frames with a name pattern
/run for k, v in pairs(_G) do if type(k)=="string" and k:find("ChattyLittle") then print(k, type(v)) end end
```

### Taint Debugging

```lua
-- Check if a variable is tainted
local secure, who = issecurevariable("TargetFrame")
print("Secure:", secure, "Tainted by:", who or "nobody")

-- Check if currently secure
print("Execution is secure:", issecure())

-- Enable taint log, reproduce issue, check Logs/taint.log
/console taintLog 1
-- ... reproduce
/console taintLog 0
-- Search taint.log for "blocked"
```

# Advanced: Secure Frames, State Drivers & Intrinsics

> Deep reference for combat-safe UI, state-driven attributes, and custom frame types.
> Sources: https://warcraft.wiki.gg/wiki/SecureHandlers, SecureStateDriver, Intrinsic_frame

## SecureHandlers

SecureHandlers run code snippets inside the RestrictedEnvironment — a limited Lua subset
that can execute during combat to alter protected frame attributes.

### Templates

| Template | Trigger | Attribute |
|----------|---------|-----------|
| `SecureHandlerBaseTemplate` | (common methods) | — |
| `SecureHandlerStateTemplate` | state-xxx attribute change | `_onstate-xxx` |
| `SecureHandlerAttributeTemplate` | Any attribute change | `_onattributechanged` |
| `SecureHandlerClickTemplate` | Clicks | `_onclick` |
| `SecureHandlerDoubleClickTemplate` | Double clicks | `_ondoubleclick` |
| `SecureHandlerDragTemplate` | Dragging | `_ondragstart`, `_onreceivedrag` |
| `SecureHandlerMouseUpDownTemplate` | Mouse up/down | `_onmouseup`, `_onmousedown` |
| `SecureHandlerMouseWheelTemplate` | Mouse wheel | `_onmousewheel` |
| `SecureHandlerEnterLeaveTemplate` | Mouse enter/leave | `_onenter`, `_onleave` |
| `SecureHandlerShowHideTemplate` | Show/hide | `_onshow`, `_onhide` |

### Handler Methods

```lua
handler:Execute(body)                          -- Run snippet in restricted env
handler:WrapScript(frame, script, pre [, post]) -- Wrap widget script
handler:UnwrapScript(frame, script)             -- Remove outermost wrap
handler:SetFrameRef(id, refFrame)              -- Create frame reference
```

### Example

```lua
local header = CreateFrame("Frame", "MyHeader", UIParent, "SecureHandlerStateTemplate")
header:SetFrameRef("myButton", myButton)
header:SetAttribute("_onstate-combat", [[
    local btn = self:GetFrameRef("myButton")
    if newstate == "combat" then
        btn:Hide()
    else
        btn:Show()
    end
]])
RegisterStateDriver(header, "combat", "[combat] combat; nocombat")
```

---

## SecureStateDriver

Executes code snippets on game state changes using macro conditionals.

### AttributeDriver (RegisterStateDriver)

```lua
RegisterAttributeDriver(frame, attribute, conditional)
UnregisterAttributeDriver(frame, attribute)

-- Legacy aliases (prepends "state-" to attribute)
RegisterStateDriver(frame, state, conditional)
UnregisterStateDriver(frame, state)
```

**Special behavior:**
- `"state-visibility"` → calls `frame:Show()` on "show", `frame:Hide()` on "hide"
- Other attributes → calls `frame:SetAttribute(attribute, result)`

### UnitWatch

```lua
RegisterUnitWatch(frame, asState)    -- Toggle visibility/attribute based on unit existence
UnregisterUnitWatch(frame)

-- frame must inherit SecureUnitButtonTemplate and have:
frame:SetAttribute("unit", "party1")
```

### State Evaluation

Conditionals are re-evaluated:
- Every ~0.2 seconds (throttled)
- Immediately on: MODIFIER_STATE_CHANGED, PLAYER_REGEN_DISABLED/ENABLED, 
  PLAYER_TARGET_CHANGED, GROUP_ROSTER_UPDATE, UPDATE_STEALTH, etc.

### Examples

```lua
-- Show/hide frame based on combat state
RegisterAttributeDriver(frame, "state-visibility", "[combat] hide; show")

-- Custom state based on pet
RegisterStateDriver(frame, "petstate", 
    "[@pet,noexists] nopet; [@pet,help] mypet; [@pet,harm] mcpet")
frame:SetAttribute("_onstate-petstate", [[
    if newstate == "nopet" then
        -- no pet
    elseif newstate == "mypet" then
        -- has pet
    end
]])

-- Show unit frame only when unit exists
local uf = CreateFrame("Button", "MyParty1", UIParent, "SecureUnitButtonTemplate")
uf:SetAttribute("unit", "party1")
RegisterUnitWatch(uf)
```

---

## Macro Conditionals (Complete Reference)

Used in macros, RegisterStateDriver, and SecureCmdOptionParse.

### Target Conditionals

| Conditional | Description |
|-------------|-------------|
| `@unitId` | Temporary target override (@player, @focus, @mouseover, etc.) |
| `@cursor` | Cast at cursor position |
| `@none` | No target / require targeting cursor |

### Target-Evaluated (default: @target)

| Conditional | Description |
|-------------|-------------|
| `[exists]` | Target exists |
| `[help]` | Can assist target |
| `[harm]` | Can attack target |
| `[dead]` | Target is dead |
| `[party]` / `[raid]` | Target in party/raid |
| `[unithasvehicleui]` | Target in vehicle |

### Player State

| Conditional | Description |
|-------------|-------------|
| `[combat]` | In combat |
| `[stealth]` | Stealthed |
| `[mounted]` | Mounted |
| `[swimming]` | Swimming |
| `[flying]` | Flying |
| `[flyable]` | In flyable area |
| `[advflyable]` | In skyriding area |
| `[indoors]` / `[outdoors]` | Indoor/outdoor |
| `[resting]` | In rested zone |
| `[group]` / `[group:party]` / `[group:raid]` | In group type |
| `[spec:1]` / `[spec:2]` | Active specialization |
| `[form:n]` / `[stance:n]` | Shapeshift form |
| `[pet]` / `[pet:name]` / `[pet:family]` | Has pet |
| `[known:spell]` | Spell is known |
| `[equipped:type]` | Item type equipped |
| `[channeling]` / `[channeling:spell]` | Channeling |
| `[pvpcombat]` | PvP talents usable |
| `[canexitvehicle]` | Can exit vehicle |
| `[petbattle]` | In pet battle |

### UI State

| Conditional | Description |
|-------------|-------------|
| `[mod:shift]` / `[mod:ctrl]` / `[mod:alt]` | Modifier key |
| `[button:1]` / `[btn:2]` | Mouse button |
| `[actionbar:n]` / `[bar:n]` | Action bar page |
| `[bonusbar]` / `[bonusbar:n]` | Bonus bar visible |
| `[extrabar]` | Extra action bar visible |
| `[overridebar]` | Override bar active |
| `[vehicleui]` | Vehicle UI active |
| `[cursor]` | Dragging an action |

### Housing (New in Midnight)

| Conditional | Description |
|-------------|-------------|
| `[house]` | In house (inside or plot) |
| `[house:inside]` | Inside a house |
| `[house:plot]` | On house plot |
| `[house:editor]` | House editor active |
| `[house:neighborhood]` | On neighborhood map |

### Syntax

```
/command [cond1,cond2] action1; [cond3] action2; fallback
```

- Comma = AND (all must be true)
- Semicolon = ELSE (try next clause)
- `no` prefix = negation (`[nocombat]`, `[nodead]`)
- Slash in values = OR (`[mod:shift/ctrl]`, `[spec:1/2]`)

---

## Intrinsic Frames

Custom frame types that extend existing widget types with bound pre/post script handlers.

### Defining

```xml
<Frame name="MyIntrinsic" intrinsic="true">
    <Scripts>
        <OnShow function="MyIntrinsic_PreShow" intrinsicOrder="precall"/>
        <OnShow function="MyIntrinsic_PostShow" intrinsicOrder="postcall"/>
    </Scripts>
</Frame>
```

### Using

```lua
-- In Lua (like any built-in widget type)
local f = CreateFrame("MyIntrinsic", nil, UIParent)

-- In XML (as a tag)
<MyIntrinsic parentKey="child">
    <Scripts>
        <OnShow>print("normal OnShow")</OnShow>
    </Scripts>
</MyIntrinsic>
```

### Execution Order

1. `intrinsicOrder="precall"` — Before normal handler
2. Normal handler (SetScript / XML inline)
3. `intrinsicOrder="postcall"` — After normal handler

### Key Rules

- Intrinsic scripts **cannot be replaced** once bound
- Can be hooked with `HookScript` and inspected with `GetScript`
- `GetObjectType()` returns the base type ("Frame"), not the intrinsic name
- Cannot create intrinsics based on other intrinsics
- Default `intrinsicOrder` is "precall" if not specified

### Inspecting

```lua
f:GetScript("OnShow", LE_SCRIPT_BINDING_TYPE_INTRINSIC_PRECALL)
f:GetScript("OnShow", LE_SCRIPT_BINDING_TYPE_EXTRINSIC)
f:GetScript("OnShow", LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL)
```

### FrameXML Intrinsics

| Type | Intrinsic |
|------|-----------|
| Frame | EventFrame, ScrollingMessageFrame |
| Button | ContainedAlertFrame, DropDownToggleButton, EventButton, ItemButton |
| EditBox | EventEditBox |

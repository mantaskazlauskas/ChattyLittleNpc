# Secure Execution & Tainting (Patch 12.0.1)

> Addons cannot perform protected actions (targeting, casting) from tainted code during combat.
> Full reference: https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting

## Core Concept

When WoW begins executing Lua code, execution starts **secure**. It becomes **tainted** when it encounters code or data from addon (third-party) sources. Tainted execution cannot call protected functions, especially during combat.

```
Secure code (Blizzard) → can do anything
Tainted code (Addons)  → restricted during combat
```

## What Gets Tainted

- All addon code and saved variables start tainted
- Local/global variables created by addon code are tainted
- Table keys and values set by addon code are tainted
- When secure code reads a tainted value, the execution path becomes tainted
- Taint spreads to anything the tainted execution modifies

### Honey Analogy

Think of taint as sticky honey:
- Addon code always has sticky hands
- Everything you touch becomes sticky
- Blizzard code has clean hands, but touching something sticky makes them sticky too
- Errors occur when Blizzard tries to call a protected function with sticky hands

## Protected Functions

Protected functions can only be called from secure (untainted) execution paths. During combat lockdown, addons cannot:

- Cast spells
- Change targets
- Show/hide/move protected frames
- Change attributes on secure frames
- Modify combat-affecting state

### Checking Combat Lockdown

```lua
if InCombatLockdown() then
    -- Cannot modify secure frames or call protected functions
    print("Please wait until combat ends")
    return
end
```

## Avoiding Taint

### hooksecurefunc — Secure Post-Hooking

```lua
-- Post-hook a global function (runs AFTER the original)
hooksecurefunc("TargetUnit", function(unitID)
    print("Targeted:", unitID)
end)

-- Post-hook a table method
hooksecurefunc(GameTooltip, "SetUnit", function(self, unitID)
    print("Tooltip set to:", unitID)
end)
```

**Key**: The hook runs after the original. It receives the same arguments but doesn't taint the original's execution.

### HookScript — Secure Script Post-Hooking

```lua
-- Runs AFTER any existing OnShow handler
frame:HookScript("OnShow", function(self)
    print("Frame shown!")
end)
```

**Do NOT use SetScript on Blizzard frames** — it replaces the secure handler and causes taint.

### securecall

```lua
securecall(func, ...)  -- Call function without spreading taint
```

## Protected Frames

Protected frames are locked down during combat:
- Cannot be shown/hidden/moved by addon code
- Attributes cannot be changed
- Configured out of combat using `frame:SetAttribute()`

### Secure Templates

| Template | Description |
|----------|-------------|
| `SecureActionButtonTemplate` | Button that can cast spells, use items, target |
| `SecureUnitButtonTemplate` | Button that responds to unit clicks |
| `SecureGroupHeaderTemplate` | Auto-manages party/raid unit frames |
| `SecureGroupPetHeaderTemplate` | Auto-manages pet frames |
| `SecureHandlerStateTemplate` | Responds to state changes |
| `SecureHandlerAttributeTemplate` | Responds to attribute changes |
| `SecureHandlerClickTemplate` | Custom click behavior |
| `SecureHandlerShowHideTemplate` | Show/hide reactions |

### Using Secure Action Buttons

```lua
local btn = CreateFrame("Button", "MySecureButton", UIParent, "SecureActionButtonTemplate")
btn:SetAttribute("type", "spell")
btn:SetAttribute("spell", "Flash Heal")
-- This button will cast Flash Heal when clicked, even in combat
-- BUT: You can only SetAttribute OUTSIDE of combat!
```

### Common Attribute Types

```lua
frame:SetAttribute("type", "spell")     -- Cast a spell
frame:SetAttribute("type", "item")      -- Use an item
frame:SetAttribute("type", "macro")     -- Execute a macro
frame:SetAttribute("type", "target")    -- Target a unit
frame:SetAttribute("type", "focus")     -- Focus a unit
frame:SetAttribute("type", "action")    -- Perform an action slot
```

## SecureHandlers (Advanced)

Restricted Lua environment that runs during combat:

```lua
local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
header:SetFrameRef("myButton", myButton)
header:SetAttribute("_onstate-combat", [[
    -- This runs in restricted environment during combat
    local button = self:GetFrameRef("myButton")
    if newstate == "combat" then
        button:Hide()
    else
        button:Show()
    end
]])
RegisterStateDriver(header, "combat", "[combat] combat; nocombat")
```

### Restricted Environment Functions

Available in secure handler bodies:
```lua
self:GetFrameRef(key) : frame
self:GetAttribute(name) : value
self:SetAttribute(name, value)
self:Show() / self:Hide()
self:SetAlpha(alpha)
self:ClearAllPoints()
self:SetPoint(...)
self:SetWidth(w) / self:SetHeight(h) / self:SetSize(w, h)
-- And other limited functions
```

## Taint Debugging

```
/console taintLog 1   -- Enable taint logging
-- Reproduce the issue
/console taintLog 0   -- Disable logging
-- Check Logs/taint.log for "blocked" entries
```

The error message "Interface action failed because of an AddOn" means taint blocked a protected action.

## Security Functions

```lua
-- Taint introspection
issecure() : isSecure                         -- Is current execution secure?
issecurevariable(table, key) : isSecure, who  -- Is variable secure?
hooksecurefunc([table,] name, func)          -- Secure post-hook
securecall(func, ...)                        -- Call without spreading taint
forceinsecure()                              -- Force tainted execution

-- Secret value introspection (Patch 12.0+)
issecretvalue(val) : bool           -- true if val is a secret value
issecrettable(tbl) : bool           -- true if table is flagged as secret
canaccessvalue(val) : bool          -- true if current context permits operations on val
canaccesstable(tbl) : bool          -- true if table indexing won't error
hasanysecretvalues(tbl) : bool      -- true if table contains any secret values
scrubsecretvalues(tbl) : tbl        -- replaces all secret values in tbl with nil (in-place)
```

## Secret Values (Patch 12.0+)

Secret values restrict what addons can do with certain Lua values when executing on tainted code paths. They primarily affect combat-state data: health, power, auras, cooldowns, cast info, and unit identity. The core rule: addons may **present/display** combat information but may NOT **compute/branch** on it.

> Secret values, private auras, and combat-log removal are **separate mechanisms**:
> - **Secret values** — restricted operations on API return values
> - **Private auras** — auras only visible to the affected player
> - **Combat log removal** — `COMBAT_LOG_EVENT` no longer fires for addons

### APIs That Return Secret Values

Conditionally secret (controlled by predicates like `SecretWhenUnitAuraRestricted`, `SecretWhenSpellCooldownRestricted`, etc.):

| API | What's Secret |
|-----|---------------|
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | Full aura data table |
| `C_UnitAuras.GetAuraDataByIndex` | Full aura data table |
| `C_UnitAuras.GetAuraDataBySlot` | Full aura data table |
| `C_UnitAuras.GetUnitAuras` | Aura tables |
| `C_Spell.GetSpellCooldown` | Cooldown values |
| `C_Spell.GetSpellCharges` | Charge info |
| `UnitCastingInfo` / `UnitChannelInfo` | Cast name, duration, etc. |
| `UnitHealth` / `UnitPower` | Current resource values |
| `UnitName` | Some identity APIs |
| `CHAT_MSG_MONSTER_*` event args | text, npcName, guid can be secret |

**NOT secret** (explicitly loosened):
- Player max health/power
- All class secondary resources (combo points, holy power, etc.)
- Player's own spell-cast information
- Cooldown/aura access outside combat or outside active M+/PvP

### Operations — Allowed vs. Blocked

**BLOCKED** (immediate Lua error from tainted code):
```lua
-- Comparison
if secretVal == 100 then end        -- ERROR
if secretVal ~= nil then end        -- ERROR
if secretVal > 0 then end           -- ERROR

-- Boolean test
if secretVal then end               -- ERROR

-- Arithmetic
local x = secretVal + 1             -- ERROR

-- Length
local n = #secretVal                -- ERROR

-- String methods
secretVal:sub(1, 5)                 -- ERROR
secretVal:find("pattern")           -- ERROR
secretVal:len()                     -- ERROR
secretVal:lower()                   -- ERROR
tostring(secretVal)                 -- ERROR

-- Table key use (irrevocably marks table as secret!)
tbl[secretVal] = true               -- ERROR

-- Indexed access on secret tables
local v = secretTbl[1]              -- ERROR
local v = secretTbl.key             -- ERROR

-- Calling secret values
secretVal()                         -- ERROR
```

**ALLOWED** from tainted code:
```lua
-- Type introspection
type(secretVal)                     -- returns "string", "number", etc.
issecretvalue(secretVal)            -- returns true
issecrettable(secretTbl)            -- returns true
canaccessvalue(val)                 -- returns true if operations permitted
canaccesstable(tbl)                 -- returns true if indexing won't error
hasanysecretvalues(tbl)             -- checks table contents
scrubsecretvalues(tbl)              -- replaces secrets with nil

-- Storage and passing
local x = secretVal                 -- store in variable OK
tbl.someKey = secretVal             -- store as table value OK (NOT as key)
someFunc(secretVal)                 -- pass to functions OK

-- String concatenation (secret strings/numbers only)
local s = "HP: " .. secretVal       -- OK for display
string.format("HP: %s", secretVal)  -- OK
string.join(", ", secretA, secretB) -- OK

-- Secret-accepting widget APIs (see below)
myFontString:SetText(secretStr)     -- OK
myStatusBar:SetValue(secretNum)     -- OK
```

### Secret-Accepting Widget APIs

These Blizzard APIs accept secret values from tainted code:

```lua
StatusBar:SetValue(secretNum)
StatusBar:SetMinMaxValues(secretMin, secretMax)
StatusBar:SetTimerDuration(durationObj)
FontString:SetText(secretStr)       -- applies "Text" secret aspect
-- Blizzard TTS APIs accept secret-containing text
```

### Display-Safe Alternatives

```lua
-- Percentage health/power (display-oriented, not secret)
UnitHealthPercent(unit)
UnitPowerPercent(unit)

-- Curve-based mapping (secret value → display output)
C_CurveUtil.CreateCurve()
C_CurveUtil.CreateColorCurve()

-- Duration objects for cooldown bars
local dur = C_Spell.GetSpellCooldownDuration()
myStatusBar:SetTimerDuration(dur)

-- Aura display helpers
C_UnitAuras.GetAuraDuration()                   -- returns DurationObject
C_UnitAuras.GetAuraApplicationDisplayCount()    -- safe display count
C_Secrets.ShouldUnitAuraIndexBeSecret()         -- predict if query would be secret
```

### Secret Aspects

When secret values are passed to widget APIs, they apply "aspects" that propagate restrictions:

```lua
-- Setting secret text marks the fontstring
myFontString:SetText(secretStr)        -- applies "Text" aspect
myFontString:GetText()                 -- now returns secret!

-- Aspect introspection
frame:HasSecretAspect("Text")          -- FrameScriptObject method
frame:HasSecretValues()                -- test if object has any secret values
frame:SetToDefaults()                  -- only way to clear secret aspects

-- Secret anchoring: objects with secret values make position APIs return secrets
region:IsAnchoringSecret()             -- test for secret anchoring
```

### Desecret Pattern for Chat Events

For `CHAT_MSG_MONSTER_*` and similar events where args may be secret strings:

```lua
local function desecret(val)
    local t = type(val)  -- type() is safe on secrets
    if t ~= "string" and t ~= "number" then return val end
    -- Concatenation is allowed on secret strings/numbers
    local ok, plain = pcall(function() return "" .. val end)
    if ok and plain then return plain end
    -- Fallback: string.format is also allowed
    ok, plain = pcall(string.format, "%s", val)
    if ok and plain then return plain end
    return nil  -- truly inaccessible
end

-- Usage: desecret event args before any comparison/logic
text = desecret(text)
npcName = desecret(npcName)
```

### SavedVariables Behavior

Secret values do **not** serialize into SavedVariables — they are scrubbed to nil on logout/reload. Use `scrubsecretvalues(tbl)` before persisting if a table might contain secrets.

### Chronology of Loosening

1. **Oct 2025** — Cooldown/aura access loosened outside combat/M+/PvP
2. **Oct 2025** — Secret text allowed into TTS APIs; gossip restrictions removed
3. **Nov 2025** — Player spell-cast info loosened; player max health/power loosened; class secondary resources fully unsecreted
4. **Feb 2026** — Temporary healer HoT/buff carve-outs until built-in filtering arrives

## Best Practices

1. **Never SetScript on Blizzard frames** — use HookScript instead
2. **Never modify Blizzard globals** — creates taint
3. **Check InCombatLockdown()** before modifying secure frames
4. **Use hooksecurefunc** to observe Blizzard function calls
5. **Configure secure frames out of combat** — use PLAYER_REGEN_ENABLED event
6. **Don't read/write Blizzard saved variables** — causes taint
7. **Use your own namespace** — don't pollute _G with common names
8. **Desecret chat event args** before comparing or branching — use the `desecret()` pattern
9. **Use `scrubsecretvalues()`** before persisting tables that may contain secrets
10. **Never use secret values as table keys** — it irrevocably marks the table as secret
11. **Prefer display-safe APIs** — `UnitHealthPercent`, `DurationObject`, `C_CurveUtil` over raw values
12. **Guard with `issecretvalue()`/`canaccessvalue()`** before performing operations on values that might be secret

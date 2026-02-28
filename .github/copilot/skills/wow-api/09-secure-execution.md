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
issecure() : isSecure                         -- Is current execution secure?
issecurevariable(table, key) : isSecure, who  -- Is variable secure?
hooksecurefunc([table,] name, func)          -- Secure post-hook
securecall(func, ...)                        -- Call without spreading taint
forceinsecure()                              -- Force tainted execution
```

## Midnight Changes

As of Midnight (12.0.x), addons can no longer access most combat data while inside instances. This significantly impacts boss mods and combat analysis addons.

## Best Practices

1. **Never SetScript on Blizzard frames** — use HookScript instead
2. **Never modify Blizzard globals** — creates taint
3. **Check InCombatLockdown()** before modifying secure frames
4. **Use hooksecurefunc** to observe Blizzard function calls
5. **Configure secure frames out of combat** — use PLAYER_REGEN_ENABLED event
6. **Don't read/write Blizzard saved variables** — causes taint
7. **Use your own namespace** — don't pollute _G with common names

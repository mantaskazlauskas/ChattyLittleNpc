# Saved Variables (Patch 12.0.1)

> Persist addon data between game sessions using TOC directives.
> Full reference: https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions

## Quick Setup

### 1. Declare in TOC

```toc
## Interface: 120001
## Title: MyAddon
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
MyAddon.lua
```

### 2. Initialize on ADDON_LOADED

```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "MyAddon" then
        -- SavedVariables are now available
        if MyAddonDB == nil then
            -- First time: set defaults
            MyAddonDB = {
                enabled = true,
                volume = 0.8,
                history = {},
            }
        end

        if MyAddonCharDB == nil then
            MyAddonCharDB = {
                position = { x = 0, y = 0 },
            }
        end

        -- Merge new defaults with existing (forward compatibility)
        if MyAddonDB.volume == nil then
            MyAddonDB.volume = 0.8
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Last chance to update data before save
        MyAddonCharDB.lastSeen = time()
    end
end)
```

## SavedVariables vs SavedVariablesPerCharacter

| Directive | Scope | Storage Path |
|-----------|-------|-------------|
| `SavedVariables` | Per-account | `WTF/Account/NAME/SavedVariables/AddonName.lua` |
| `SavedVariablesPerCharacter` | Per-character | `WTF/Account/NAME/Realm/Char/SavedVariables/AddonName.lua` |

## Loading Timeline

```
1. WoW FrameXML code loads
2. Addon Lua/XML code loads and executes
   └── Global defaults set in Lua code are in memory
3. SavedVariables files load (OVERWRITES globals from step 2!)
   └── ADDON_LOADED fires for each addon
4. PLAYER_LOGIN fires (all non-LoD addons loaded)
```

**Critical**: SavedVariables overwrite any defaults you set at file load time. Always check in ADDON_LOADED.

## What Can Be Saved

| Type | Saveable | Notes |
|------|----------|-------|
| `string` | ✅ | |
| `number` | ✅ | |
| `boolean` | ✅ | |
| `table` | ✅ | Nested tables work; circular refs may not survive |
| `nil` | ✅ | Key is omitted from saved file |
| `function` | ❌ | Not serializable |
| `userdata` | ❌ | Not serializable |
| `coroutine` | ❌ | Not serializable |

## When Data Saves

Data writes to disk automatically on:
- Player logout
- Client disconnect
- Game quit
- `/reload` UI reload

## Common Patterns

### Default Merging

```lua
local DEFAULTS = {
    enabled = true,
    volume = 0.8,
    language = "en",
    history = {},
}

-- Shallow merge: fill in missing keys
local function MergeDefaults(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            if type(v) == "table" then
                saved[k] = CopyTable(v)
            else
                saved[k] = v
            end
        end
    end
end

-- Usage in ADDON_LOADED:
if MyAddonDB == nil then
    MyAddonDB = CopyTable(DEFAULTS)
else
    MergeDefaults(MyAddonDB, DEFAULTS)
end
```

### Profile System

```lua
-- Simple per-character profiles stored in account-wide SV
local function GetProfileKey()
    return UnitName("player") .. "-" .. GetNormalizedRealmName()
end

-- In ADDON_LOADED:
MyAddonDB = MyAddonDB or { profiles = {} }
local key = GetProfileKey()
if not MyAddonDB.profiles[key] then
    MyAddonDB.profiles[key] = CopyTable(DEFAULTS)
end
local db = MyAddonDB.profiles[key]
```

### LoadSavedVariablesFirst

```toc
## LoadSavedVariablesFirst: 1
```

When set to `1`, SavedVariables load BEFORE addon script files. This reverses the normal order but is rarely used.

## Common Pitfalls

1. **Don't set defaults at file scope** — they'll be overwritten by SavedVariables loading
2. **Variables must be global** — `local` variables can't be saved
3. **Tables referencing the same object** — after reload, they become separate copies
4. **Functions in tables are stripped** — any function values in a saved table are lost
5. **Large SavedVariables** — keep data size reasonable; `SAVED_VARIABLES_TOO_LARGE` event fires if exceeded
6. **Version migrations** — always handle the case where saved data is from an older addon version

## Deleting Saved Data

Delete the files in:
- `WTF/Account/ACCOUNTNAME/SavedVariables/AddonName.lua` (account-wide)
- `WTF/Account/ACCOUNTNAME/RealmName/CharName/SavedVariables/AddonName.lua` (per-char)

Or `/run MyAddonDB = nil; ReloadUI()` to reset in-game.

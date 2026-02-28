# CVars, Combat Log & Macro Commands

> Console variables, combat log event parsing, and slash commands.

## Console Variables (CVars)

> Full list: https://warcraft.wiki.gg/wiki/Console_variables

### Reading/Writing CVars

```lua
-- Read a CVar
local value = GetCVar("Sound_MasterVolume")       -- Returns string
local value = GetCVarBool("Sound_EnableAllSound")  -- Returns boolean

-- Write a CVar
SetCVar("Sound_MasterVolume", "0.5")

-- Default value
local default = GetCVarDefault("Sound_MasterVolume")

-- From chat
/console Sound_MasterVolume 0.5
/dump GetCVar("Sound_MasterVolume")
```

### CVar Scope

| Scope | Description |
|-------|-------------|
| **Game** | Global game settings |
| **Account** | Per-Battle.net account |
| **Character** | Per-character |

### Commonly Used CVars

#### Sound
| CVar | Default | Description |
|------|---------|-------------|
| `Sound_EnableAllSound` | 1 | Master sound toggle |
| `Sound_MasterVolume` | 1.0 | Master volume (0.0–1.0) |
| `Sound_EnableSFX` | 1 | Effects toggle |
| `Sound_SFXVolume` | 1.0 | Effects volume |
| `Sound_EnableMusic` | 1 | Music toggle |
| `Sound_MusicVolume` | 0.4 | Music volume |
| `Sound_EnableAmbience` | 1 | Ambience toggle |
| `Sound_AmbienceVolume` | 0.6 | Ambience volume |
| `Sound_EnableDialog` | 1 | Dialog toggle |
| `Sound_DialogVolume` | 1.0 | Dialog volume |

#### Nameplates
| CVar | Default | Description |
|------|---------|-------------|
| `nameplateShowAll` | 0 | Show all nameplates |
| `nameplateShowFriends` | 0 | Show friendly nameplates |
| `nameplateShowEnemies` | 1 | Show enemy nameplates |
| `nameplateMotion` | 1 | Stacking nameplates (0=overlap, 1=stack) |

#### Combat / UI
| CVar | Default | Description |
|------|---------|-------------|
| `advancedCombatLogging` | 0 | Advanced combat log data |
| `ActionButtonUseKeyDown` | 1 | Activate on key down |
| `autoLootDefault` | 0 | Auto-loot |
| `cameraDistanceMaxZoomFactor` | 1.9 | Max camera zoom |
| `UnitNameNPC` | 0 | Show NPC names |
| `UnitNameFriendlyPlayerName` | 1 | Show friendly player names |

#### Addon-Relevant
| CVar | Default | Description |
|------|---------|-------------|
| `taintLog` | 0 | Enable taint logging (to Logs/taint.log) |
| `scriptErrors` | 0 | Show Lua error popup |
| `scriptProfile` | 0 | Enable addon CPU/memory profiling |

### CVar Events

```lua
-- CVAR_UPDATE fires when a CVar changes
frame:RegisterEvent("CVAR_UPDATE")
-- payload: eventName (string) — the CVar that changed
```

---

## Combat Log

> Full reference: https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT

### Registering

```lua
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")  -- Use UNFILTERED for addons
frame:SetScript("OnEvent", function(self, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local info = {CombatLogGetCurrentEventInfo()}
        local timestamp, subevent, hideCaster,
              sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags = unpack(info)
        -- Process subevent...
    end
end)
```

### Base Parameters (first 11)

| # | Name | Type | Description |
|---|------|------|-------------|
| 1 | timestamp | number | Unix time with ms precision |
| 2 | subevent | string | e.g. "SPELL_DAMAGE", "SWING_DAMAGE" |
| 3 | hideCaster | bool | Source unit is hidden |
| 4 | sourceGUID | string | Source unit GUID |
| 5 | sourceName | string | Source unit name |
| 6 | sourceFlags | number | Unit type/affiliation flags |
| 7 | sourceRaidFlags | number | Raid target marker |
| 8 | destGUID | string | Target unit GUID |
| 9 | destName | string | Target unit name |
| 10 | destFlags | number | Target type/affiliation flags |
| 11 | destRaidFlags | number | Target raid marker |

### Prefix Parameters (12–14)

| Prefix | Param 12 | Param 13 | Param 14 |
|--------|----------|----------|----------|
| SWING | — | — | — |
| RANGE / SPELL / SPELL_PERIODIC | spellId | spellName | spellSchool |
| ENVIRONMENTAL | envType | — | — |

### Suffix Parameters (15+)

| Suffix | Params |
|--------|--------|
| _DAMAGE | amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand |
| _HEAL | amount, overhealing, absorbed, critical |
| _MISSED | missType, isOffHand, amountMissed, critical |
| _ENERGIZE | amount, overEnergize, powerType |
| _AURA_APPLIED / _AURA_REMOVED | auraType, amount |
| _CAST_START / _CAST_SUCCESS | — |
| _CAST_FAILED | failedType |
| _INTERRUPT | extraSpellId, extraSpellName, extraSchool |
| _DISPEL | extraSpellId, extraSpellName, extraSchool, auraType |
| _SUMMON / _CREATE | — |
| _INSTAKILL | unconsciousOnDeath |

### Special Events

| Subevent | Description |
|----------|-------------|
| UNIT_DIED | Unit died |
| UNIT_DESTROYED | Unit destroyed (totems, etc.) |
| PARTY_KILL | Party killed a unit |
| DAMAGE_SHIELD | Thorns-type damage |
| DAMAGE_SPLIT | Split damage |
| ENCHANT_APPLIED / ENCHANT_REMOVED | Enchant changes |

### Spell Schools (Bitmask)

| Bit | Value | School | Color |
|-----|-------|--------|-------|
| 1 | 1 | Physical | `FFFF00` |
| 2 | 2 | Holy | `FFE680` |
| 3 | 4 | Fire | `FF8000` |
| 4 | 8 | Nature | `4DFF4D` |
| 5 | 16 | Frost | `80FFFF` |
| 6 | 32 | Shadow | `8080FF` |
| 7 | 64 | Arcane | `FF80FF` |

Combined: e.g. Frostfire = 20 (Frost + Fire), Chaos = 127 (all)

---

## Macro Commands (Slash Commands)

> Full reference: https://warcraft.wiki.gg/wiki/Macro_commands

### Most Used Commands

#### Casting
```
/cast SpellName                    -- Cast a spell
/cast [mod:shift] Spell1; Spell2   -- Conditional cast
/use ItemName                      -- Use an item
/use 13                            -- Use trinket slot 1 (14 = slot 2)
/castrandom Spell1, Spell2         -- Random spell
/castsequence Spell1, Spell2       -- Sequential (resets on timeout)
/stopcasting                       -- Stop current cast
/cancelaura BuffName               -- Cancel a buff
/cancelform                        -- Cancel shapeshift
```

#### Targeting
```
/target UnitName                   -- Target by name
/targetenemy                       -- Target nearest enemy
/targetenemyplayer                 -- Target nearest enemy player
/targetfriend                      -- Target nearest friend
/assist PlayerName                 -- Assist player
/focus                             -- Set focus target
/clearfocus                        -- Clear focus
/targetexact UnitName              -- Exact name match
```

#### Chat
```
/say text                          -- Local say
/yell text                         -- Zone yell
/whisper Player text               -- Whisper
/party text                        -- Party chat
/raid text                         -- Raid chat
/guild text                        -- Guild chat
/emote text                        -- Custom emote
```

#### UI / System
```
/run LuaCode()                     -- Execute Lua
/dump Expression                   -- Print Lua expression value
/console CVar Value                -- Set console variable
/reload                            -- Reload UI
/framestack                        -- Show frames under cursor
/etrace                            -- Event trace
/api                               -- API browser
```

### Macro Conditionals

```
/cast [mod:shift,@focus] Spell1; [nomod] Spell2

[target=unit]  or [@unit]     -- Target override
[mod:shift/ctrl/alt]          -- Modifier key
[nomod]                       -- No modifier
[combat] / [nocombat]         -- In/out of combat
[dead] / [nodead]             -- Target alive/dead
[exists] / [noexists]         -- Target exists
[help] / [harm]               -- Friendly/hostile
[stealth] / [nostealth]       -- In stealth
[swimming]                    -- Swimming
[flying]                      -- Flying
[mounted] / [nomounted]       -- Mounted
[group:party/raid]            -- In group
[spec:1/2]                    -- Current spec
[form:1/2/3]                  -- Shapeshift form
[channeling]                  -- Channeling
[pet]                         -- Has pet
[button:1/2/3/4/5]            -- Mouse button
[known:SpellName]             -- Spell is known
```

### Macro Targets

```
@player     -- Self
@target     -- Current target
@focus      -- Focus target
@pet        -- Pet
@party1-4   -- Party members
@arena1-5   -- Arena opponents
@mouseover  -- Mouseover unit
@cursor     -- Cast at cursor position
@none       -- No target (self-cast or ground)
```

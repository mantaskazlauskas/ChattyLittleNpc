# Enums & Constants Reference

> Common enumeration values used throughout the WoW API.
> Full enum list: https://github.com/Ketho/BlizzardInterfaceResources/blob/live/Resources/Enums.lua

## Enum.PowerType

| Value | Field | Class/Usage |
|-------|-------|-------------|
| 0 | Mana | Casters, most NPCs |
| 1 | Rage | Warriors, Bear Druids |
| 2 | Focus | Hunters, Hunter Pets |
| 3 | Energy | Rogues, Monks, Cat Druids |
| 4 | ComboPoints | Rogues, Cat Druids |
| 5 | Runes | Death Knights |
| 6 | RunicPower | Death Knights |
| 7 | SoulShards | Warlocks |
| 8 | LunarPower | Balance Druids (Astral Power) |
| 9 | HolyPower | Retribution Paladins |
| 10 | Alternate | Boss encounter mechanics |
| 11 | Maelstrom | Enhancement/Elemental Shamans |
| 12 | Chi | Windwalker Monks |
| 13 | Insanity | Shadow Priests |
| 16 | ArcaneCharges | Arcane Mages |
| 17 | Fury | Havoc Demon Hunters |
| 18 | Pain | Vengeance Demon Hunters |
| 19 | Essence | Evokers |
| 25 | AlternateMount | Dragonriding Vigor |

## Enum.ItemQuality

| Value | Name | Hex Color |
|-------|------|-----------|
| 0 | Poor | `9D9D9D` (gray) |
| 1 | Common | `FFFFFF` (white) |
| 2 | Uncommon | `1EFF00` (green) |
| 3 | Rare | `0070DD` (blue) |
| 4 | Epic | `A335EE` (purple) |
| 5 | Legendary | `FF8000` (orange) |
| 6 | Artifact | `E6CC80` (gold) |
| 7 | Heirloom | `00CCFF` (cyan) |
| 8 | WoWToken | `00CCFF` (cyan) |

## Class IDs & Colors

| ID | Class | Token | Hex Color |
|----|-------|-------|-----------|
| 1 | Warrior | `WARRIOR` | `C69B6D` |
| 2 | Paladin | `PALADIN` | `F48CBA` |
| 3 | Hunter | `HUNTER` | `AAD372` |
| 4 | Rogue | `ROGUE` | `FFF468` |
| 5 | Priest | `PRIEST` | `FFFFFF` |
| 6 | Death Knight | `DEATHKNIGHT` | `C41E3A` |
| 7 | Shaman | `SHAMAN` | `0070DD` |
| 8 | Mage | `MAGE` | `3FC7EB` |
| 9 | Warlock | `WARLOCK` | `8788EE` |
| 10 | Monk | `MONK` | `00FF98` |
| 11 | Druid | `DRUID` | `FF7C0A` |
| 12 | Demon Hunter | `DEMONHUNTER` | `A330C9` |
| 13 | Evoker | `EVOKER` | `33937F` |

```lua
-- Access class colors
local color = RAID_CLASS_COLORS["WARRIOR"]  -- ColorMixin with .r, .g, .b, .colorStr
local r, g, b = GetClassColor("WARRIOR")
```

## Inventory Slot IDs

| ID | Constant | Slot |
|----|----------|------|
| 1 | `INVSLOT_HEAD` | Head |
| 2 | `INVSLOT_NECK` | Neck |
| 3 | `INVSLOT_SHOULDER` | Shoulder |
| 4 | `INVSLOT_BODY` | Shirt |
| 5 | `INVSLOT_CHEST` | Chest |
| 6 | `INVSLOT_WAIST` | Waist |
| 7 | `INVSLOT_LEGS` | Legs |
| 8 | `INVSLOT_FEET` | Feet |
| 9 | `INVSLOT_WRIST` | Wrist |
| 10 | `INVSLOT_HAND` | Hands |
| 11 | `INVSLOT_FINGER1` | Ring 1 |
| 12 | `INVSLOT_FINGER2` | Ring 2 |
| 13 | `INVSLOT_TRINKET1` | Trinket 1 |
| 14 | `INVSLOT_TRINKET2` | Trinket 2 |
| 15 | `INVSLOT_BACK` | Back (cloak) |
| 16 | `INVSLOT_MAINHAND` | Main Hand |
| 17 | `INVSLOT_OFFHAND` | Off Hand |
| 18 | `INVSLOT_RANGED` | Ranged (Classic) |
| 19 | `INVSLOT_TABARD` | Tabard |

## Bag IDs

| ID | Bag |
|----|-----|
| 0 | Backpack (16 slots base) |
| 1–4 | Equipped bag slots |
| 5 | Reagent Bag |
| -1 | Bank |
| -3 | Reagent Bank |
| 6–12 | Bank bag slots |
| 13 | Account Bank Tab 1 |

## Difficulty IDs

| ID | Name |
|----|------|
| 1 | Normal (5-man) |
| 2 | Heroic (5-man) |
| 3 | 10 Player |
| 4 | 25 Player |
| 5 | 10 Player Heroic |
| 6 | 25 Player Heroic |
| 7 | LFR (legacy) |
| 8 | Mythic+ |
| 14 | Normal (raid) |
| 15 | Heroic (raid) |
| 16 | Mythic (raid) |
| 17 | LFR (modern) |
| 23 | Mythic (5-man) |
| 24 | Timewalking |

## Spell Schools (Bitmask)

| Bit | Value | School | Color |
|-----|-------|--------|-------|
| 0 | 1 | Physical | `FFFF00` |
| 1 | 2 | Holy | `FFE680` |
| 2 | 4 | Fire | `FF8000` |
| 3 | 8 | Nature | `4DFF4D` |
| 4 | 16 | Frost | `80FFFF` |
| 5 | 32 | Shadow | `8080FF` |
| 6 | 64 | Arcane | `FF80FF` |

Combined: Frostfire=20, Shadowfrost=48, Chaos=127 (all)

```lua
-- Check if school includes fire
local hasFire = bit.band(school, 4) > 0
```

## UnitFlag Bitmask (Combat Log)

| Bit | Value | Meaning |
|-----|-------|---------|
| 0 | 0x1 | Affiliation: Mine |
| 1 | 0x2 | Affiliation: Party |
| 2 | 0x4 | Affiliation: Raid |
| 3 | 0x8 | Affiliation: Outsider |
| 4 | 0x10 | Reaction: Friendly |
| 5 | 0x20 | Reaction: Neutral |
| 6 | 0x40 | Reaction: Hostile |
| 8 | 0x100 | Control: Player |
| 9 | 0x200 | Control: NPC |
| 10 | 0x400 | Type: Player |
| 11 | 0x800 | Type: NPC |
| 12 | 0x1000 | Type: Pet |
| 13 | 0x2000 | Type: Guardian |
| 14 | 0x4000 | Type: Object |
| 16 | 0x10000 | Target |
| 17 | 0x20000 | Focus |

```lua
-- Common flag combinations
local COMBATLOG_OBJECT_AFFILIATION_MINE = 0x1
local COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
local isMyAction = bit.band(sourceFlags, 0x1) > 0
local isPlayer = bit.band(sourceFlags, 0x400) > 0
```

## Raid Target Markers

| Bit | Value | Icon | Name |
|-----|-------|------|------|
| 0 | 0x1 | ⭐ | Star |
| 1 | 0x2 | 🟠 | Circle (Orange) |
| 2 | 0x4 | 💎 | Diamond |
| 3 | 0x8 | 🔺 | Triangle |
| 4 | 0x10 | 🌙 | Moon |
| 5 | 0x20 | 🟦 | Square (Blue) |
| 6 | 0x40 | ❌ | Cross |
| 7 | 0x80 | 💀 | Skull |

## Frame Strata Values

```lua
-- Back to front (lower = further back)
"WORLD"
"BACKGROUND"
"LOW"
"MEDIUM"       -- Default
"HIGH"
"DIALOG"
"FULLSCREEN"
"FULLSCREEN_DIALOG"
"TOOLTIP"      -- Always on top
```

## Draw Layer Values

```lua
-- Bottom to top within a frame
"BACKGROUND"
"BORDER"
"ARTWORK"      -- Default
"OVERLAY"
"HIGHLIGHT"    -- Mouse highlight layer
```

## Sound Channel Names

| Channel | Description |
|---------|-------------|
| `"Master"` | Master volume (bypasses individual toggles) |
| `"SFX"` | Sound effects |
| `"Music"` | Background music |
| `"Ambience"` | Ambient sounds |
| `"Dialog"` | NPC/quest dialog voice |
| `"Talking Head"` | Talking head voiceover |

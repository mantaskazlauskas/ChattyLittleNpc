# Escape Sequences, Hyperlinks & Text Formatting

> Pipe `|` escape sequences for colors, textures, and hyperlinks in WoW text.
> Full reference: https://warcraft.wiki.gg/wiki/UI_escape_sequences
> Hyperlinks: https://warcraft.wiki.gg/wiki/Hyperlinks

## Color Codes

```lua
-- Basic color: |cAARRGGBB text |r
"|cFFFF0000This is red|r"         -- Red text
"|cFF00FF00This is green|r"       -- Green text
"|cFF0070DDThis is rare blue|r"   -- Rare item blue

-- Nesting: |r pops innermost color
"|cFFFF0000red |cFF00FF00green|r back to red|r normal"

-- Named global colors (from GlobalColor.db2)
"|cnPURE_GREEN_COLOR:Green Text|r"
"|cnPURE_RED_COLOR:Red Text|r"

-- Item quality colors
"|cnIQ4:Epic Quality Text|r"   -- 0=Poor,1=Common,2=Uncommon,3=Rare,4=Epic,5=Legendary

-- Helper function
WrapTextInColorCode("Text", "FFFF0000")  -- Returns colored string
```

## Texture Markup

```lua
-- |Tpath:height[:width[:offsetX:offsetY[:texW:texH:left:right:top:bottom[:r:g:b]]]]|t

-- Simple icon (square, auto-sized to text height)
"|T133784:16|t Coins"                              -- By FileDataID
"|TInterface\\Icons\\INV_Misc_Coin_01:16|t Coins"  -- By path

-- Fixed size
"|TInterface\\Icons\\INV_Misc_Coin_01:16:16|t"     -- 16x16

-- Aspect ratio (0 height = text height, width = aspect)
"|TInterface\\Icons\\INV_Misc_Coin_01:0:1.5|t"     -- 1.5:1 aspect

-- With tex coords (cropping)
"|TInterface\\Icons\\INV_Misc_Coin_01:16:16:0:0:64:64:4:60:4:60|t"

-- With vertex color (RGB 0-255)
"|TInterface\\Icons\\INV_Misc_Coin_01:16:16:0:0:16:16:0:16:0:16:73:177:73|t"

-- Helper functions
CreateSimpleTextureMarkup("Interface/Icons/INV_Misc_Coin_01", 16, 16)
CreateTextureMarkup(file, fileW, fileH, width, height, left, right, top, bottom)
```

## Atlas Markup

```lua
-- |A:atlasName:height:width[:offsetX:offsetY[:r:g:b]]|a
"|A:groupfinder-icon-role-large-tank:19:19|a Tank"
"|A:4259:19:19|a Tank"  -- By atlas ID

-- Helper
CreateAtlasMarkup("groupfinder-icon-role-large-tank", 16, 16)
```

## Hyperlinks

Format: `|cffXXXXXX|Htype:payload|h[text]|h|r`

### Common Hyperlink Types

```lua
-- Item
"|cffffffff|Hitem:2592::::::::::::::::::|h[Wool Cloth]|h|r"

-- Spell
"|cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r"

-- Achievement
"|cffffff00|Hachievement:10671:Player-GUID:1:2:16:17:...|h[Level 110]|h|r"

-- Quest
"|cffffff00|Hquest:53370:-1:110:120:3|h[Hour of Reckoning]|h|r"

-- Player (left-click whispers, right-click context menu)
"|Hplayer:CharName-Realm|h[CharName]|h"

-- Talent build (opens talent tree viewer)
"|cffa330c9|Htalentbuild:577:70:importString|h[Talents: Havoc DH]|h|r"

-- Keystone
"|cffa335ee|Hkeystone:180653:381:15:10:8:12:121|h[Keystone: Spires (15)]|h|r"

-- Currency
"|cffffffff|Hcurrency:1744|h[Corrupted Memento]|h|r"

-- Unit (shows tooltip, right-click opens combat log context)
"|Hunit:Creature-0-2083-0-7-299-00005A0F91:Young Wolf|hYoung Wolf|h"

-- Addon (local-only, cannot be sent in chat)
"|cff71d5ff|Haddon:MyAddon:custom:data|h[Click Me]|h|r"
```

### Handling Addon Hyperlinks

```lua
-- Register click handler for addon hyperlinks
hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
    local linkType, addonName, data = strsplit(":", link)
    if linkType == "addon" and addonName == "MyAddon" then
        print("Clicked:", data)
    end
end)

-- Or via EventRegistry
EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button)
    -- same handling
end)
```

### Inspecting Hyperlinks

```lua
-- From chat: /dump "[Flash Heal]"
-- Returns: |cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r

-- Programmatically
local linkType, data = LinkUtil.ExtractLink(hyperlink)
```

## Other Escape Sequences

```lua
"|n"     -- Newline (if widget supports it)
"||"     -- Literal pipe character

-- In macros/chat, use \124 for pipe: \124cFFFF0000red\124r

-- Word wrap hint (avoid breaking within)
"|Wkeep together|w"
```

## Grammar Helpers (Localization)

```lua
-- Korean postpositions
"라면|1을;를;"    -- Selects 을/를 based on consonant/vowel

-- French prepositions
"|2 fraise"       -- "de fraise"
"|2 avion"        -- "d'avion"

-- Plural
"1 |4car:cars;"   -- "1 car"
"2 |4car:cars;"   -- "2 cars"

-- English a/an
"|5 banana"       -- "a banana"
"|5 apple"        -- "an apple"
"|5^ apple"       -- "An apple" (capitalized)
```

## Kstrings (Restricted Text)

Kstrings (`|Kq1|k`) are replacement tokens for protected data (Battle.net names, group finder listings) that render as the actual text on screen but cannot be read programmatically.

## Quality Colors Reference

| Quality | Hex | Name |
|---------|-----|------|
| 0 | `9D9D9D` | Poor (gray) |
| 1 | `FFFFFF` | Common (white) |
| 2 | `1EFF00` | Uncommon (green) |
| 3 | `0070DD` | Rare (blue) |
| 4 | `A335EE` | Epic (purple) |
| 5 | `FF8000` | Legendary (orange) |
| 6 | `E6CC80` | Artifact (gold) |
| 7 | `00CCFF` | Heirloom (cyan) |
| 8 | `00CCFF` | WoW Token (cyan) |

## Class Colors

| Class | Hex |
|-------|-----|
| Death Knight | `C41E3A` |
| Demon Hunter | `A330C9` |
| Druid | `FF7C0A` |
| Evoker | `33937F` |
| Hunter | `AAD372` |
| Mage | `3FC7EB` |
| Monk | `00FF98` |
| Paladin | `F48CBA` |
| Priest | `FFFFFF` |
| Rogue | `FFF468` |
| Shaman | `0070DD` |
| Warlock | `8788EE` |
| Warrior | `C69B6D` |

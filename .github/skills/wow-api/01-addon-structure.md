# Addon Structure & TOC Format

## TOC File

The `.toc` file is mandatory for every addon. The filename must match the folder name:
```
Interface/AddOns/MyAddon/MyAddon.toc
```

### Basic Structure

```toc
## Interface: 120001
## Title: MyAddonName
## Notes: Brief description about what MyAddonName does
## Version: 1.0.0

# This line is a comment

MyFrame.xml
MyCode.lua
lib\MyCode.lua
subfolder\MoreCode.xml
```

### Metadata Directives

| Directive | Description |
|-----------|-------------|
| `## Interface: 120001` | WoW version (Midnight = 120001). Comma-delimited for multi-client |
| `## Title: Name` | Displayed in AddOns list. Supports color codes and localization (`Title-frFR`) |
| `## Notes: Text` | Tooltip in AddOns list. Supports `\|cFFRRGGBB\|r` color codes |
| `## Category: Name` | Collapsible category header in addon list |
| `## Group: ParentAddon` | Groups addon under a parent in the list |
| `## Version: 1.0.0` | Addon version string |
| `## Author: Name` | Author name |
| `## IconTexture: path` | Icon path for addon list |
| `## IconAtlas: atlasName` | Atlas name for addon list icon (lower priority than IconTexture) |
| `## X-Custom: value` | Custom metadata accessible via GetAddOnMetadata() |

### Loading Conditions

| Directive | Description |
|-----------|-------------|
| `## LoadOnDemand: 1` | Delay loading until LoadAddOn() is called |
| `## Dependencies: addon1, addon2` | Must load first (aliases: RequiredDeps, Dep*) |
| `## OptionalDeps: addon1` | Load first if available |
| `## LoadWith: addon1` | Load when specified addon loads (implies LoadOnDemand) |
| `## LoadManagers: addon1` | Makes addon LoadOnDemand when manager is present |
| `## DefaultState: disabled` | Requires explicit user enable |
| `## OnlyBetaAndPTR: 1` | Only loadable on Beta/PTR clients |

### AllowLoadGameType

Restricts loading to specific client flavors:
```toc
## AllowLoadGameType: mainline
```

| Value | Client |
|-------|--------|
| `standard` | Midnight (excluding Plunderstorm) |
| `mainline` | Midnight (including Plunderstorm) |
| `mists` | Mists of Pandaria Classic |
| `cata` | Cataclysm Classic |
| `wrath` | WotLK Classic / Titan Reforged |
| `tbc` | Burning Crusade Classic |
| `vanilla` | Classic Era |
| `plunderstorm` | Plunderstorm mode |
| `classic` | All Classic expansions |

### SavedVariables

```toc
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
```

- Per-account: `WTF/Account/NAME/SavedVariables/AddonName.lua`
- Per-character: `WTF/Account/NAME/Realm/Char/SavedVariables/AddonName.lua`

### Addon Compartment (Minimap Dropdown)

```toc
## AddonCompartmentFunc: MyAddon_OnClick
## AddonCompartmentFuncOnEnter: MyAddon_OnEnter
## AddonCompartmentFuncOnLeave: MyAddon_OnLeave
```

### Per-File Conditions (Added 11.1.5+)

```toc
# Only load on Mainline
MainlineOnly.lua [AllowLoadGameType mainline]

# Only load for English or French clients
Localized.lua [AllowLoadTextLocale enUS, frFR]
```

### Per-File Variables (Added 11.1.5+)

```toc
# Expands to "Mainline\File.lua" or "Classic\File.lua"
[Family]\File.lua

# Expands to "Standard\File.lua", "Mists\File.lua", etc.
[Game]\File.lua

# Expands to "Localization\enUS.lua", "Localization\frFR.lua", etc.
Localization\[TextLocale].lua
```

### Client-Specific TOC Files

| Suffix | Client |
|--------|--------|
| `AddonName_Standard.toc` | Midnight (excl. Plunderstorm) |
| `AddonName_Mainline.toc` | Midnight (incl. Plunderstorm) |
| `AddonName_Classic.toc` | All Classic expansions |
| `AddonName_Mists.toc` | MoP Classic |
| `AddonName_Cata.toc` | Cataclysm Classic |
| `AddonName_Wrath.toc` | WotLK Classic |
| `AddonName_Vanilla.toc` | Classic Era |

## File Loading Order

1. Files load top-to-bottom as listed in the `.toc`
2. XML files can load additional files via `<Script file="..."/>` and `<Include file="..."/>`
3. WoW FrameXML loads first, then addon code, then SavedVariables
4. `ADDON_LOADED` fires after each addon's saved variables load
5. `PLAYER_LOGIN` fires after all non-load-on-demand addons load

## Addon Installation Path

```
World of Warcraft/_retail_/Interface/AddOns/MyAddon/
├── MyAddon.toc
├── MyAddon.lua
├── MyAddon.xml (optional)
└── Libs/ (optional)
```

## File Loading Process

```
1. WoW FrameXML loads
2. Addon Lua/XML files execute (top to bottom per TOC)
3. SavedVariables for each addon load → ADDON_LOADED fires per addon
4. PLAYER_LOGIN fires (all addons loaded, player in world)
5. PLAYER_ENTERING_WORLD fires (initial login or zone change)
```

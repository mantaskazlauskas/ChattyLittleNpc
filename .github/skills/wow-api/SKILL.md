---
name: wow-api
description: "Comprehensive WoW addon API reference for Midnight (Patch 12.0.1). Use when writing, reviewing, or debugging WoW addon Lua/XML code. Covers the full in-game API (C_* namespaces, Widget API, events, scripts, XML schema), Lua 5.1 environment, SavedVariables, secure execution/taint, EventRegistry, escape sequences, CVars, combat log, macros, Settings API, FrameXML utilities, GUIDs, Edit Mode, NPC dialog lifecycle, Battle.net REST API, Raider.IO/WarcraftLogs/Wago third-party APIs, enums/constants, and ChattyLittleNpc-specific patterns. Activates for: WoW API, addon development, Lua WoW, CreateFrame, RegisterEvent, C_GossipInfo, PlaySoundFile, quest dialog, gossip, taint, secure frames, widget API."
---

# WoW API Skill — Midnight (Patch 12.0.1)

> Comprehensive reference for World of Warcraft addon development targeting the Midnight expansion (Patch 12.0.1, Interface 120001). Use this skill when writing, reviewing, or debugging WoW addon Lua/XML code.

## Quick Reference

| Resource | Description |
|----------|-------------|
| [00-cheatsheet.md](./00-cheatsheet.md) | **⚡ Quick-lookup cheat sheet** — top APIs, gotchas, patterns |
| [01-addon-structure.md](./01-addon-structure.md) | TOC format, file loading, addon lifecycle |
| [02-api-systems.md](./02-api-systems.md) | Core C_* namespace API functions by system |
| [03-widget-api.md](./03-widget-api.md) | Widget hierarchy, Frame/Region/Texture methods |
| [04-events.md](./04-events.md) | Frame events by system, handling patterns |
| [05-widget-scripts.md](./05-widget-scripts.md) | OnEvent, OnClick, OnUpdate, etc. script handlers |
| [06-xml-schema.md](./06-xml-schema.md) | XML UI definitions, tags, attributes |
| [07-lua-environment.md](./07-lua-environment.md) | Lua 5.1 in WoW, available/unavailable libraries |
| [08-saved-variables.md](./08-saved-variables.md) | Persisting data between sessions |
| [09-secure-execution.md](./09-secure-execution.md) | Taint, protected functions, secure templates |
| [10-midnight-api-changes.md](./10-midnight-api-changes.md) | Patch 12.0.1 new/removed/changed APIs |
| [11-event-registry.md](./11-event-registry.md) | EventRegistry callback system |
| [12-common-patterns.md](./12-common-patterns.md) | Idiomatic addon code patterns and best practices |
| [13-battlenet-web-api.md](./13-battlenet-web-api.md) | Battle.net REST API (OAuth2, Game Data, Profile) |
| [14-third-party-apis.md](./14-third-party-apis.md) | Raider.IO, Warcraft Logs GraphQL, Wago.io APIs |
| [15-resources-and-links.md](./15-resources-and-links.md) | All documentation sources, tools, Discord links |
| [16-chatty-addon-apis.md](./16-chatty-addon-apis.md) | **ChattyLittleNpc-specific** API usage, events, flows |
| [17-escape-sequences.md](./17-escape-sequences.md) | Color codes, texture markup, hyperlinks, text formatting |
| [18-cvars-combatlog-macros.md](./18-cvars-combatlog-macros.md) | Console variables, combat log parsing, macro commands |
| [19-secure-advanced.md](./19-secure-advanced.md) | SecureHandlers, StateDrivers, intrinsic frames, macro conditionals |
| [20-settings-options.md](./20-settings-options.md) | Modern Settings API, options panels, UI templates |
| [21-framexml-utilities.md](./21-framexml-utilities.md) | Mixins, pools, CopyTable, colors, GUIDs, anchors, formatting |
| [22-editmode-debug-gaps.md](./22-editmode-debug-gaps.md) | Edit Mode API, C_CVar, quest text APIs, templates, debugging |
| [23-npc-dialog-lifecycle.md](./23-npc-dialog-lifecycle.md) | **NPC dialog flow diagrams**, gossip/quest event sequences, queue logic |
| [24-enums-constants.md](./24-enums-constants.md) | PowerType, ItemQuality, class IDs, spell schools, flags, strata |

## Key Facts for Midnight (12.0.1)

- **Interface version**: `120001`
- **TOC suffix for mainline**: `_Standard.toc` or `_Mainline.toc`
- **Lua version**: 5.1 (modified — no os/io/debug libraries)
- **Trig functions**: Use degrees (not radians)
- **No file I/O**: Addons cannot read/write files directly
- **Secure execution**: Protected functions cannot be called from tainted (addon) code during combat
- **SavedVariables**: Loaded after addon code; use ADDON_LOADED event
- **CreateFrame**: Frames cannot be garbage collected — reuse via pools
- **EventRegistry**: Modern callback system; alternative to frame:RegisterEvent

## Conventions

- API functions use `C_SystemName.FunctionName()` namespace pattern
- Widget methods use `WidgetType:MethodName()` pattern
- Events are ALL_CAPS_WITH_UNDERSCORES
- Script handlers are PascalCase prefixed with "On" (OnEvent, OnClick, OnUpdate)
- Protected/secure functions are marked with `#protected` or `#secureframe`
- Combat-restricted functions are marked with `#nocombat`

## ChattyLittleNpc-Relevant APIs

For this addon specifically, the most important API systems are:
- **NPC Dialog**: See [23-npc-dialog-lifecycle.md](./23-npc-dialog-lifecycle.md) for complete dialog flow
- **GossipInfo**: C_GossipInfo namespace for NPC gossip/dialog
- **Quest Dialog**: GetQuestText(), GetProgressText(), GetRewardText(), GetGreetingText()
- **UnitInfo**: UnitName(), UnitGUID(), UnitSex() — "npc" unitID during dialogs
- **Sound**: PlaySoundFile(), StopSound(), C_Sound.IsPlaying() for voiceover
- **AddOns**: ADDON_LOADED event, SavedVariables
- **ChatInfo**: CHAT_MSG_MONSTER_SAY, CHAT_MSG_MONSTER_WHISPER, CHAT_MSG_MONSTER_YELL

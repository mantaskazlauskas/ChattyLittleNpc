# WoW API Documentation Sources & Links

> A comprehensive index of all known WoW API documentation hubs.

## Official Blizzard Sources

| Resource | URL | Type |
|----------|-----|------|
| **Battle.net Developer Portal** | https://develop.battle.net/documentation/world-of-warcraft | Web API docs (SPA) |
| **Blizzard API Forums** | https://us.forums.blizzard.com/en/blizzard/c/api-discussion | Community Q&A |
| **Getting Started Guide** | https://us.forums.blizzard.com/en/blizzard/t/getting-started-with-the-wow-api/12097 | Forum post |
| **In-Game `/api` Command** | Type `/api` in WoW chat | In-game API browser |
| **Blizzard API Docs (Generated)** | https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated | Auto-generated from client |
| **OAuth Client Sample** | https://github.com/Blizzard/oauth-client-sample | Auth example code |

## In-Game AddOn / Lua API Wikis

| Resource | URL | Status | Notes |
|----------|-----|--------|-------|
| **Warcraft Wiki (wiki.gg)** | https://warcraft.wiki.gg/wiki/World_of_Warcraft_API | ✅ Active | Most up-to-date; Patch 12.0.1 |
| **Warcraft Wiki — Widget API** | https://warcraft.wiki.gg/wiki/Widget_API | ✅ Active | Frame/widget methods |
| **Warcraft Wiki — Events** | https://warcraft.wiki.gg/wiki/Events | ✅ Active | All frame events |
| **Warcraft Wiki — Lua Functions** | https://warcraft.wiki.gg/wiki/Lua_functions | ✅ Active | Lua 5.1 in WoW |
| **Warcraft Wiki — Widget Scripts** | https://warcraft.wiki.gg/wiki/Widget_script_handlers | ✅ Active | OnEvent, OnClick, etc. |
| **Warcraft Wiki — XML Schema** | https://warcraft.wiki.gg/wiki/XML_schema | ✅ Active | UI XML definitions |
| **Warcraft Wiki — CVars** | https://warcraft.wiki.gg/wiki/Console_variables | ✅ Active | Console variables |
| **Warcraft Wiki — TOC Format** | https://warcraft.wiki.gg/wiki/TOC_format | ✅ Active | Addon manifest format |
| **Warcraft Wiki — API Changes** | https://warcraft.wiki.gg/wiki/API_change_summaries | ✅ Active | Patch-by-patch diffs |
| **Warcraft Wiki — HOWTOs** | https://warcraft.wiki.gg/wiki/HOWTOs | ✅ Active | Tutorials |
| **Wowpedia (Fandom)** | https://wowpedia.fandom.com/wiki/World_of_Warcraft_API | ⚠️ Defunct | Last updated Patch 10.1.7 (2023) |
| **WoWWiki Archive (Fandom)** | https://wowwiki-archive.fandom.com/wiki/World_of_Warcraft_API | 📦 Archive | Historical reference |
| **AddOn Studio Wiki** | https://addonstudio.org/wiki/WoW:World_of_Warcraft_API | ⚠️ Dated | Older but detailed API reference |
| **wowprogramming.com** | https://wowprogramming.com | ❌ Down | Was a classic reference; currently 404 |

## FrameXML / Source Code

| Resource | URL | Notes |
|----------|-----|-------|
| **Gethe/wow-ui-source** | https://github.com/Gethe/wow-ui-source | Git mirror of Blizzard UI source (retail) |
| **Ketho/BlizzardInterfaceResources** | https://github.com/Ketho/BlizzardInterfaceResources | Templates, globals, widget reference lists |
| **wow-ui-source (MoP Classic)** | https://github.com/Ketho/wow-ui-source-mists | MoP Classic FrameXML |
| **wow-ui-source (Vanilla)** | https://github.com/Ketho/wow-ui-source-vanilla | Classic Era FrameXML |
| **Townlong Yak FrameXML** | https://www.townlong-yak.com/framexml/ | Web-based FrameXML browser (intermittent availability) |
| **UI.xsd Schema** | https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_SharedXML/UI.xsd | XML schema definition |

## Third-Party / Community APIs

| Resource | URL | Type |
|----------|-----|------|
| **Raider.IO API** | https://raider.io/api | M+ rankings, character profiles (Swagger) |
| **Raider.IO OpenAPI Spec** | https://raider.io/openapi.json | Machine-readable spec |
| **Warcraft Logs API v2** | https://www.warcraftlogs.com/api/docs | Combat log data (GraphQL) |
| **Wago.io API** | https://docs.wago.io/ | Addon/WeakAura distribution |
| **Wago Game Versions** | https://addons.wago.io/api/data/game | Available patch versions |
| **Postman Collections** | https://www.postman.com/api-evangelist/blizzard | WoW API collections |
| **WoW.tools** | https://wow.tools/ | Datamining browser |

## Addon Distribution Sites

| Site | URL | Notes |
|------|-----|-------|
| **CurseForge** | https://www.curseforge.com/wow/addons | Largest addon host (Overwolf) |
| **Wago Addons** | https://addons.wago.io | Growing alternative (Method) |
| **WoWInterface** | https://www.wowinterface.com | Classic addon host (Minion) |
| **GitHub** | https://github.com | Many addons hosted here |

## Addon Manager Apps

| App | URL |
|-----|-----|
| **CurseForge (Overwolf)** | https://www.curseforge.com/download/app |
| **WoWUp** | https://wowup.io/ |
| **Wago App** | https://addons.wago.io |

## Community / Discord

| Resource | URL |
|----------|-----|
| **WoW UI Dev Discord** | https://discord.gg/txUg39Vhc6 |
| **Blizzard API Community Discord** | Referenced in forum post |
| **Raider.IO Discord** | https://discord.gg/raider |

## Development Tools

| Tool | URL | Notes |
|------|-----|-------|
| **VS Code** | https://code.visualstudio.com/ | Recommended editor |
| **Red Hat XML Extension** | https://marketplace.visualstudio.com/items?itemName=redhat.vscode-xml | XML validation for WoW UI |
| **Lua Language Server** | https://marketplace.visualstudio.com/items?itemName=sumneko.lua | Lua IntelliSense |
| **WoW API Type Definitions** | https://github.com/ketho-wow/vscode-wow-api | VS Code WoW API completions |
| **BigWigs Packager** | https://github.com/BigWigsMods/packager | Automated addon packaging/release |
| **DevTool (in-game)** | https://www.curseforge.com/wow/addons/devtool | In-game Lua table inspector |

## In-Game Debugging Commands

| Command | Description |
|---------|-------------|
| `/api` | Opens Blizzard's built-in API documentation browser |
| `/fstack` | Frame stack — shows frames under cursor |
| `/etrace` | Event trace — shows events as they fire |
| `/tinspect` | Table inspector — inspect any Lua value |
| `/dump expression` | Evaluate and print a Lua expression |
| `/run lua_code` | Execute Lua code directly |
| `/console cvar value` | Set console variables |
| `/console taintLog 1` | Enable taint logging (check Logs/taint.log) |

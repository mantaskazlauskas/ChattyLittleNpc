# Events System (Patch 12.0.1)

> Events are messages sent by the WoW client to UI code via OnEvent script handlers.
> Full reference: https://warcraft.wiki.gg/wiki/Events

## Handling Events

```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        -- handle addon loaded
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        -- handle entering world
    end
end)
```

### Pattern: Method Dispatch

```lua
local frame, events = CreateFrame("Frame"), {}

function events:PLAYER_ENTERING_WORLD(...)
    -- handle
end

function events:PLAYER_LEAVING_WORLD(...)
    -- handle
end

frame:SetScript("OnEvent", function(self, event, ...)
    events[event](self, ...)
end)
for k, v in pairs(events) do
    frame:RegisterEvent(k)
end
```

### Unit Events (Filtered)

```lua
frame:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
-- Only fires for specified units — more efficient than RegisterEvent
```

## Key Events by Category

### Addon Lifecycle

| Event | Payload | Description |
|-------|---------|-------------|
| `ADDON_LOADED` | addOnName, containsBindings | Fired after each addon's saved variables load |
| `ADDONS_UNLOADING` | closingClient | Fired when addons are about to unload |
| `PLAYER_LOGIN` | — | All non-LoD addons loaded, player in world |
| `PLAYER_LOGOUT` | — | Player logging out (last chance to save data) |
| `PLAYER_ENTERING_WORLD` | isInitialLogin, isReloadingUi | Login, reload, or zone change |
| `PLAYER_LEAVING_WORLD` | — | Player leaving the world |
| `SAVED_VARIABLES_TOO_LARGE` | addOnName | SavedVariables exceeded size limit |

### Chat Messages

| Event | Payload | Description |
|-------|---------|-------------|
| `CHAT_MSG_SAY` | *CHAT_MSG* | Player /say |
| `CHAT_MSG_YELL` | *CHAT_MSG* | Player /yell |
| `CHAT_MSG_WHISPER` | *CHAT_MSG* | Incoming whisper |
| `CHAT_MSG_WHISPER_INFORM` | *CHAT_MSG* | Outgoing whisper |
| `CHAT_MSG_PARTY` | *CHAT_MSG* | Party chat |
| `CHAT_MSG_RAID` | *CHAT_MSG* | Raid chat |
| `CHAT_MSG_GUILD` | *CHAT_MSG* | Guild chat |
| `CHAT_MSG_CHANNEL` | *CHAT_MSG* | Channel chat |
| `CHAT_MSG_EMOTE` | *CHAT_MSG* | Player emote |
| `CHAT_MSG_SYSTEM` | *CHAT_MSG* | System message |
| `CHAT_MSG_ADDON` | prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID | Addon message |
| `CHAT_MSG_MONSTER_SAY` | *CHAT_MSG* | NPC /say |
| `CHAT_MSG_MONSTER_YELL` | *CHAT_MSG* | NPC /yell |
| `CHAT_MSG_MONSTER_WHISPER` | *CHAT_MSG* | NPC whisper |
| `CHAT_MSG_MONSTER_EMOTE` | *CHAT_MSG* | NPC emote |
| `CHAT_MSG_MONSTER_PARTY` | *CHAT_MSG* | NPC party message |
| `CHAT_MSG_RAID_BOSS_EMOTE` | *CHAT_MSG* | Boss emote |
| `CHAT_MSG_RAID_BOSS_WHISPER` | *CHAT_MSG* | Boss whisper |

#### CHAT_MSG Payload Pattern

All CHAT_MSG_* events share this payload:
```lua
text, playerName, languageName, channelName, playerName2, specialFlags,
zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid,
bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons
```

### Unit Events

| Event | Payload | Description |
|-------|---------|-------------|
| `UNIT_HEALTH` | unitTarget | Unit health changed |
| `UNIT_POWER_UPDATE` | unitTarget, powerType | Unit power changed |
| `UNIT_AURA` | unitTarget, updateInfo | Buffs/debuffs changed |
| `UNIT_TARGET` | unitTarget | Unit's target changed |
| `UNIT_NAME_UPDATE` | unitTarget | Unit's name changed |
| `UNIT_SPELLCAST_START` | unitTarget, castGUID, spellID | Cast started |
| `UNIT_SPELLCAST_STOP` | unitTarget, castGUID, spellID | Cast stopped |
| `UNIT_SPELLCAST_SUCCEEDED` | unitTarget, castGUID, spellID | Cast succeeded |
| `UNIT_SPELLCAST_INTERRUPTED` | unitTarget, castGUID, spellID | Cast interrupted |
| `UNIT_SPELLCAST_CHANNEL_START` | unitTarget, castGUID, spellID | Channel started |
| `UNIT_SPELLCAST_CHANNEL_STOP` | unitTarget, castGUID, spellID | Channel stopped |

### Player Events

| Event | Payload | Description |
|-------|---------|-------------|
| `PLAYER_TARGET_CHANGED` | — | Target changed |
| `PLAYER_REGEN_DISABLED` | — | Entered combat |
| `PLAYER_REGEN_ENABLED` | — | Left combat |
| `PLAYER_LEVEL_UP` | level, ... | Player leveled up |
| `PLAYER_MONEY` | — | Money changed |
| `PLAYER_STARTED_MOVING` | — | Player started moving |
| `PLAYER_STOPPED_MOVING` | — | Player stopped moving |
| `PLAYER_DEAD` | — | Player died |
| `PLAYER_ALIVE` | — | Player alive/resurrected |
| `PLAYER_UNGHOST` | — | Player unghosted |
| `PLAYER_MAX_LEVEL_UPDATE` | — | New in 12.0.1 |

### Quest Events

| Event | Payload | Description |
|-------|---------|-------------|
| `QUEST_ACCEPTED` | questID | Quest accepted |
| `QUEST_REMOVED` | questID, wasReplayQuest | Quest removed from log |
| `QUEST_COMPLETE` | — | Quest completion dialog shown |
| `QUEST_DETAIL` | questStartItemID | Quest detail dialog shown |
| `QUEST_FINISHED` | — | Quest dialog closed |
| `QUEST_GREETING` | — | Quest greeting shown |
| `QUEST_LOG_UPDATE` | — | Quest log changed |
| `QUEST_PROGRESS` | — | Quest progress shown |
| `QUEST_TURNED_IN` | questID, xpReward, moneyReward | Quest turned in |

### Gossip Events

| Event | Payload | Description |
|-------|---------|-------------|
| `GOSSIP_SHOW` | — | NPC gossip window opened |
| `GOSSIP_CLOSED` | — | NPC gossip window closed |
| `GOSSIP_CONFIRM` | gossipID, text, cost | Gossip requires confirmation |
| `GOSSIP_ENTER_CODE` | gossipID | Gossip requires code entry |

### Combat Log

| Event | Payload | Description |
|-------|---------|-------------|
| `COMBAT_LOG_EVENT_UNFILTERED` | — | Any combat log event (use CombatLogGetCurrentEventInfo()) |

### Group Events

| Event | Payload | Description |
|-------|---------|-------------|
| `GROUP_ROSTER_UPDATE` | — | Party/raid roster changed |
| `GROUP_FORMED` | category | Group formed |
| `GROUP_LEFT` | category | Left group |
| `PARTY_LEADER_CHANGED` | — | Party leader changed |

### Nameplate Events

| Event | Payload | Description |
|-------|---------|-------------|
| `NAME_PLATE_UNIT_ADDED` | unitToken | Nameplate appeared |
| `NAME_PLATE_UNIT_REMOVED` | unitToken | Nameplate removed |

### Encounter Events (New/Updated in 12.0.1)

| Event | Payload | Description |
|-------|---------|-------------|
| `ENCOUNTER_START` | encounterID, name, difficulty, groupSize | Boss encounter started |
| `ENCOUNTER_END` | encounterID, name, difficulty, groupSize, success | Boss encounter ended |
| `ENCOUNTER_TIMELINE_VIEW_ACTIVATED` | — | New in 12.0.1 |
| `ENCOUNTER_TIMELINE_VIEW_DEACTIVATED` | — | New in 12.0.1 |

### ActionBar Events

| Event | Payload | Description |
|-------|---------|-------------|
| `ACTIONBAR_SLOT_CHANGED` | slot | Slot contents changed |
| `ACTIONBAR_UPDATE_COOLDOWN` | — | Cooldowns updated |
| `ACTIONBAR_UPDATE_STATE` | — | Action states updated |
| `ACTIONBAR_UPDATE_USABLE` | — | Usability changed |
| `ACTION_USABLE_CHANGED` | changes | Fine-grained usability |
| `ACTION_RANGE_CHECK_UPDATE` | slot, isInRange, checksRange | Range check |

### Talent Events

| Event | Payload | Description |
|-------|---------|-------------|
| `ACTIVE_COMBAT_CONFIG_CHANGED` | configID | Talent config changed |
| `SELECTED_LOADOUT_CHANGED` | — | Loadout switched |

### Housing Events (New in 12.0.x)

| Event | Payload | Description |
|-------|---------|-------------|
| `HOUSING_CLEANUP_MODE_HOVERED_TARGET_CHANGED` | ... | Housing hover target changed |

### Photo Sharing Events (New in 12.0.1)

| Event | Payload | Description |
|-------|---------|-------------|
| `PHOTO_SHARING_AUTHORIZATION_NEEDED` | — | Auth needed |
| `PHOTO_SHARING_AUTHORIZATION_UPDATED` | — | Auth updated |
| `PHOTO_SHARING_PHOTO_UPLOAD_STATUS` | — | Upload status |
| `PHOTO_SHARING_SCREENSHOT_READY` | — | Screenshot ready |
| `PHOTO_SHARING_THIRD_PARTY_AUTHORIZATION_NEEDED` | — | Third-party auth needed |

### Container/Bag Events

| Event | Payload | Description |
|-------|---------|-------------|
| `BAG_UPDATE` | bagID | Bag contents changed |
| `BAG_UPDATE_DELAYED` | — | Deferred bag update |
| `BAG_UPDATE_COOLDOWN` | — | Bag item cooldown changed |
| `BAG_OPEN` | bagID | Bag opened |
| `BAG_CLOSED` | bagID | Bag closed |
| `ITEM_LOCK_CHANGED` | bagOrSlotIndex, slotIndex | Item lock state changed |

### Delves Events

| Event | Payload | Description |
|-------|---------|-------------|
| `ACTIVE_DELVE_DATA_UPDATE` | — | Delve data changed |
| `DELVE_ASSIST_ACTION` | data | Delve assist action |
| `SHOW_DELVES_COMPANION_CONFIGURATION_UI` | — | Show companion config |
| `WALK_IN_DATA_UPDATE` | — | Walk-in data changed |

### Damage Meter Events

| Event | Payload | Description |
|-------|---------|-------------|
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` | type, sessionID | Session updated |
| `DAMAGE_METER_CURRENT_SESSION_UPDATED` | — | Current session changed |
| `DAMAGE_METER_RESET` | — | Meter reset |

### Edit Mode Events

| Event | Payload | Description |
|-------|---------|-------------|
| `EDIT_MODE_LAYOUTS_UPDATED` | layoutInfo, reconcileLayouts | Layouts changed |

### Currency Events

| Event | Payload | Description |
|-------|---------|-------------|
| `CURRENCY_DISPLAY_UPDATE` | currencyType, quantity, change, source, reason | Currency changed |
| `PLAYER_MONEY` | — | Gold/silver/copper changed |

## Event Debugging

Use `/etrace` to open the Event Trace panel for inspecting events in real-time.

## EventRegistry (Modern Alternative)

See [11-event-registry.md](./11-event-registry.md) for the callback-based EventRegistry system.

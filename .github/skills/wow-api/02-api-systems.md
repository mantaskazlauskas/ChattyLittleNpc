# Core API Systems (Patch 12.0.1)

> Up to date as of Patch 12.0.1 (65893) Feb 11 2026.
> Full reference: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API

## API Namespace Pattern

Most APIs follow the `C_SystemName.FunctionName(args) : returns` pattern. Some older APIs are global functions without the `C_` prefix.

## Key API Systems

### C_AddOns — Addon Management

```lua
C_AddOns.GetAddOnInfo(name) : name, title, notes, loadable, reason, security
C_AddOns.IsAddOnLoaded(name) : loadedOrLoading, loaded
C_AddOns.LoadAddOn(name) : loaded, value  -- Load on-demand addon
C_AddOns.GetAddOnMetadata(name, variable) : value  -- Read TOC metadata
C_AddOns.GetNumAddOns() : numAddOns
C_AddOns.EnableAddOn(name [, character])
C_AddOns.DisableAddOn(name [, character])
C_AddOns.GetAddOnDependencies(name) : deps
```

### C_ChatInfo — Chat System

```lua
C_ChatInfo.GetChannelInfoFromIdentifier(channelIdentifier) : info
C_ChatInfo.GetNumActiveChannels() : numChannels
C_ChatInfo.RegisterAddonMessagePrefix(prefix) : registered
C_ChatInfo.SendAddonMessage(prefix, message, chatType [, target])
C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) : isRegistered
```

Related global functions:
```lua
SendChatMessage(msg, chatType, languageID, target)
GetDefaultLanguage() : language, languageID
```

### C_GossipInfo — NPC Gossip/Dialog

```lua
C_GossipInfo.GetActiveQuests() : info
C_GossipInfo.GetAvailableQuests() : info
C_GossipInfo.GetOptions() : info  -- Get gossip options
C_GossipInfo.GetText() : text  -- Get gossip text
C_GossipInfo.GetNumActiveQuests() : numQuests
C_GossipInfo.GetNumAvailableQuests() : numQuests
C_GossipInfo.GetNumOptions() : numOptions
C_GossipInfo.SelectActiveQuest(index)
C_GossipInfo.SelectAvailableQuest(index)
C_GossipInfo.SelectOption(optionID [, text, confirmed])
C_GossipInfo.CloseGossip()
C_GossipInfo.ForceGossip() : forceGossip
```

### C_QuestLog — Quest System

```lua
C_QuestLog.GetInfo(questLogIndex) : info
C_QuestLog.GetLogIndexForQuestID(questID) : questLogIndex
C_QuestLog.GetNumQuestLogEntries() : numEntries, numQuests
C_QuestLog.GetQuestObjectives(questID) : objectives
C_QuestLog.GetQuestTagInfo(questID) : info
C_QuestLog.GetSelectedQuest() : questID
C_QuestLog.GetTitleForQuestID(questID) : title
C_QuestLog.IsComplete(questID) : isComplete
C_QuestLog.IsQuestFlaggedCompleted(questID) : isCompleted
C_QuestLog.IsOnQuest(questID) : isOnQuest
C_QuestLog.SetSelectedQuest(questID)
```

### C_Map — Map System

```lua
C_Map.GetBestMapForUnit(unitToken) : uiMapID
C_Map.GetMapInfo(uiMapID) : info
C_Map.GetPlayerMapPosition(uiMapID, unitToken) : position
C_Map.GetWorldPosFromMapPos(uiMapID, mapPosition) : continentID, worldPosition
```

### C_NamePlate — Nameplates

```lua
C_NamePlate.GetNamePlateForUnit(unitToken) : frame
C_NamePlate.GetNamePlates() : frames
C_NamePlate.SetNamePlateFriendlyClickThrough(clickThrough)
C_NamePlate.SetNamePlateEnemyClickThrough(clickThrough)
```

### C_Timer — Timer System

```lua
C_Timer.After(duration, callback)  -- One-shot timer
C_Timer.NewTimer(duration, callback) : timer  -- Cancelable timer
C_Timer.NewTicker(duration, callback [, iterations]) : ticker
-- ticker:Cancel() to stop
```

### C_Spell — Spell Information

```lua
C_Spell.GetSpellInfo(spellID) : info
C_Spell.GetSpellName(spellID) : name
C_Spell.GetSpellTexture(spellID) : iconID
C_Spell.GetSpellDescription(spellID) : description
C_Spell.GetSpellCooldown(spellID) : cooldownInfo
C_Spell.IsSpellUsable(spellID) : isUsable, insufficientResources
```

### C_Item — Item Information

```lua
C_Item.GetItemInfo(itemID) : info
C_Item.GetItemNameByID(itemID) : itemName
C_Item.GetItemIconByID(itemID) : icon
C_Item.GetItemQualityByID(itemID) : quality
C_Item.IsItemDataCachedByID(itemID) : isCached
C_Item.RequestLoadItemDataByID(itemID)
```

### C_ClassTalents — Talent System

```lua
C_ClassTalents.GetActiveConfigID() : configID
C_ClassTalents.GetHasStarterBuild() : hasStarterBuild
```

### C_ActionBar — Action Bars

```lua
C_ActionBar.HasAction(actionID) : hasAction
C_ActionBar.GetActionTexture(actionID) : textureFileID
C_ActionBar.GetActionText(actionID) : text
C_ActionBar.IsUsableAction(actionID) : isUsable, isLackingResources
C_ActionBar.IsActionInRange(actionID [, target]) : isInRange
C_ActionBar.GetActionCooldown(actionID) : cooldownInfo
```

### C_Container — Bag/Inventory

```lua
C_Container.GetContainerNumSlots(bagIndex) : numSlots
C_Container.GetContainerItemInfo(bagIndex, slotIndex) : info
C_Container.GetContainerItemID(bagIndex, slotIndex) : itemID
C_Container.UseContainerItem(bagIndex, slotIndex)
C_Container.PickupContainerItem(bagIndex, slotIndex)
```

### C_FriendList — Social

```lua
C_FriendList.GetNumFriends() : numFriends
C_FriendList.GetNumOnlineFriends() : numOnline
C_FriendList.GetFriendInfo(friendIndex) : info
```

### C_DelvesUI — Delves (New in TWW/Midnight)

```lua
C_DelvesUI.GetPlayerCompanionPDEID() : pdeID
C_DelvesUI.GetTieredEntrancePDEID() : pdeID
```

### Global Unit Functions

```lua
UnitName(unitID) : name, realm
UnitGUID(unitID) : guid
UnitClass(unitID) : className, classFilename, classID
UnitRace(unitID) : raceName, raceFilename, raceID
UnitLevel(unitID) : level
UnitHealth(unitID) : health
UnitHealthMax(unitID) : maxHealth
UnitPower(unitID [, powerType]) : power
UnitPowerMax(unitID [, powerType]) : maxPower
UnitExists(unitID) : exists
UnitIsDeadOrGhost(unitID) : isDead
UnitIsPlayer(unitID) : isPlayer
UnitIsUnit(unit1, unit2) : isSame
UnitCreatureType(unitID) : creatureType
UnitCreatureFamily(unitID) : creatureFamily
UnitIsFriend(unit1, unit2) : isFriend
UnitIsEnemy(unit1, unit2) : isEnemy
UnitAffectingCombat(unitID) : inCombat
UnitCastingInfo(unitID) : name, text, texture, startTimeMS, endTimeMS, ...
UnitChannelInfo(unitID) : name, text, texture, startTimeMS, endTimeMS, ...
```

### Unit IDs

| UnitID | Description |
|--------|-------------|
| `player` | The player character |
| `target` | Current target |
| `focus` | Focus target |
| `pet` | Player's pet |
| `party1`-`party4` | Party members |
| `raid1`-`raid40` | Raid members |
| `boss1`-`boss8` | Boss frames |
| `arena1`-`arena5` | Arena opponents |
| `npc` | NPC in gossip/quest dialog |
| `mouseover` | Unit under mouse cursor |
| `nameplate1`+ | Nameplate units |

### Sound Functions

```lua
PlaySound(soundKitID [, channel, forceNoDuplicates])
PlaySoundFile(sound [, channel]) : willPlay, soundHandle
-- sound: FileDataID (number) or addon file path (string)
-- channel: "Master", "SFX", "Music", "Ambience", "Dialog", "Talking Head"
-- Returns: willPlay (bool), soundHandle (number) for StopSound
-- Addon files: "Interface\\AddOns\\MyAddon\\sound.ogg" (.ogg/.mp3)
-- File must exist BEFORE login/reload

StopSound(soundHandle [, fadeoutTime])
-- fadeoutTime in milliseconds (0 = immediate)

MuteSoundFile(soundFileID)
UnmuteSoundFile(soundFileID)

-- Check playback status
C_Sound.IsPlaying(soundHandle) : isPlaying
```

**Sound channels & CVars:**
| Channel | Toggle CVar | Volume CVar |
|---------|-------------|-------------|
| `Master` | Sound_EnableAllSound | Sound_MasterVolume |
| `SFX` | Sound_EnableSFX | Sound_SFXVolume |
| `Music` | Sound_EnableMusic | Sound_MusicVolume |
| `Ambience` | Sound_EnableAmbience | Sound_AmbienceVolume |
| `Dialog` | Sound_EnableDialog | Sound_DialogVolume |

### Tooltip Functions

```lua
GameTooltip:SetOwner(owner, anchor)
GameTooltip:SetUnit(unitID)
GameTooltip:SetSpellByID(spellID)
GameTooltip:SetItemByID(itemID)
GameTooltip:SetHyperlink(link)
GameTooltip:AddLine(text [, r, g, b, wrap])
GameTooltip:AddDoubleLine(leftText, rightText [, ...colors])
GameTooltip:Show()
GameTooltip:Hide()
```

### Slash Commands

```lua
-- Register a slash command
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"  -- Alias
function SlashCmdList.MYADDON(msg, editBox)
    -- msg = text after the slash command
    print("Command received:", msg)
end
```

### Print / Chat Output

```lua
print(...)  -- Prints to default chat frame
DEFAULT_CHAT_FRAME:AddMessage(text [, r, g, b])
```

### Miscellaneous Global Functions

```lua
GetTime() : seconds  -- Game time in seconds (float)
GetServerTime() : serverTime  -- Server Unix timestamp
time() : epoch  -- Lua time() — seconds since epoch
GetLocale() : locale  -- "enUS", "frFR", etc.
GetBuildInfo() : version, build, date, tocVersion
GetRealmName() : realmName
GetNormalizedRealmName() : realmName  -- No spaces
InCombatLockdown() : inCombat  -- True if in combat lockdown
IsInInstance() : inInstance, instanceType
IsInGroup() : inGroup
IsInRaid() : inRaid
```

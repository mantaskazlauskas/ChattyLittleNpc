# ChattyLittleNpc — Addon-Specific API Reference

> APIs, events, and patterns specifically used by the ChattyLittleNpc addon.
> This file is the most important reference when working on this addon's code.

## Addon Metadata

```toc
## Interface: 120001, 50503, 40402, 30405, 20505, 11508
## SavedVariables: ChattyLittleNpcDB, NpcInfoDB, UnitInfoDB
```

- **Multi-client**: Retail through Classic Era
- **No external libraries** — fully self-contained custom systems

## Events Used

### Core Lifecycle
| Event | Usage |
|-------|-------|
| `ADDON_LOADED` | Initialize SavedVariables, set up systems |
| `PLAYER_LOGIN` | Deferred init after all addons loaded |

### NPC Dialog/Gossip
| Event | Usage |
|-------|-------|
| `GOSSIP_SHOW` | NPC gossip window opens → get text via `C_GossipInfo.GetText()` |
| `GOSSIP_CLOSED` | Gossip window closes → stop/queue voiceover |
| `QUEST_GREETING` | Quest giver greeting (multiple quests) |
| `QUEST_DETAIL` | Quest detail text shown (accept dialog) |
| `QUEST_PROGRESS` | Quest progress text (turn-in not ready) |
| `QUEST_COMPLETE` | Quest completion text (turn-in dialog) |
| `QUEST_FINISHED` | Quest dialog closed (any type) |
| `ITEM_TEXT_READY` | Book/letter/item text ready to read |

### Combat State
| Event | Usage |
|-------|-------|
| `PLAYER_REGEN_DISABLED` | Entered combat → may pause/stop voiceover |
| `PLAYER_REGEN_ENABLED` | Left combat → may resume |

### Cinematics (Audio Interruption)
| Event | Usage |
|-------|-------|
| `CINEMATIC_START` | Cinematic playing → pause voiceover |
| `PLAY_MOVIE` | Movie playing → pause voiceover |

### UI State
| Event | Usage |
|-------|-------|
| `EDIT_MODE_LAYOUTS_UPDATED` | Edit mode layout changes |
| `CVAR_UPDATE` | Console variable changes |
| `UI_SCALE_CHANGED` | UI scale changes → reposition |
| `DISPLAY_SIZE_CHANGED` | Resolution changes → reposition |
| `UPDATE_MOUSEOVER_UNIT` | Mouseover unit changed |
| `PLAYER_TARGET_CHANGED` | Target changed |

### Custom Internal Messages
| Message | Usage |
|---------|-------|
| `VOICEOVER_STOP` | Audio finished → play next in queue or clean up UI |

## Key API Functions

### NPC Text & Gossip
```lua
C_GossipInfo.GetText() : gossipText
-- Available when GOSSIP_SHOW fires. Returns the gossip dialog text.

GetQuestID() : questID
-- Returns the current quest ID in a quest dialog.

-- NOTE: There is no GetQuestPhase() API. The dialog phase is determined by
-- which event fired: QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_GREETING

-- Quest dialog text functions (available during quest events)
GetTitleText() : title            -- Quest title from dialog window
GetQuestText() : text             -- QUEST_DETAIL body text
GetProgressText() : text          -- QUEST_PROGRESS body text
GetRewardText() : text            -- QUEST_COMPLETE body text
GetGreetingText() : text          -- QUEST_GREETING body text
GetObjectiveText() : text         -- Quest objective text
QuestGetAutoAccept() : autoAccept -- Whether quest auto-accepts

C_QuestLog.GetTitleForQuestID(questID) : title
-- Returns quest title by ID.

C_QuestLog.GetSelectedQuest() : questID
-- Returns the currently selected quest in the quest log.
```

### Unit Information
```lua
UnitName("npc") : name, realm
-- Returns the NPC's name during gossip/quest dialogs.
-- "npc" unitID is only valid when a gossip/quest frame is open.

UnitSex("npc") : sex
-- Returns 1=unknown, 2=male, 3=female. Used for voice selection.

UnitRace("npc") : raceName, raceFile, raceID
-- Returns the NPC's race (for character-type NPCs).

UnitGUID("npc") : guid
-- Returns globally unique identifier. Format: "Creature-0-XXXX-XXXX-XXXX-XXXX-XXXX"
-- Parse with: local type, _, serverID, instanceID, zoneUID, npcID, spawnUID = strsplit("-", guid)
```

### Sound Playback

> Full reference: [02-api-systems.md — Sound Functions](./02-api-systems.md)

```lua
-- Core pattern used by ChattyLittleNpc:
local willPlay, soundHandle = PlaySoundFile(
    "Interface\\AddOns\\ChattyLittleNpc\\Sounds\\npc_greeting.ogg",
    db.audioChannel  -- "Master", "Dialog", "SFX", etc.
)
StopSound(soundHandle, 0)           -- Stop immediately
C_Sound.IsPlaying(soundHandle)      -- Check if still playing
```

Key facts: .ogg/.mp3 accepted. File must exist before login/reload. Both `/` and `\\` work.

### Timer System
```lua
-- One-shot timer (non-cancellable)
C_Timer.After(delay, function()
    -- runs once after delay seconds
end)

-- Cancellable timer
local timer = C_Timer.NewTimer(delay, function()
    -- runs once after delay seconds
end)
timer:Cancel()

-- Repeating ticker
local ticker = C_Timer.NewTicker(interval, function()
    -- runs every interval seconds
end)
ticker:Cancel()  -- Stop the ticker

-- Current game time (high precision float)
local now = GetTime()
```

### Item Text (Books/Letters)
```lua
ItemTextGetItem() : itemName
-- Returns the name of the book/letter item.

ItemTextGetText() : text
-- Returns the text content of the book/letter.

-- Triggered by ITEM_TEXT_READY event
```

### Addon Detection
```lua
C_AddOns.IsAddOnLoaded("SomeOtherAddon") : loadedOrLoading, loaded
-- Check if another addon is loaded (e.g., for compatibility).
```

### Realm & Locale
```lua
GetRealmName() : realmName           -- "Tichondrius" (with spaces)
GetLocale() : locale                 -- "enUS", "deDE", "frFR", etc.
GetBuildInfo() : version, build, date, tocVersion
```

### Secure Hooking
```lua
-- Hook Blizzard frames without causing taint
hooksecurefunc("SomeGlobalFunction", function(...)
    -- runs AFTER original
end)

frame:HookScript("OnShow", function(self)
    -- runs AFTER existing OnShow
end)
```

## Model Display System

> Full API reference: [03-widget-api.md — PlayerModel & ModelScene](./03-widget-api.md)

ChattyLittleNpc uses a **dual-backend** model display system:

### Backend Selection (`renderBackend` setting)
- `"auto"` — Use ModelScene on Shadowlands+ clients, PlayerModel on older
- `"scene"` — Force ModelScene (modern, better lighting/animation)
- `"player"` — Force PlayerModel (legacy, wider compatibility)

### Key Usage Patterns

```lua
-- PlayerModel (legacy): Display NPC from gossip/quest dialog
local model = CreateFrame("PlayerModel", name, parent)
model:SetUnit("npc")               -- During GOSSIP_SHOW / QUEST_DETAIL
model:SetDisplayInfo(displayID)     -- By creature display ID
model:SetSequence(60)               -- EmoteTalk animation
model:SetFacing(radians)
model:SetCamera(0)
model:SetLight(enabled, lightTable)

-- ModelScene (modern): Display NPC with better rendering
local scene = CreateFrame("ModelScene", name, parent, "ModelSceneFrameTemplate")
local actor = scene:CreateActor("npc", "ModelSceneActorTemplate")
actor:SetModelByCreatureDisplayID(displayID)
actor:SetModelByUnit("npc")
actor:SetAnimation(60, 0, 1.0)     -- animID, variation, speed
scene:SetCameraOrientationByYawPitchRoll(yaw, pitch, roll)

-- Display info lookup
local info = C_ModelInfo.GetModelSceneActorDisplayInfoByID(displayID)
-- Returns: { animation, animationVariation, animSpeed, animationKitID, ... }
```

## SavedVariables Structure

```lua
ChattyLittleNpcDB = {
    profile = {
        -- Playback
        autoPlayVoiceovers = true,
        playVoiceoverAfterDelay = false,
        questPlaybackMode = "queue",  -- "queue" | "stopOnClose" | "manual"
        audioChannel = "MASTER",

        -- UI Display
        showReplayFrame = true,
        alwaysShowReplayFrame = true, -- legacy (not user-facing; frame always uses idle-fade)
        compactMode = false,
        highContrastMode = false,

        -- Model Rendering
        renderBackend = "auto",  -- "auto" | "scene" | "player"
        npcModelFrameHeight = number,

        -- Logging
        logNpcTexts = true,
        printNpcTexts = false,
        logToChat = false,

        -- Debug
        debugMode = false,
        debugAnimations = false,

        -- Position & Layout
        framePos = { point, relPoint, x, y },
        frameSize = { width, height },
        editModeLayouts = {},
    }
}

NpcInfoDB = {
    -- Cached NPC metadata keyed by some identifier
}

UnitInfoDB = {
    -- Cached unit information
}
```

## Quest Queue Flow

```
GOSSIP_SHOW / QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE
    ↓
Extract text → Identify NPC → Find audio file
    ↓
PlaySoundFile(path, channel) → returns soundHandle
    ↓
C_Timer.NewTicker(0.5s) polls C_Sound.IsPlaying(soundHandle)
    ↓
When finished → fire "VOICEOVER_STOP" internal message
    ↓
If queue mode → play next quest in CLN.questsQueue[]
If stopOnClose → stop when dialog closes (QUEST_FINISHED / GOSSIP_CLOSED)
If manual → wait for user replay click
```

## Slash Commands

```lua
/clndebug      -- Debug model window
/clnmodel      -- Model testing
/clnlogs       -- Animation/event logs viewer
/clnexp        -- Export layout to clipboard
/clnimp        -- Import layout from clipboard
/clnlayoutdebug -- Layout detection debug
```

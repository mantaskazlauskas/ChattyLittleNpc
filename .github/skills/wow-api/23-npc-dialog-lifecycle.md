# NPC Dialog Lifecycle & Quest/Gossip Deep Dive

> Complete reference for NPC interaction flow — the core of ChattyLittleNpc.
> This covers gossip, quest dialogs, item text, and the event sequence.

## NPC Dialog Event Flow

### Gossip Dialog (NPC with multiple options)

```
Player right-clicks NPC
    ↓
GOSSIP_SHOW ──────────────────────── C_GossipInfo.GetText() available
    │                                UnitName("npc") available
    │                                UnitGUID("npc") available
    │                                UnitSex("npc") available
    │                                C_GossipInfo.GetOptions() available
    │                                C_GossipInfo.GetActiveQuests() available
    │                                C_GossipInfo.GetAvailableQuests() available
    ↓
Player selects gossip option ─────── C_GossipInfo.SelectOption(optionID)
    ↓
GOSSIP_CLOSED ────────────────────── Dialog closed
    ↓
(may chain to QUEST_DETAIL, another GOSSIP_SHOW, or nothing)
```

### Quest Accept Dialog (Single quest from NPC)

```
Player right-clicks quest giver (single quest)
    ↓
QUEST_DETAIL ─────────────────────── GetTitleText() available
    │                                GetQuestText() available (detail body)
    │                                GetQuestID() available
    │                                GetObjectiveText() available
    │                                QuestGetAutoAccept() available
    ↓
Player clicks Accept
    ↓
QUEST_ACCEPTED ───────────────────── questID payload
    ↓
QUEST_FINISHED ───────────────────── Dialog window closed
```

### Quest Greeting (Multiple quests from NPC)

```
Player right-clicks NPC with multiple quests
    ↓
QUEST_GREETING ───────────────────── GetGreetingText() available
    │                                Lists available/active quests
    ↓
Player selects a quest
    ↓
QUEST_DETAIL ─────────────────────── GetTitleText(), GetQuestText()
    ↓
(accept flow continues as above)
```

### Quest Turn-in (Progress → Complete)

```
Player talks to quest turn-in NPC
    ↓
QUEST_PROGRESS ───────────────────── GetProgressText() available
    │                                GetTitleText() available
    │                                Quest not yet completable (items needed)
    ↓
(if completable, may skip directly to:)
    ↓
QUEST_COMPLETE ───────────────────── GetRewardText() available
    │                                GetTitleText() available
    │                                GetQuestID() available
    ↓
Player clicks Complete Quest
    ↓
QUEST_TURNED_IN ──────────────────── questID, xpReward, moneyReward
    ↓
QUEST_FINISHED ───────────────────── Dialog window closed
```

### Quest Dialog Closed (Any Type)

```
QUEST_FINISHED fires whenever:
  - Player closes any quest dialog
  - Player accepts a quest
  - Quest auto-accepts
  - Player walks away from NPC
  - NPC dialog transitions
```

### Gossip → Quest Chain

```
GOSSIP_SHOW → Player selects quest option
    ↓
GOSSIP_CLOSED (gossip window closes)
    ↓
QUEST_DETAIL (quest detail opens)
    ↓
(quest accept flow)
```

### Item Text (Books, Letters, Plaques)

```
Player reads a book/letter/plaque
    ↓
ITEM_TEXT_READY ──────────────────── ItemTextGetItem() available
    │                                ItemTextGetText() available
    │                                ItemTextGetPage() for current page
    │                                ItemTextGetMaterial() for texture
    │                                ItemTextHasNextPage() for pagination
    ↓
(Player closes book)
    ↓
ITEM_TEXT_CLOSED ──────────────────── (if applicable)
```

## Key API Functions by Dialog Type

### During GOSSIP_SHOW

```lua
C_GossipInfo.GetText() : gossipText        -- NPC's spoken text
C_GossipInfo.GetOptions() : options         -- Available dialog options
-- Each option: { name, gossipOptionID, status, orderIndex, flags, ... }

C_GossipInfo.GetNumOptions() : numOptions
C_GossipInfo.GetActiveQuests() : quests     -- Quests that can be turned in
C_GossipInfo.GetAvailableQuests() : quests  -- Quests that can be accepted
C_GossipInfo.GetNumActiveQuests() : num
C_GossipInfo.GetNumAvailableQuests() : num

C_GossipInfo.SelectOption(optionID [, text, confirmed])
C_GossipInfo.SelectActiveQuest(index)
C_GossipInfo.SelectAvailableQuest(index)
C_GossipInfo.CloseGossip()
C_GossipInfo.ForceGossip() : forceGossip
```

### During QUEST_DETAIL

```lua
GetTitleText() : title                      -- Quest title
GetQuestText() : text                       -- Quest description body
GetObjectiveText() : text                   -- Objective summary
GetQuestID() : questID                      -- Current quest ID
QuestGetAutoAccept() : autoAccept           -- Auto-accept flag
GetNumQuestRewards() : numRewards           -- Reward count
GetNumQuestChoices() : numChoices           -- Choice reward count
```

### During QUEST_PROGRESS

```lua
GetTitleText() : title
GetProgressText() : text                    -- "Bring me 10 wolf pelts"
GetQuestID() : questID
IsQuestCompletable() : completable          -- Can turn in now?
GetQuestItemInfo(type, index) : name, texture, count
```

### During QUEST_COMPLETE

```lua
GetTitleText() : title
GetRewardText() : text                      -- Completion/reward text
GetQuestID() : questID
GetNumQuestRewards() : numRewards
GetNumQuestChoices() : numChoices
GetRewardXP() : xp
GetRewardMoney() : copper
```

### During QUEST_GREETING

```lua
GetGreetingText() : text                    -- "Greetings, traveler..."
GetNumActiveQuests() : num                  -- Turn-in quests listed
GetNumAvailableQuests() : num               -- Accept quests listed
GetActiveTitle(index) : title, isComplete
GetAvailableTitle(index) : title, isTrivial, ...
SelectActiveQuest(index)
SelectAvailableQuest(index)
```

### Unit Information (During any NPC dialog)

```lua
-- "npc" unitID is valid while a gossip/quest frame is open
UnitName("npc") : name, realm
UnitGUID("npc") : guid                     -- Parse for npcID
UnitSex("npc") : sex                       -- 1=unknown, 2=male, 3=female
UnitRace("npc") : raceName, raceFile, raceID
UnitCreatureType("npc") : creatureType     -- "Humanoid", "Beast", etc.

-- GUID parsing for NPC ID
local guid = UnitGUID("npc")
local npcID = guid and select(6, strsplit("-", guid))
npcID = npcID and tonumber(npcID)
```

## ChattyLittleNpc Quest Queue Logic

### Queue Mode

```
QUEST_DETAIL fires
    → Extract text, NPC info, find audio
    → Add to CLN.questsQueue[]
    → If nothing playing: start playback
    → If already playing: queue waits

VOICEOVER_STOP fires (audio finished)
    → Remove completed entry from queue
    → If more in queue: play next
    → If queue empty: clean up UI

QUEST_FINISHED / GOSSIP_CLOSED fires
    → In "stopOnClose" mode: stop current audio
    → In "queue" mode: let audio continue
    → In "manual" mode: no auto-play
```

### Deduplication

```lua
-- Prevent same quest phase from queuing twice
-- Key: questID + phase (e.g., "12345_detail", "12345_progress")
-- Check before adding to queue
```

### Audio Playback Monitoring

```lua
-- Start playback
local willPlay, soundHandle = PlaySoundFile(path, db.audioChannel)

-- Monitor completion with ticker
local watcher = C_Timer.NewTicker(0.5, function()
    if not C_Sound.IsPlaying(soundHandle) then
        watcher:Cancel()
        -- Fire internal VOICEOVER_STOP message
        EventSystem:Fire("VOICEOVER_STOP")
    end
end)

-- Stop playback
StopSound(soundHandle, 0)
```

## Events Quick Reference

| Event | When | Key APIs Available |
|-------|------|-------------------|
| `GOSSIP_SHOW` | NPC gossip opens | C_GossipInfo.GetText(), UnitName("npc") |
| `GOSSIP_CLOSED` | Gossip closes | — |
| `QUEST_GREETING` | Multi-quest NPC | GetGreetingText() |
| `QUEST_DETAIL` | Quest accept dialog | GetQuestText(), GetTitleText() |
| `QUEST_PROGRESS` | Quest turn-in (incomplete) | GetProgressText() |
| `QUEST_COMPLETE` | Quest turn-in (complete) | GetRewardText() |
| `QUEST_FINISHED` | Any quest dialog closes | — |
| `QUEST_ACCEPTED` | Quest accepted | questID |
| `QUEST_TURNED_IN` | Quest turned in | questID, xp, money |
| `ITEM_TEXT_READY` | Book/letter ready | ItemTextGetText() |
| `CINEMATIC_START` | Cinematic plays | (pause audio) |
| `PLAY_MOVIE` | Movie plays | (pause audio) |
| `PLAYER_REGEN_DISABLED` | Combat starts | (maybe pause) |
| `PLAYER_REGEN_ENABLED` | Combat ends | (maybe resume) |

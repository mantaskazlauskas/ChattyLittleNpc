# Chatty Little NPC public API

For addon authors who want to play, stop or react to voiceovers. Everything on `ChattyLittleNpc.API` is supported. Anything else on `ChattyLittleNpc` is internal and can change in any release.

## Getting started

Add the addon as an optional dependency, then check for the API before using it:

```
## OptionalDeps: ChattyLittleNpc
```

```lua
local CLN = ChattyLittleNpc and ChattyLittleNpc.API
if CLN and CLN.version == 1 then
    if CLN.HasQuestVoiceover(questId, "Desc") then
        CLN.PlayQuest(questId, "Desc", npcId)
    end
end
```

Call functions with a dot (`API.PlayQuest(...)`), not a colon. Before the addon has finished loading, `IsReady()` returns `false`, queries return `false`, `nil` or `0`, and actions do nothing.

`API.version` goes up only when an existing function changes incompatibly, so check for the exact version you were written against. New functions don't change it.

## Quest phases

`phase` is `"Desc"`, `"Prog"` or `"Comp"`. Blizzard-style names such as `"detail"`, `"progress"` and `"completion"` also work, in any case.

## Checking state

| Function | Returns |
| --- | --- |
| `IsReady()` | `boolean`: the addon has loaded and the other functions will work |
| `IsPlaying()` | `boolean`: a voiceover is audibly playing; `false` while paused |
| `IsPaused()` | `boolean`: the player paused playback |
| `GetCurrent()` | A copy of the current line (see [Line records](#line-records)), or `nil` |
| `GetAutoPlayDelay()` | `number`: seconds the player wants to wait before a voiceover starts automatically |

## Finding voiceovers

These only count voiceovers the player can hear, in their selected language.

| Function | Returns |
| --- | --- |
| `HasQuestVoiceover(questId, phase)` | `boolean` |
| `HasGossipVoiceover(npcId, soundType, text, gender)` | `boolean` |

- `soundType` is `"Gossip"`, `"GameObject"` or `"Item"`.
- `text` must be exactly the text shown in game, because voiceovers are matched by a hash of it.
- `gender` is `"Male"`, `"Female"`, `"Neutral"` or `nil`. Some lines are recorded separately for each gender. Without one, the addon uses the gender it last saw for that NPC, if any.

## Controlling playback

| Function | What it does |
| --- | --- |
| `PlayQuest(questId, phase, npcId)` | Plays a quest voiceover. `npcId` is optional and sets the portrait |
| `PlayGossip(npcId, soundType, text, gender)` | Plays a gossip, object or item voiceover |
| `Stop(options)` | Stops the current line |
| `Pause()` | Pauses the current line. Does nothing if nothing is playing, or if the line has under 1.5 seconds left |
| `Resume()` | Resumes after a pause. WoW can't seek in a sound, so the line restarts, unless it was nearly finished and the player's settings show the remaining text as subtitles instead |
| `Skip()` | Skips to the next line in the queue |

`PlayQuest` and `PlayGossip` follow the player's settings: a line may be queued instead of starting at once, or be ignored, for example when a gossip line is on cooldown. Use `IsPlaying()` or the events below to see what happened.

`Stop` takes an optional table:

| Option | Default | Effect |
| --- | --- | --- |
| `clearQueue` | `false` | Also drops every queued line |
| `respectQueueMode` | `false` | Does nothing if the player uses queue mode. Use this when closing a dialog shouldn't cut off the queue |

Without `clearQueue`, queued lines stay queued but don't start on their own; they wait until something else plays, or until `Skip()`. A line that was set aside for a quest is dropped either way.

## Events

```lua
local function onChange(event, state, line)
    print(event, state, line and line.title)
end

ChattyLittleNpc.API.RegisterCallback("PLAYBACK_STATE_CHANGED", onChange)
ChattyLittleNpc.API.UnregisterCallback("PLAYBACK_STATE_CHANGED", onChange)
```

`RegisterCallback` returns `false` for an unknown event. Callbacks receive the event name, then:

| Event | Arguments | When |
| --- | --- | --- |
| `PLAYBACK_STATE_CHANGED` | `state`, `line` or `nil` | Playback may have changed. Can repeat with the same state, so don't assume each call is a change |
| `QUEUE_CHANGED` | `reason` (`"cleared"` or `nil`) | The queue changed |
| `HISTORY_ADDED` | `line` | A line finished, or was skipped or dropped |
| `CONVERSATION_ENDED` | `lastText` or `nil` | Playback stopped. After `Stop()` the queue may still hold lines, and this can fire when nothing was playing |

`state` is one of `"idle"`, `"queued"`, `"playing"`, `"paused_user"`, `"paused_native"`, `"text_continuing"`, `"suspended"`, `"completed"` or `"dropped"`.

## Line records

`GetCurrent()` and the events give you a copy, so changing it has no effect on playback. Any field can be `nil`.

| Field | Meaning |
| --- | --- |
| `title` | Quest title, or the line's text for gossip. For lines played from the voiceover library, the NPC or entry name |
| `entryType` | `"quest"`, `"Gossip"`, `"GameObject"` or `"Item"` |
| `questId`, `phase` | Set for quest lines |
| `npcId`, `displayID`, `gender`, `creatureType` | The speaker |
| `state` | See above |
| `startTime` | `GetTime()` when the line started. Not set in `HISTORY_ADDED` |
| `duration` | Estimated length in seconds. Not set in `HISTORY_ADDED` |

## Moving from internal calls

| Internal call | API call |
| --- | --- |
| `VoiceoverPlayer:PlayQuestSound(id, phase, npc)` | `PlayQuest(id, phase, npc)` |
| `VoiceoverPlayer:PlayNonQuestSound(id, type, text, gender)` | `PlayGossip(id, type, text, gender)` |
| `VoiceoverPlayer:ForceStopCurrentSound(true)` | `Stop({ clearQueue = true, respectQueueMode = true })` |
| `VoiceoverPlayer.currentlyPlaying:isPlaying()` | `IsPlaying()` |
| Searching `VoiceoverPacks[...].Voiceovers` | `HasQuestVoiceover(id, phase)` |
| `Utils:GetHashes` + `Utils:GetPathToNonQuestFile` | `HasGossipVoiceover(id, type, text, gender)` |
| `db.profile.playVoiceoverAfterDelay` | `GetAutoPlayDelay()` |

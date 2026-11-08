-- API.lua - Stable public interface for other addons.
-- Documented in docs/API.md. Everything else on ChattyLittleNpc is internal and
-- may change between releases. Call these with a dot, not a colon:
--   ChattyLittleNpc.API.PlayQuest(questId, "Desc")

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ChattyLittleNpcAPI
local API = {}
CLN.API = API

--- Raised when a released function changes incompatibly; additions don't raise it.
API.version = 1

local function ready()
    return CLN.db ~= nil and CLN.db.profile ~= nil and CLN.VoiceoverPlayer ~= nil
end

--- A separate copy of a playback or history record, holding only the public fields.
local function publicRecord(record)
    if not (record and (record.title or record.questId)) then return nil end
    return {
        title = record.title,
        entryType = record.entryType,
        questId = record.questId,
        phase = record.phase,
        npcId = record.npcId,
        displayID = record.displayID,
        gender = record.gender,
        creatureType = record.creatureType,
        state = record.state,
        startTime = record.startTime,
        duration = record._estimatedDuration,
    }
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- True once the addon has finished loading and the other functions will work.
---@return boolean
function API.IsReady()
    return ready()
end

--- True while a voiceover is audibly playing. False while paused.
---@return boolean
function API.IsPlaying()
    if not ready() then return false end
    local cp = CLN.VoiceoverPlayer.currentlyPlaying
    return (cp and cp:isPlaying()) and true or false
end

--- True while the player has paused playback.
---@return boolean
function API.IsPaused()
    return ready() and CLN.VoiceoverPlayer:IsPaused() or false
end

--- A copy of the current line, or nil if there is none.
---@return table|nil
function API.GetCurrent()
    if not ready() then return nil end
    return publicRecord(CLN.VoiceoverPlayer.currentlyPlaying)
end

--- Seconds the player chose to wait before a voiceover starts automatically.
---@return number
function API.GetAutoPlayDelay()
    return ready() and CLN.db.profile.playVoiceoverAfterDelay or 0
end

-- ---------------------------------------------------------------------------
-- Finding voiceovers
-- ---------------------------------------------------------------------------

--- Does the player have a voiceover for this quest text?
---@param questId number
---@param phase string "Desc", "Prog" or "Comp"
---@return boolean
function API.HasQuestVoiceover(questId, phase)
    if not (ready() and questId and phase) then return false end
    local normalized = CLN.Utils:NormalizeQuestPhase(phase)
    if not CLN.Utils:IsCanonicalQuestPhase(normalized) then return false end
    return CLN:HasQuestVoiceover(questId, normalized)
end

--- Does the player have a voiceover for this gossip, item or object text?
---@param npcId number
---@param soundType string "Gossip", "GameObject" or "Item"
---@param text string The exact text shown in game
---@param gender string|nil "Male", "Female", "Neutral" or nil
---@return boolean
function API.HasGossipVoiceover(npcId, soundType, text, gender)
    if not (ready() and npcId and soundType and text) then return false end
    -- Same fallback PlayGossip gets, so this agrees with what would play
    if not gender or gender == "" then
        local cached = CLN.NpcMetadataCache:Lookup(npcId)
        gender = cached and cached.gender or ""
    end
    local hashes = CLN.Utils:GetHashes(npcId, text)
    local path = CLN.Utils:GetPathToNonQuestFile(npcId, soundType, hashes, gender)
    return (path and path ~= "") and true or false
end

-- ---------------------------------------------------------------------------
-- Controlling playback
-- ---------------------------------------------------------------------------

--- Play a quest voiceover, following the player's queue settings.
---@param questId number
---@param phase string "Desc", "Prog" or "Comp"
---@param npcId number|nil The NPC giving the quest, for the portrait
function API.PlayQuest(questId, phase, npcId)
    if not ready() then return end
    -- The force-stop guard rejects stray re-triggers; this is a deliberate
    -- request, and callers commonly Stop() and play in the same breath
    CLN.VoiceoverPlayer._lastForceStopTime = nil
    CLN.VoiceoverPlayer:PlayQuestSound(questId, phase, npcId)
end

--- Play a gossip, item or object voiceover, following the player's queue settings.
---@param npcId number
---@param soundType string "Gossip", "GameObject" or "Item"
---@param text string The exact text shown in game
---@param gender string|nil "Male", "Female", "Neutral" or nil
function API.PlayGossip(npcId, soundType, text, gender)
    if not ready() then return end
    CLN.VoiceoverPlayer:PlayNonQuestSound(npcId, soundType, text, gender)
end

--- Stop the current line.
---@param options table|nil { clearQueue = boolean, respectQueueMode = boolean }.
--- With respectQueueMode, nothing happens when the player uses queue mode.
function API.Stop(options)
    if not ready() then return end
    options = options or {}
    CLN.VoiceoverPlayer:ForceStopCurrentSound(options.clearQueue and true or false, not options.respectQueueMode)
end

--- Pause the current line.
function API.Pause()
    if ready() then CLN.VoiceoverPlayer:PausePlayback() end
end

--- Resume after a pause. WoW can't seek, so the line restarts from the beginning.
function API.Resume()
    if ready() then CLN.VoiceoverPlayer:ResumePlayback() end
end

--- Skip the current line and move to the next one in the queue.
function API.Skip()
    if ready() then CLN.VoiceoverPlayer:SkipCurrentSound() end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Public event name -> how to turn the internal payload into the public one.
local function passThrough(...) return ... end
local EVENTS = {
    PLAYBACK_STATE_CHANGED = function(state, record) return state, publicRecord(record) end,
    QUEUE_CHANGED = passThrough,
    HISTORY_ADDED = function(entry) return publicRecord(entry) end,
    CONVERSATION_ENDED = passThrough,
}

local subscriptions = {} -- event -> callback -> wrapper

--- Call a function when something happens. Registering the same function for
--- the same event twice has no extra effect.
---@param event string See docs/API.md
---@param callback fun(event: string, ...)
---@return boolean registered False for an unknown event or a missing callback
function API.RegisterCallback(event, callback)
    local convert = EVENTS[event]
    if not (convert and type(callback) == "function") then return false end
    subscriptions[event] = subscriptions[event] or {}
    if subscriptions[event][callback] then return true end
    local wrapper = function(_, ...)
        callback(event, convert(...))
    end
    subscriptions[event][callback] = wrapper
    CLN:RegisterMessage(CLN.Messages[event], wrapper)
    return true
end

--- Stop calling a function registered with RegisterCallback.
---@param event string
---@param callback function
function API.UnregisterCallback(event, callback)
    local wrapper = subscriptions[event] and subscriptions[event][callback]
    if not wrapper then return end
    subscriptions[event][callback] = nil
    CLN:UnregisterMessage(CLN.Messages[event], wrapper)
end

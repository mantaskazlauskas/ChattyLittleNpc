---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Director: decides which emote/animation to play during voiceover
ReplayFrame.Director = ReplayFrame.Director or {}
local Director = ReplayFrame.Director

-- ==========================
-- constants (timings/ids/ui)
-- ==========================

-- Talk animation ids
local TALK_ANIM_NORMAL = 60 -- normal talking
-- (kept for reference if needed: exclamation=64, question=65)

-- Greeting heuristics
local FIRST_SENTENCE_MIN_DOT_POS = 10
local FIRST_SENTENCE_MAX_CHARS = 50
local GREETING_HEURISTIC_MAX_LEN = 80

-- Wave logic
local WAVE_COOLDOWN = 30 -- seconds, per-NPC
-- (Removed unused constants: ALLOW_WAVE_LATE_START_SECONDS, WAVE_HELLO_DURATION,
--  WAVE_ZOOM_AMOUNT, WAVE_OUT_DURATION, WAVE_ZOOM_BACK_DURATION)

-- Interaction gate
local RECENT_INTERACT_TTL = 120 -- seconds

-- Removed farewell/bye cooldown and detection


-- Pattern-based greeting detection (lowercased, Lua patterns allowed)
local GREETING_PATTERNS = {
    "greetings", "greetings, traveler", "well met", "hail",
    "hello", "^hello", "good day", "good day to you",
    "light be with you", "king's honor", "elune", "ishnu",
    "strength and honor", "blood and thunder", "lok.?tar", "victory or death",
    "peace[, ]?friend", "how may i aid you", "winds guide you",
    "hello, mon", "greetings, mon", "what be on ya mind", "who you be",
    "speak quickly", "what do you require", "glory to the sin.?dorei",
    "time is money, friend", "greetings, wanderer", "which river led you",
    "zandalar will endure", "have you come to trade", "got anything for me",
}

function Director:LooksLikeGreeting(msg)
    if not msg or msg == "" then 
        if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("LooksLikeGreeting - empty message") end
        return false 
    end
    
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("LooksLikeGreeting analyzing:", string.sub(msg, 1, 50) .. (string.len(msg) > 50 and "..." or "")) end
    
    msg = tostring(msg):lower()
    
    -- direct pattern matching
    for _, pat in ipairs(GREETING_PATTERNS) do
        if string.find(msg, pat) then
            if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("Found greeting pattern:", pat) end
            return true
        end
    end
    
    -- heuristic: analyze first sentence using talk animation logic
    local r = ReplayFrame
    if r and r.ChooseTalkAnimIdForText then
        -- first sentence or capped length
        local firstPart = msg
        local dotPos = string.find(msg, "%.")
        if dotPos and dotPos > FIRST_SENTENCE_MIN_DOT_POS then
            firstPart = string.sub(msg, 1, dotPos)
        elseif #msg > FIRST_SENTENCE_MAX_CHARS then
            firstPart = string.sub(msg, 1, FIRST_SENTENCE_MAX_CHARS)
        end
        
        local animId = r:ChooseTalkAnimIdForText(firstPart)
        
        -- if it's normal talk, likely a greeting; add soft keyword+length check
        if animId == TALK_ANIM_NORMAL then
            local hasCommonGreetingWords = string.find(firstPart, "welcome") or 
                                         string.find(firstPart, "come") or
                                         string.find(firstPart, "you") or
                                         string.find(firstPart, "what") or
                                         string.find(firstPart, "how")
            if CLN.Utils and CLN.Utils.LogAnimDebug then 
                CLN.Utils:LogAnimDebug("Heuristic analysis - animId: " .. tostring(animId) .. ", hasGreetingWords: " .. tostring(hasCommonGreetingWords) .. ", length: " .. tostring(#firstPart))
            end
            if hasCommonGreetingWords and #firstPart < GREETING_HEURISTIC_MAX_LEN then
                if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("Heuristic detected greeting") end
                return true
            end
        end
    end
    
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("No greeting detected") end
    return false
end

local lastWaveBy = {}

local function getWaveKey()
    -- prefer GUID if available, otherwise npcId from playback
    if UnitGUID then
        local guid = UnitGUID("npc") or UnitGUID("target")
        if guid and guid ~= "" then return guid end
    end
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    if cur and cur.npcId then return tostring(cur.npcId) end
    return nil
end

function Director:CanWave()
    local key = getWaveKey() or "unknown"
    local now = GetTime and GetTime() or 0
    local last = lastWaveBy[key]
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("CanWave check - key:", key, "now:", now, "lastWave:", last or "never") end
    if (not last) or ((now - last) > WAVE_COOLDOWN) then
        if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("Wave allowed (cooldown free)") end
        return true
    end
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("Wave blocked by cooldown, time remaining:", WAVE_COOLDOWN - (now - last)) end
    return false
end

-- Mark that we actually performed a wave for the current NPC key (start cooldown)
function Director:MarkWaved()
    local key = getWaveKey() or "unknown"
    local now = GetTime and GetTime() or 0
    lastWaveBy[key] = now
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("MarkWaved - starting cooldown for key:", key, "at:", now) end
end

local lastInteractBy = {}

local function getInteractKey()
    return getWaveKey() or "unknown"
end

function Director:HasInteractedRecently()
    local key = getInteractKey()
    local now = GetTime and GetTime() or 0
    local last = lastInteractBy[key]
    local hasInteracted = last and ((now - last) < RECENT_INTERACT_TTL) or false
    if ReplayFrame and ReplayFrame.Debug then ReplayFrame:Debug("HasInteractedRecently - key:", key, "lastInteract:", last or "never", "hasInteracted:", hasInteracted) end
    return hasInteracted
end

function Director:MarkInteracted()
    local key = getInteractKey()
    local now = GetTime and GetTime() or 0
    lastInteractBy[key] = now
end

-- Farewell detection removed

-- Start decision-making for the current playback state
-- Start/Stop/Update are managed by the new ReplayFrame FSM; Director now provides only heuristics and gates.

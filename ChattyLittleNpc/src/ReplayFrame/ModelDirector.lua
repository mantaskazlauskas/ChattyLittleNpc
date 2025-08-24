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
local ALLOW_WAVE_LATE_START_SECONDS = 2.0
local WAVE_HELLO_DURATION = 1.5
local WAVE_ZOOM_AMOUNT = 0.3
local WAVE_OUT_DURATION = 0.2
local WAVE_ZOOM_BACK_DURATION = 0.5

-- Interaction gate
local RECENT_INTERACT_TTL = 120 -- seconds

-- Farewell logic
local BYE_COOLDOWN = 45 -- seconds, per-NPC
local BYE_DURATION = 1.2
local HELLO_DURATION = 1.5
local STOP_HIDE_DELAY = 1.6

-- Playback start grace to avoid idle flash
local RECENTLY_STARTED_WINDOW = 0.6

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
    if not msg or msg == "" then return false end
    msg = tostring(msg):lower()
    
    -- direct pattern matching
    for _, pat in ipairs(GREETING_PATTERNS) do
        if string.find(msg, pat) then
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
            if hasCommonGreetingWords and #firstPart < GREETING_HEURISTIC_MAX_LEN then
                return true
            end
        end
    end
    
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
    if (not last) or ((now - last) > WAVE_COOLDOWN) then
        lastWaveBy[key] = now
        return true
    end
    return false
end

local lastInteractBy = {}

local function getInteractKey()
    return getWaveKey() or "unknown"
end

function Director:HasInteractedRecently()
    local key = getInteractKey()
    local now = GetTime and GetTime() or 0
    local last = lastInteractBy[key]
    return last and ((now - last) < RECENT_INTERACT_TTL) or false
end

function Director:MarkInteracted()
    local key = getInteractKey()
    local now = GetTime and GetTime() or 0
    lastInteractBy[key] = now
end

local function getSinceStart(cur)
    local now = GetTime and GetTime() or 0
    local startedAt = (cur and cur.startTime) or now
    return now - startedAt
end

-- Farewell detection
local FAREWELL_PATTERNS = {
    "farewell", "^farewell", "goodbye", "^goodbye", "%f[%a]bye%f[%A]", "^bye$", "see you", "until we meet again",
    "safe travels", "walk with the earth mother", "be seeing you", "light guide you", "go in peace",
    "remember the sunwell", "winds at your back", "watch your back", "shadows guide you",
}

function Director:LooksLikeFarewell(msg)
    if not msg or msg == "" then return false end
    msg = tostring(msg):lower()
    for _, pat in ipairs(FAREWELL_PATTERNS) do
        if string.find(msg, pat) then
            return true
        end
    end
    return false
end

local lastByeBy = {}

local function getByeKey()
    return getWaveKey() or "unknown"
end

function Director:CanPlayBye()
    local key = getByeKey()
    local now = GetTime and GetTime() or 0
    local last = lastByeBy[key]
    if (not last) or ((now - last) > BYE_COOLDOWN) then
        lastByeBy[key] = now
        return true
    end
    return false
end

-- Start decision-making for the current playback state
function Director:Start()
    local r = ReplayFrame
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    if not (cur and cur.soundHandle and cur.isPlaying and cur:isPlaying()) then return end
    if self._dirHandle == cur.soundHandle then return end

    self._dirHandle = cur.soundHandle

    -- stop any prior loops/emotes and clear lingering flags/animations
    if r.StopEmoteLoop then r:StopEmoteLoop() end
    if r.CancelEmote then r:CancelEmote() end
    r._pendingTalkAfterZoom = false
    if r.AnimStop then r:AnimStop("zoom"); r:AnimStop("pan") end

    -- save last message for potential farewell
    self._lastMsg = cur and cur.title

    -- mark interaction (for recent-gate decision)
    local interactedRecently = self:HasInteractedRecently()
    self:MarkInteracted()

    -- greeting -> wave; skip for quest or late-start; apply cooldown + recent-interaction gate
    local shouldWave = self:LooksLikeGreeting(cur and cur.title)
    local allowWave = (not interactedRecently) and (not cur.questId) and (getSinceStart(cur) <= ALLOW_WAVE_LATE_START_SECONDS) and self:CanWave()

    if shouldWave and allowWave then
        -- hello emote (wave choreography)
        if r.PlayEmote then r:PlayEmote("hello", { duration = WAVE_HELLO_DURATION, waveZoom = WAVE_ZOOM_AMOUNT, waveOutDur = WAVE_OUT_DURATION, zoomBackDur = WAVE_ZOOM_BACK_DURATION }) end
    else
        -- no wave: talk + loop immediately
        if r.CancelEmote then r:CancelEmote() end
        
        -- set talk animation on the model frame
        local m = r.NpcModelFrame
        if m and m.SetAnimation then
            local talkId = TALK_ANIM_NORMAL
            if r.ChooseTalkAnimIdForText and cur and cur.title then
                talkId = r:ChooseTalkAnimIdForText(cur.title)
            end
            if r._animState ~= "talk" or r._lastTalkId ~= talkId then
                pcall(m.SetAnimation, m, talkId)
            end
            if m.SetSheathed then pcall(m.SetSheathed, m, true) end
            r._animState = "talk"
            r._lastTalkId = talkId
        end
        
        if r.PlayEmote then r:PlayEmote("talk") end
        if r.StartEmoteLoop then r:StartEmoteLoop() end
    end
end

function Director:Stop()
    self._dirHandle = nil
    local r = ReplayFrame
    if r.StopEmoteLoop then r:StopEmoteLoop() end
    if r.CancelEmote then r:CancelEmote() end

    -- if last line looked like a farewell, play a brief emote even after audio ends
    local lastMsg = self._lastMsg
    self._lastMsg = nil
    if lastMsg and self:LooksLikeFarewell(lastMsg) and self:CanPlayBye() then
        -- ensure model is visible
        if r.ModelContainer then r.ModelContainer:Show() end
        if r.NpcModelFrame then r.NpcModelFrame:Show() end
        -- pick bye vs hello depending on wording
        local emote = "bye"
        if lastMsg:lower():find("hello") or lastMsg:lower():find("greetings") or lastMsg:lower():find("well met") then
            emote = "hello"
        end
        if r.PlayEmote then r:PlayEmote(emote, { duration = (emote == "bye") and BYE_DURATION or HELLO_DURATION }) end
        -- hide model shortly after if nothing started playing again
        if C_Timer and C_Timer.After then
            C_Timer.After(STOP_HIDE_DELAY, function()
                -- only hide if nothing started playing again
                local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
                if not (cur and cur.isPlaying and cur:isPlaying()) then
                    if r.ModelContainer then r.ModelContainer:Hide() end
                    if r.NpcModelFrame then r.NpcModelFrame:Hide() end
                end
            end)
        end
    end
end

-- Called by UpdateConversationAnimation
function Director:OnPlaybackUpdate()
    local r = ReplayFrame
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    -- grace window: right after starting a sound, treat as active
    local recentlyStarted = false
    if cur and cur.startTime and GetTime then
        local dt = GetTime() - (cur.startTime or 0)
        recentlyStarted = dt >= 0 and dt < RECENTLY_STARTED_WINDOW
    end
    if cur and ( (cur.isPlaying and cur:isPlaying()) or recentlyStarted ) then
        self:Start()
    else
        self:Stop()
        if r.SetIdleLoop then r:SetIdleLoop() end
    end
end

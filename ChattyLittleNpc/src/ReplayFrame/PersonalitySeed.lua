---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

ReplayFrame.PersonalitySeed = ReplayFrame.PersonalitySeed or {}
local PersonalitySeed = ReplayFrame.PersonalitySeed

local _cache = {}

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function next01(state)
    state = (state * 1664525 + 1013904223) % 4294967296
    return state, (state / 4294967295)
end

local function computeTraits(npcId)
    local seed = math.floor(tonumber(npcId) or 0)
    if seed < 0 then seed = -seed end
    seed = (seed * 1103515245 + 12345 + (seed % 7919) * 97) % 4294967296

    local s = seed
    local formal, playful, energy, nervousness
    s, formal = next01(s)
    s, playful = next01(s)
    s, energy = next01(s)
    s, nervousness = next01(s)

    formal = clamp01(formal)
    playful = clamp01(playful)
    energy = clamp01(energy)
    nervousness = clamp01(nervousness)

    local traits = {
        formal = formal,
        playful = playful,
        energy = energy,
        nervousness = nervousness,
    }

    traits.driftAmplitudeScale = clamp01(0.8 + (energy - 0.5) * 0.6 - (formal - 0.5) * 0.25) + 0.2
    traits.fidgetChanceScale = clamp01(0.6 + playful * 0.9)
    traits.idleVarianceScale = clamp01(0.6 + nervousness * 0.9)
    traits.talkEnergyScale = clamp01(0.5 + energy)
    return traits
end

function PersonalitySeed:GetTraits(npcId)
    local id = tonumber(npcId)
    if not id then
        return { formal = 0.5, playful = 0.5, energy = 0.5, nervousness = 0.5, driftAmplitudeScale = 1, fidgetChanceScale = 1, idleVarianceScale = 1, talkEnergyScale = 1 }
    end
    if not _cache[id] then
        _cache[id] = computeTraits(id)
    end
    return _cache[id]
end

function PersonalitySeed:ResetCache()
    _cache = {}
end

function ReplayFrame:GetPersonalityTraits(npcId)
    local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local resolvedNpcId = npcId or (cur and cur.npcId) or self._lastUnitNpcId
    return PersonalitySeed:GetTraits(resolvedNpcId)
end

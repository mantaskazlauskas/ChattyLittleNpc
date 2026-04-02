---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ---------------------------------------------------------------------------
-- AnimationInfer — detect an NPC's current world animation
--
-- The WoW API has no direct "GetUnitAnimation()" for world units.  However
-- the legacy PlayerModel widget mirrors a unit's pose when SetUnit() is
-- called and immediately exposes the animation via GetAnimation().
--
-- We create a tiny, hidden, off-screen PlayerModel purely as a detection
-- probe.  When the "npc" unit token is available we load it into the probe,
-- read the animation, then clear the model.  This is the only reliable way
-- to capture special idle poses (sitting, kneeling, working) that NPCs may
-- have in the world and reflect them in the ModelScene portrait.
--
-- A secondary heuristic path uses unit-state APIs (GetUnitSpeed, UnitIsDead,
-- etc.) as a best-effort fallback when the probe cannot be used.
-- ---------------------------------------------------------------------------

local AnimationInfer = {}
ReplayFrame.AnimationInfer = AnimationInfer

-- Animations that are transient / emote-like — unsuitable as a resting pose
local TRANSIENT_ANIMS = {
    [25]  = true,  -- Point
    [60]  = true,  -- Talk
    [64]  = true,  -- TalkExclamation
    [65]  = true,  -- TalkQuestion
    [66]  = true,  -- Bow
    [67]  = true,  -- Wave
    [68]  = true,  -- Cheer
    [69]  = true,  -- Dance
    [70]  = true,  -- Kneel
    [113] = true,  -- Salute
    [185] = true,  -- Yes (nod)
    [186] = true,  -- No (headshake)
}

local probeFrame

-- Lazy-create a 1x1 hidden off-screen PlayerModel used solely for animation
-- detection.  It is never shown to the player.
local function getProbe()
    if probeFrame then return probeFrame end
    local ok, frame = pcall(CreateFrame, "PlayerModel", "CLN_AnimProbe", UIParent)
    if not (ok and frame) then return nil end
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100) -- off-screen
    frame:SetAlpha(0)
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    frame:Hide()
    probeFrame = frame
    return frame
end

--- Probe the NPC's animation using the hidden PlayerModel.
--- PlayerModel:SetUnit() mirrors the unit's world pose synchronously
--- so GetAnimation() returns the correct value immediately.
---@param unit string?  Unit token (default "npc")
---@return number|nil animId  Detected animation, or nil on failure
function AnimationInfer.ProbeUnitAnimation(unit)
    unit = unit or "npc"
    if not (UnitExists and UnitExists(unit)) then return nil end

    local probe = getProbe()
    if not probe then return nil end

    -- PlayerModel needs to be shown momentarily for SetUnit to work
    probe:Show()
    local ok = pcall(probe.SetUnit, probe, unit)
    if not ok then
        probe:Hide()
        return nil
    end

    local animId
    if probe.GetAnimation then
        local okA, a = pcall(probe.GetAnimation, probe)
        if okA and type(a) == "number" and not TRANSIENT_ANIMS[a] then
            animId = a
        end
    end

    pcall(probe.ClearModel, probe)
    probe:Hide()
    return animId
end

--- Infer the animation from observable unit state (fallback heuristic).
--- Uses speed, alive/dead status, and cast state to guess the animation.
---@param unit string?  Unit token (default "npc")
---@return number animId  Best-guess animation ID (0 = idle if nothing matches)
function AnimationInfer.InferFromState(unit)
    unit = unit or "npc"
    if not (UnitExists and UnitExists(unit)) then return 0 end

    -- Dead → death animation
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return 6 end

    -- Moving → walk or run
    if GetUnitSpeed then
        local speed = GetUnitSpeed(unit) or 0
        if speed > 7  then return 5 end -- Run  (> base 100% speed)
        if speed > 0  then return 4 end -- Walk
    end

    -- Casting → generic spell cast
    if UnitCastingInfo  and UnitCastingInfo(unit)  then return 26 end
    if UnitChannelInfo and UnitChannelInfo(unit) then return 26 end

    return 0 -- Idle / Stand
end

--- Combined inference: probe first, fall back to state heuristics.
---@param unit string?  Unit token (default "npc")
---@return number animId  Resolved animation ID (never nil)
function AnimationInfer.Infer(unit)
    unit = unit or "npc"
    local probed = AnimationInfer.ProbeUnitAnimation(unit)
    if probed and probed ~= 0 then return probed end
    return AnimationInfer.InferFromState(unit)
end

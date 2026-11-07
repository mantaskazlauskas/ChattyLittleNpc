-- Migrations.lua - Saved-settings migrations, kept in one ordered list.
--
-- Each profile stores the schemaVersion it was last migrated to. Run() applies
-- every step whose version is higher, in order, then stamps the latest version.
-- It runs for the active profile on load and again whenever the profile is
-- switched, copied or reset, so inactive profiles catch up when activated.
--
-- Rules for steps:
--   * Append new steps at the end with the next version number; never renumber.
--   * Every step must be idempotent: it can see a profile that was already
--     partly migrated (older builds ran some of these on every login), or a
--     brand-new profile that never had the legacy keys.
--   * Steps get the raw profile table (defaults already merged in), not the
--     db.profile proxy, so `pairs` works and a cleared key is really gone.
--
-- schemaVersion is deliberately NOT in Main.lua's defaults: defaults are
-- merged before migrations run, so a default would mark old profiles as
-- already migrated.

local CLN = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc = CLN

local Migrations = {}
CLN.Migrations = Migrations

local function logInfo(msg)
    if CLN.Logger and CLN.Utils and CLN.Utils.LogCategories then
        CLN.Logger:info(msg, false, CLN.Utils.LogCategories.misc)
    end
end

-- ============================================================================
-- Steps
-- ============================================================================

--- Docking next to the objectives tracker became the default placement.
--- Keep the window where it is for anyone who already moved it off the old
--- default spot (CENTER +500,0).
function Migrations.DockToObjectivesTracker(p)
    local pos = p.framePos
    local atOldDefault = type(pos) == "table" and pos.point == "CENTER" and pos.relativePoint == "CENTER"
        and pos.xOfs == 500 and pos.yOfs == 0
    p.frameAnchor = atOldDefault and "objectives" or "free"
end

--- Gossip cooldown moved from a minutes slider (0-120) to a seconds dropdown.
function Migrations.GossipCooldownToSeconds(p)
    local minutes = p.gossipCooldownMinutes
    if minutes == nil then return end
    -- The old default (5) was written into every profile, so only carry the value
    -- over when the cooldown was actually enabled; otherwise use the new default.
    if p.gossipCooldownEnabled then
        if minutes == 0 then
            p.gossipCooldownSeconds = 0
        elseif minutes <= 2 then
            p.gossipCooldownSeconds = 60
        else
            p.gossipCooldownSeconds = 300
        end
    else
        p.gossipCooldownSeconds = nil   -- falls back to the default
    end
    p.gossipCooldownMinutes = nil
end

--- Older boolean/flag settings that were replaced by mode settings.
function Migrations.LegacyModeSettings(p)
    -- pauseOnNativeVO (boolean) → nativeVOMode
    if p.pauseOnNativeVO ~= nil then
        if p.pauseOnNativeVO == true and (not p.nativeVOMode or p.nativeVOMode == "off") then
            p.nativeVOMode = "whitelist"
        end
        p.pauseOnNativeVO = nil
    end

    -- nativeVOMode "all" was removed
    if p.nativeVOMode == "all" then
        p.nativeVOMode = "whitelist"
    end

    -- enableQuestPlaybackQueueing + stopVoiceoverAfterDialogWindowClose → questPlaybackMode
    if p.enableQuestPlaybackQueueing ~= nil or p.stopVoiceoverAfterDialogWindowClose ~= nil then
        if p.stopVoiceoverAfterDialogWindowClose then
            p.questPlaybackMode = "stopOnClose"
        elseif p.enableQuestPlaybackQueueing == false then
            p.questPlaybackMode = "manual"
        else
            p.questPlaybackMode = "queue"
        end
        p.enableQuestPlaybackQueueing = nil
        p.stopVoiceoverAfterDialogWindowClose = nil
    end
end

-- Copy a table up to three levels deep (enough for the v1 layout buckets).
local function copyLayouts(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            local copy = {}
            for k2, v2 in pairs(v) do
                if type(v2) == "table" then
                    local inner = {}
                    for k3, v3 in pairs(v2) do inner[k3] = v3 end
                    copy[k2] = inner
                else
                    copy[k2] = v2
                end
            end
            out[k] = copy
        end
    end
    return out
end

-- Build one v2 layout bucket from a flat v1 bucket.
local function convertLayout(p, v1)
    local convState = {}
    if v1.frameScale then convState.scale = v1.frameScale end
    if v1.queueTextScale then convState.textScale = v1.queueTextScale end
    if v1.frameSize then
        convState.size = {
            width  = v1.frameSize.width,
            height = v1.frameSize.height,
        }
    end
    -- v1 stored position as { point, relativePoint, x, y } in layout buckets
    local pos = v1.framePos or v1.displayFramePos
    if pos then
        convState.pos = {
            point         = pos.point,
            relativePoint = pos.relativePoint or pos.relPoint,
            x             = pos.x or pos.xOfs or 0,
            y             = pos.y or pos.yOfs or 0,
        }
    end

    -- Model state: keep an undocked position from the global profile
    local globalModelPos = p.modelFramePos
    local isDocked = type(globalModelPos) ~= "table"
    local modelState = { docked = isDocked }
    if v1.npcModelFrameHeight then
        local w = (v1.frameSize and v1.frameSize.width) or 475
        modelState.size = { width = w, height = v1.npcModelFrameHeight }
    end
    if not isDocked then
        modelState.pos = {
            point         = globalModelPos.point,
            relativePoint = globalModelPos.relativePoint,
            x             = globalModelPos.xOfs or 0,
            y             = globalModelPos.yOfs or 0,
        }
        if globalModelPos.width and modelState.size then
            modelState.size.width = globalModelPos.width
        end
    end

    return { conversation = convState, model = modelState }
end

--- Per-Edit-Mode-layout settings: pre-v1 layoutPositions/layoutSizes and the
--- flat v1 editModeLayouts/editModeExclude become the namespaced p.editMode
--- store (schemaVersion 2) used by EditMode/Persistence.lua.
function Migrations.EditModeLayoutsV2(p)
    -- Pre-v1: separate position/size maps → flat v1 buckets
    if p.layoutPositions or p.layoutSizes then
        if type(p.editModeLayouts) ~= "table" then p.editModeLayouts = {} end
        if type(p.layoutPositions) == "table" then
            for name, pos in pairs(p.layoutPositions) do
                p.editModeLayouts[name] = p.editModeLayouts[name] or {}
                p.editModeLayouts[name].framePos = pos
            end
        end
        if type(p.layoutSizes) == "table" then
            for name, size in pairs(p.layoutSizes) do
                p.editModeLayouts[name] = p.editModeLayouts[name] or {}
                p.editModeLayouts[name].frameSize = size
            end
        end
    end

    local alreadyV2 = type(p.editMode) == "table" and (p.editMode.schemaVersion or 0) >= 2
    local hasLegacy = type(p.editModeLayouts) == "table" and next(p.editModeLayouts) ~= nil
        or type(p.editModeExclude) == "table"

    if not alreadyV2 and hasLegacy then
        local migrated = { schemaVersion = 2, layouts = {}, exclude = {} }
        local count = 0
        for name, v1 in pairs(p.editModeLayouts or {}) do
            if type(v1) == "table" then
                migrated.layouts[name] = convertLayout(p, v1)
                count = count + 1
            end
        end

        local oldExclude = type(p.editModeExclude) == "table" and p.editModeExclude or {}
        migrated.exclude = {
            conversation = {
                pos       = oldExclude.framePos or false,
                size      = oldExclude.frameSize or false,
                scale     = oldExclude.frameScale or false,
                textScale = oldExclude.queueTextScale or false,
            },
            model = {
                docked = false,
                pos    = oldExclude.framePos or false,
                size   = oldExclude.npcModelFrameHeight or false,
            },
        }

        -- One-time backup of the v1 data, in case the conversion went wrong
        if type(p.editModeLayouts) == "table" then
            p._editModeLegacyBackup = copyLayouts(p.editModeLayouts)
        end
        p.editMode = migrated
        logInfo("Migrated " .. count .. " Edit Mode layout(s) to the v2 format")
    end

    -- The legacy keys are never read again, whether or not there was data to move
    p.layoutPositions = nil
    p.layoutSizes = nil
    p.editModeLayouts = nil
    p.editModeExclude = nil
end

--- Settings that nothing reads any more.
function Migrations.RemoveDeadKeys(p)
    p.alwaysShowReplayFrame = nil
end

-- Ordered list. Versions 1 and 2 match what older builds stamped: profiles at
-- 2 already ran the frame-anchor step. Steps 3-4 used to run on every login,
-- so they also have to cope with profiles that already went through them.
Migrations.steps = {
    { version = 2, name = "dock to objectives tracker", run = Migrations.DockToObjectivesTracker },
    { version = 3, name = "gossip cooldown in seconds",  run = Migrations.GossipCooldownToSeconds },
    { version = 3, name = "legacy mode settings",        run = Migrations.LegacyModeSettings },
    { version = 4, name = "edit mode layouts v2",        run = Migrations.EditModeLayoutsV2 },
    { version = 5, name = "remove dead keys",            run = Migrations.RemoveDeadKeys },
}

Migrations.LATEST = Migrations.steps[#Migrations.steps].version

-- ============================================================================
-- Runner
-- ============================================================================

--- Bring one raw profile table up to the latest schema version.
---@param p table raw profile table (not the db.profile proxy)
---@return boolean changed whether any step ran
function Migrations:Run(p)
    if type(p) ~= "table" then return false end
    local from = tonumber(p.schemaVersion) or 0
    if from >= self.LATEST then return false end
    for _, step in ipairs(self.steps) do
        if step.version > from then
            step.run(p)
        end
    end
    p.schemaVersion = self.LATEST
    return true
end

--- Migrate the database's active profile.
---@param db table Database instance (Core/Database.lua)
function Migrations:RunActive(db)
    local profiles = db and db.sv and db.sv.profiles
    local p = profiles and profiles[db.sv.currentProfile]
    if self:Run(p) then
        logInfo("Settings profile '" .. tostring(db.sv.currentProfile) .. "' migrated to version " .. self.LATEST)
    end
end

--- Migrate the active profile now and after every profile switch, copy or reset.
--- Call right after creating the database so these callbacks run before the
--- UI's own profile-change handlers.
---@param db table Database instance
function Migrations:Attach(db)
    self:RunActive(db)
    local function rerun() Migrations:RunActive(db) end
    db:RegisterCallback("OnProfileChanged", rerun)
    db:RegisterCallback("OnProfileCopied", rerun)
    db:RegisterCallback("OnProfileReset", rerun)
end

return Migrations

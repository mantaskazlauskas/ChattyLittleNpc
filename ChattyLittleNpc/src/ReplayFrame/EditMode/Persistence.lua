---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

-- ============================================================================
-- Per-Layout Persistence (v2 Schema)
-- ============================================================================
-- Manages per-layout settings storage and coordinated persist/apply across all registered window controllers.
-- ============================================================================

local Persistence = {}
EditMode.Persistence = Persistence

local HIDDEN_BASE_LAYOUTS = 2
local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")

local function logDebug(msg)
    CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui)
end
local function logInfo(msg, chat)
    CLN.Logger:info(msg, chat or false, CLN.Utils.LogCategories.ui)
end
local function logWarn(msg)
    CLN.Logger:warn(msg, false, CLN.Utils.LogCategories.ui)
end

-- Whether a state field is opted out of per-layout storage.
-- The dock state ("anchor") is part of the position, so it follows "pos".
local function isExcluded(wExclude, key)
    if key == "anchor" then key = "pos" end
    return wExclude[key]
end

-- ============================================================================
-- Schema Management
-- ============================================================================

--- Ensure the v2 editMode container exists in the profile.
--- Legacy v1 data is converted earlier, by Core/Migrations.lua.
---@return table editMode root container
function Persistence:EnsureStore()
    local p = CLN.db.profile
    if not p.editMode then
        p.editMode = { schemaVersion = 2, layouts = {}, exclude = {} }
    end
    if not p.editMode.layouts then p.editMode.layouts = {} end
    if not p.editMode.exclude then p.editMode.exclude = {} end
    return p.editMode
end

--- Ensure per-window exclude config exists with defaults.
---@return table exclude config
function Persistence:EnsureExcludeConfig()
    local em = self:EnsureStore()
    em.exclude.conversation = em.exclude.conversation or {
        pos       = false,
        size      = false,
        scale     = false,
        textScale = false,
    }
    em.exclude.model = em.exclude.model or {
        docked = false,
        pos    = false,
        size   = false,
    }
    return em.exclude
end

--- Count layouts in the v2 store.
function Persistence:CountLayouts()
    local em = self:EnsureStore()
    local n = 0
    for k, v in pairs(em.layouts) do
        if type(v) == "table" then n = n + 1 end
    end
    return n
end

-- ============================================================================
-- Active Layout Detection
-- ============================================================================

--- Returns the name of the currently active Blizzard Edit Mode layout.
--- Multi-fallback strategy to handle Blizzard API inconsistencies.
---@return string|nil layoutName
function Persistence:GetActiveLayoutName()
    if not hasAPI then return nil end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or not layouts or not layouts.layouts then return nil end

    local list = layouts.layouts
    local idx = tonumber(layouts.activeLayout)

    -- Primary: try adjusted index first (subtract hidden Modern/Classic presets)
    if idx then
        local adj = idx - HIDDEN_BASE_LAYOUTS
        if adj >= 1 and list[adj] and list[adj].layoutName then
            return list[adj].layoutName
        end
        -- Direct index (some clients may already align)
        if list[idx] and list[idx].layoutName then
            return list[idx].layoutName
        end
    end

    -- Fallback 1: scan for explicit active flag
    for i, l in ipairs(list) do
        if l.isActive or l.active or l.isLayoutActive then
            logDebug("Active layout by isActive scan (index=" .. i .. ")")
            return l.layoutName
        end
    end

    -- Fallback 2: probe nearby indices with active flag requirement
    if idx then
        for shift = -3, 3 do
            local cand = list[idx + shift]
            if cand and cand.layoutName and (cand.isActive or cand.active or cand.isLayoutActive) then
                logDebug("Active layout adjusted by " .. shift)
                return cand.layoutName
            end
        end
    end

    -- No fallback to first entry — return nil to prevent writing to wrong bucket
    logWarn("Could not determine active layout; returning nil (no persist/apply)")
    return nil
end

-- ============================================================================
-- Persist / Apply
-- ============================================================================

--- Persist all registered windows' current state to the active layout bucket.
--- Called on Edit Mode exit, drag stop, resize stop, and settings save.
function Persistence:PersistAll()
    local name = self:GetActiveLayoutName()
    if not name then return end

    local em = self:EnsureStore()
    local exclude = self:EnsureExcludeConfig()
    local bucket = em.layouts[name] or {}

    local Registry = EditMode.Registry
    if Registry then
        Registry:ForEach(function(id, controller)
            local wExclude = exclude[id] or {}
            local state = controller:ReadState()
            local wBucket = bucket[id] or {}

            for key, value in pairs(state) do
                if not isExcluded(wExclude, key) then
                    wBucket[key] = value
                end
            end
            -- Docked: drop the last free position so it can't be re-applied
            if state.anchor == "objectives" and not wExclude.pos then
                wBucket.pos = nil
            end

            bucket[id] = wBucket
        end)
    end

    em.layouts[name] = bucket
    logInfo("Saved per-layout settings for '" .. name .. "'")
end

--- Apply stored settings for a named layout to all registered windows.
--- Defers to PLAYER_REGEN_ENABLED if in combat.
---@param name string layout name
function Persistence:ApplyLayout(name)
    if not name then return end

    if InCombatLockdown() then
        self._pendingApply = name
        logDebug("Deferring layout apply (combat lockdown): " .. name)
        return
    end

    local em = self:EnsureStore()
    local data = em.layouts[name]
    if not data then
        logDebug("No saved settings for layout '" .. name .. "'")
        return
    end

    local exclude = self:EnsureExcludeConfig()
    local Registry = EditMode.Registry
    local legacy = false

    if Registry then
        Registry:ForEach(function(id, controller)
            local wData = data[id]
            local wExclude = exclude[id] or {}
            if wData then
                -- Build filtered state (exclude opted-out fields)
                local filtered = {}
                for key, value in pairs(wData) do
                    if not isExcluded(wExclude, key) then
                        filtered[key] = value
                    end
                end
                -- Buckets saved before "anchor" existed can hold a stale position
                -- and size (moves/resizes outside Blizzard Edit Mode weren't
                -- persisted), which reset the window on every login: keep the
                -- current placement and re-save the bucket below.
                if id == "conversation" and wData.anchor == nil then
                    filtered.pos = nil
                    filtered.size = nil
                    legacy = true
                end
                controller:ApplyState(filtered)
            end
        end)
    end

    -- Stamp a legacy bucket with the live state once (outside the apply loop)
    if legacy and name == self:GetActiveLayoutName() then
        self:PersistAll()
    end

    logInfo("Applied settings for layout '" .. name .. "'")
end

--- Apply a pending layout that was deferred due to combat lockdown.
--- Called from PLAYER_REGEN_ENABLED handler.
function Persistence:ApplyPendingLayout()
    if self._pendingApply then
        local name = self._pendingApply
        self._pendingApply = nil
        self:ApplyLayout(name)
    end
end

-- ============================================================================
-- Legacy Compatibility Bridge
-- ============================================================================
-- These functions maintain backward compatibility with code that still
-- calls the old Integration:PersistCurrentToLayout() / ApplyLayout() API.
-- They delegate to the new v2 system.

--- Write back per-layout settings to the OLD v1 flat keys in the profile.
--- This ensures Position.lua and other non-migrated code sees consistent data.
function Persistence:SyncToLegacyProfile()
    local Registry = EditMode.Registry
    if not Registry then return end

    local conv = Registry:Get("conversation")
    if conv then
        local state = conv:ReadState()
        if state.scale then CLN.db.profile.frameScale = state.scale end
        if state.textScale then CLN.db.profile.queueTextScale = state.textScale end
        if state.size then CLN.db.profile.frameSize = state.size end
        if state.pos then
            CLN.db.profile.framePos = {
                point         = state.pos.point,
                relativePoint = state.pos.relativePoint,
                xOfs          = state.pos.x or state.pos.xOfs or 0,
                yOfs          = state.pos.y or state.pos.yOfs or 0,
            }
        end
    end

    local model = Registry:Get("model")
    if model then
        local state = model:ReadState()
        if state.size and state.size.height then
            CLN.db.profile.npcModelFrameHeight = state.size.height
        end
        if state.docked then
            CLN.db.profile.modelFramePos = nil
        elseif state.pos then
            CLN.db.profile.modelFramePos = {
                point         = state.pos.point,
                relativePoint = state.pos.relativePoint,
                xOfs          = state.pos.x or state.pos.xOfs or 0,
                yOfs          = state.pos.y or state.pos.yOfs or 0,
                width         = state.size and state.size.width or nil,
            }
        end
    end
end

return Persistence

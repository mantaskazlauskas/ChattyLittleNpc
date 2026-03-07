---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

-- ============================================================================
-- Per-Layout Persistence (v2 Schema)
-- ============================================================================
-- Manages per-layout settings storage, migration from v1→v2, and
-- coordinated persist/apply across all registered window controllers.
-- ============================================================================

local Persistence = {}
EditMode.Persistence = Persistence

local HIDDEN_BASE_LAYOUTS = 2
local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")

local function logDebug(msg)
    if CLN and CLN.Logger then CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui) end
end
local function logInfo(msg, chat)
    if CLN and CLN.Logger then CLN.Logger:info(msg, chat or false, CLN.Utils.LogCategories.ui) end
end
local function logWarn(msg)
    if CLN and CLN.Logger then CLN.Logger:warn(msg, false, CLN.Utils.LogCategories.ui) end
end

-- ============================================================================
-- Schema Management
-- ============================================================================

--- Ensure the v2 editMode container exists in the profile.
--- Runs migration first if legacy data exists, to prevent EnsureStore
--- from stamping schemaVersion=2 before migration can see v1 data.
---@return table editMode root container
function Persistence:EnsureStore()
    local p = CLN.db.profile
    -- Run migration BEFORE creating the v2 container, so legacy data is preserved
    if not p.editMode or not p.editMode.schemaVersion then
        self:MigrateIfNeeded()
    end
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

-- ============================================================================
-- Migration (v1 → v2)
-- ============================================================================

--- Migrate legacy flat editModeLayouts to the new namespaced v2 schema.
--- Safe to call multiple times (idempotent — checks schemaVersion).
function Persistence:MigrateIfNeeded()
    local p = CLN.db.profile

    -- Already migrated?
    if p.editMode and p.editMode.schemaVersion and p.editMode.schemaVersion >= 2 then
        return
    end

    logInfo("Migrating Edit Mode data from v1 to v2 schema")

    -- Create one-version backup shadow for safety (deep copy to avoid aliasing)
    if p.editModeLayouts then
        p._editModeLegacyBackup = {}
        for k, v in pairs(p.editModeLayouts) do
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
                p._editModeLegacyBackup[k] = copy
            end
        end
    end

    local migrated = { schemaVersion = 2, layouts = {}, exclude = {} }

    -- Migrate per-layout data
    local old = p.editModeLayouts or {}
    for name, v1 in pairs(old) do
        if type(v1) == "table" then
            -- Build conversation state from v1 flat fields
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

            -- Build model state (v1 had no independent model position per layout)
            local modelState = {
                docked = true, -- v1 was always docked
            }
            if v1.npcModelFrameHeight then
                local w = (v1.frameSize and v1.frameSize.width) or 475
                modelState.size = { width = w, height = v1.npcModelFrameHeight }
            end

            migrated.layouts[name] = {
                conversation = convState,
                model        = modelState,
            }
        end
    end

    -- Migrate exclude config
    local oldExclude = p.editModeExclude or {}
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

    p.editMode = migrated
    logInfo("Migration complete — " .. self:CountLayouts() .. " layout(s) migrated")
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

    -- Primary: direct index lookup
    if idx then
        if list[idx] and list[idx].layoutName then
            return list[idx].layoutName
        end
        -- Adjust for hidden Modern/Classic presets
        local adj = idx - HIDDEN_BASE_LAYOUTS
        if adj >= 1 and list[adj] and list[adj].layoutName then
            logDebug(string.format("Active layout index %d adjusted -> %d", idx, adj))
            return list[adj].layoutName
        end
    end

    -- Fallback 1: scan for explicit active flag
    for i, l in ipairs(list) do
        if l.isActive or l.active or l.isLayoutActive then
            logDebug("Active layout by isActive scan (index=" .. i .. ")")
            return l.layoutName
        end
    end

    -- Fallback 2: probe nearby indices
    if idx then
        for shift = -3, 3 do
            local cand = list[idx + shift]
            if cand and cand.layoutName and (cand.isActive or cand.active or cand.isLayoutActive) then
                logDebug("Active layout adjusted by " .. shift)
                return cand.layoutName
            end
        end
    end

    -- Fallback 3: first entry
    if list[1] and list[1].layoutName then
        logWarn("Could not determine active layout; defaulting to first entry")
        return list[1].layoutName
    end

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
                if not wExclude[key] then
                    wBucket[key] = value
                end
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

    if Registry then
        Registry:ForEach(function(id, controller)
            local wData = data[id]
            local wExclude = exclude[id] or {}
            if wData then
                -- Build filtered state (exclude opted-out fields)
                local filtered = {}
                for key, value in pairs(wData) do
                    if not wExclude[key] then
                        filtered[key] = value
                    end
                end
                controller:ApplyState(filtered)
            end
        end)
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
